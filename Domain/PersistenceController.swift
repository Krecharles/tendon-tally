import Foundation
import os.log

/// JSON-backed persistence layer for storing usage samples.
///
/// This controller manages saving and loading of finalized 5-minute usage windows
/// and the current in-progress sample. Data is stored in daily files in the user's Application Support directory.
final class PersistenceController {
    static let shared = PersistenceController()
    
    private let logger = Logger(subsystem: "com.tendontally", category: "Persistence")

    private(set) var dataDirectory: URL
    private let queue = DispatchQueue(label: "TendonTally.Persistence")
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private nonisolated struct Store: Codable {
        var samples: [UsageSample]
    }

    private nonisolated struct CurrentSampleStore: Codable {
        var currentSample: UsageSample
    }

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let dir = appSupport.appendingPathComponent("TendonTally", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        self.dataDirectory = dir
    }
    
    /// Get the file URL for a specific date's samples
    private func fileURL(for date: Date) -> URL {
        let dateString = dateFormatter.string(from: date)
        return dataDirectory.appendingPathComponent("usage_\(dateString).json", isDirectory: false)
    }
    
    /// Get the file URL for the current sample
    private var currentSampleURL: URL {
        dataDirectory.appendingPathComponent("current.json", isDirectory: false)
    }

    /// Load all stored samples from disk. Returns finalized samples and optionally a current sample if it's still valid.
    func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?) {
        queue.sync {
            var allSamples: [UsageSample] = []
            let fm = FileManager.default
            
            // Load all daily files
            do {
                let files = try fm.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
                let dailyFiles = files.filter { $0.lastPathComponent.hasPrefix("usage_") && $0.lastPathComponent.hasSuffix(".json") }
                
                for fileURL in dailyFiles {
                    guard let data = try? Data(contentsOf: fileURL) else { continue }
                    do {
                        let store = try JSONDecoder().decode(Store.self, from: data)
                        allSamples.append(contentsOf: store.samples)
                    } catch {
                        logger.warning("Failed to decode daily file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.info("No existing data directory or files found, starting fresh")
            }
            
            // Load current sample
            var validCurrentSample: UsageSample? = nil
            if let currentData = try? Data(contentsOf: currentSampleURL) {
                do {
                    let currentStore = try JSONDecoder().decode(CurrentSampleStore.self, from: currentData)
                    let current = currentStore.currentSample
                    let now = Date()
                    let windowLength: TimeInterval = 5 * 60
                    // If the current sample's window hasn't expired, it's still valid
                    if current.end > now && now.timeIntervalSince(current.start) < windowLength {
                        validCurrentSample = current
                        let formatter = ISO8601DateFormatter()
                        logger.info("Loaded valid current sample from \(formatter.string(from: current.start))")
                    } else {
                        logger.info("Current sample expired, discarding")
                    }
                } catch {
                    logger.warning("Failed to decode current sample: \(error.localizedDescription)")
                }
            }
            
            logger.info("Loaded \(allSamples.count) finalized samples from disk")
            return (allSamples, validCurrentSample)
        }
    }

    /// Save a finalized sample to the appropriate daily file.
    func saveFinalizedSample(_ sample: UsageSample) {
        queue.async {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: sample.start)
            let dayFileURL = self.fileURL(for: dayStart)
            
            // Load existing samples for this day
            var daySamples: [UsageSample] = []
            if let data = try? Data(contentsOf: dayFileURL) {
                if let store = try? JSONDecoder().decode(Store.self, from: data) {
                    daySamples = store.samples
                }
            }
            
            // Add the new sample (avoid duplicates by checking ID)
            if !daySamples.contains(where: { $0.id == sample.id }) {
                daySamples.append(sample)
                // Keep samples sorted by start time
                daySamples.sort { $0.start < $1.start }
            }
            
            // Save the day's samples
            let store = Store(samples: daySamples)
            guard let data = try? JSONEncoder().encode(store) else {
                self.logger.error("Failed to encode data for saving finalized sample")
                return
            }
            do {
                try data.write(to: dayFileURL, options: [.atomic])
                self.logger.debug("Saved finalized sample to \(dayFileURL.lastPathComponent)")
            } catch {
                self.logger.error("Failed to write finalized sample to disk: \(error.localizedDescription)")
            }
        }
    }
    
    /// Save the current sample to current.json
    func saveCurrentSample(_ currentSample: UsageSample) {
        queue.async {
            let store = CurrentSampleStore(currentSample: currentSample)
            guard let data = try? JSONEncoder().encode(store) else {
                self.logger.error("Failed to encode current sample for saving")
                return
            }
            do {
                try data.write(to: self.currentSampleURL, options: [.atomic])
                self.logger.debug("Saved current sample (keys: \(currentSample.keyPressCount), clicks: \(currentSample.mouseClickCount))")
            } catch {
                self.logger.error("Failed to write current sample to disk: \(error.localizedDescription)")
            }
        }
    }
    
    /// Legacy method for compatibility - saves current sample only
    func saveSamples(_ samples: [UsageSample], currentSample: UsageSample? = nil) {
        if let current = currentSample {
            saveCurrentSample(current)
        }
        // Note: finalized samples should be saved via saveFinalizedSample
        // This method is kept for backward compatibility but only saves current sample
    }
    
    /// Delete all stored samples from disk.
    func deleteAllSamples() {
        queue.async {
            let fm = FileManager.default
            do {
                // Delete all daily files
                let files = try fm.contentsOfDirectory(at: self.dataDirectory, includingPropertiesForKeys: nil)
                let dailyFiles = files.filter { $0.lastPathComponent.hasPrefix("usage_") && $0.lastPathComponent.hasSuffix(".json") }
                for fileURL in dailyFiles {
                    try? fm.removeItem(at: fileURL)
                }
                
                // Delete current sample file
                if fm.fileExists(atPath: self.currentSampleURL.path) {
                    try fm.removeItem(at: self.currentSampleURL)
                }
                
                self.logger.info("Deleted all stored samples")
            } catch {
                self.logger.error("Failed to delete samples: \(error.localizedDescription)")
            }
        }
    }
    
    /// Generate test data for the last 4 days with 5-minute intervals.
    func generateTestData() {
        queue.async {
            let calendar = Calendar.current
            let now = Date()
            
            // Generate data for the last 4 days
            for dayOffset in 0..<4 {
                guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let startOfDay = calendar.startOfDay(for: dayStart)
                var daySamples: [UsageSample] = []
                
                // Generate 5-minute intervals for the day (288 intervals per day)
                let intervalsPerDay = 288
                let intervalLength: TimeInterval = 5 * 60 // 5 minutes
                
                for intervalIndex in 0..<intervalsPerDay {
                    let intervalStart = startOfDay.addingTimeInterval(TimeInterval(intervalIndex) * intervalLength)
                    let intervalEnd = intervalStart.addingTimeInterval(intervalLength)
                    
                    // Skip future intervals
                    if intervalEnd > now {
                        break
                    }
                    
                    // Generate realistic test data with some variation
                    // Simulate higher activity during "working hours" (9 AM - 5 PM)
                    let hour = calendar.component(.hour, from: intervalStart)
                    let isWorkingHours = hour >= 9 && hour < 17
                    
                    // Base values with some randomness
                    let baseKeys = isWorkingHours ? 150 : 30
                    let baseClicks = isWorkingHours ? 80 : 20
                    let baseScroll = isWorkingHours ? 5000 : 1000
                    let baseMouse = isWorkingHours ? 50000.0 : 10000.0
                    
                    // Add randomness (±30%)
                    let randomFactor = Double.random(in: 0.7...1.3)
                    
                    let sample = UsageSample(
                        id: UUID(),
                        start: intervalStart,
                        end: intervalEnd,
                        keyPressCount: Int(Double(baseKeys) * randomFactor),
                        mouseClickCount: Int(Double(baseClicks) * randomFactor),
                        scrollTicks: Int(Double(baseScroll) * randomFactor),
                        scrollDistance: 0,
                        mouseDistance: baseMouse * randomFactor
                    )
                    
                    daySamples.append(sample)
                }
                
                // Save this day's samples to its daily file
                if !daySamples.isEmpty {
                    let dayFileURL = self.fileURL(for: startOfDay)
                    let store = Store(samples: daySamples)
                    if let data = try? JSONEncoder().encode(store) {
                        do {
                            try data.write(to: dayFileURL, options: [.atomic])
                            self.logger.info("Generated and saved \(daySamples.count) test samples for \(self.dateFormatter.string(from: startOfDay))")
                        } catch {
                            self.logger.error("Failed to save test data for \(self.dateFormatter.string(from: startOfDay)): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

