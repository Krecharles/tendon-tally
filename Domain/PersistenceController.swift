import Foundation
import os.log

/// JSON-backed persistence layer for storing usage samples.
///
/// This controller manages saving and loading of finalized 5-minute usage windows
/// and the current in-progress sample. Data is stored in the user's Application Support directory.
final class PersistenceController {
    static let shared = PersistenceController()
    
    private let logger = Logger(subsystem: "com.activitytracker", category: "Persistence")

    private let fileURL: URL
    private let queue = DispatchQueue(label: "ActivityTracker.Persistence")

    private struct Store: Codable {
        var samples: [UsageSample]
        var currentSample: UsageSample?
        
        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(samples, forKey: .samples)
            try container.encodeIfPresent(currentSample, forKey: .currentSample)
        }
        
        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            samples = try container.decode([UsageSample].self, forKey: .samples)
            currentSample = try container.decodeIfPresent(UsageSample.self, forKey: .currentSample)
        }
        
        nonisolated init(samples: [UsageSample], currentSample: UsageSample? = nil) {
            self.samples = samples
            self.currentSample = currentSample
        }
        
        enum CodingKeys: String, CodingKey {
            case samples
            case currentSample
        }
    }

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let dir = appSupport.appendingPathComponent("ActivityTracker", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        self.fileURL = dir.appendingPathComponent("usage.json", isDirectory: false)
    }

    /// Load all stored samples from disk. Returns finalized samples and optionally a current sample if it's still valid.
    func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?) {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else {
                logger.info("No existing data file found, starting fresh")
                return ([], nil)
            }
            do {
                let store = try JSONDecoder().decode(Store.self, from: data)
                
                // Check if current sample is still valid (not older than 5 minutes)
                var validCurrentSample: UsageSample? = nil
                if let current = store.currentSample {
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
                }
                
                logger.info("Loaded \(store.samples.count) finalized samples from disk")
                return (store.samples, validCurrentSample)
            } catch {
                logger.error("Failed to decode stored data: \(error.localizedDescription)")
                return ([], nil)
            }
        }
    }

    /// Persist the given samples to disk, overwriting any previous contents.
    func saveSamples(_ samples: [UsageSample], currentSample: UsageSample? = nil) {
        queue.async {
            let store = Store(samples: samples, currentSample: currentSample)
            guard let data = try? JSONEncoder().encode(store) else {
                self.logger.error("Failed to encode data for saving")
                return
            }
            do {
                try data.write(to: self.fileURL, options: [.atomic])
                if let current = currentSample {
                    self.logger.info("Saved \(samples.count) samples and current sample (keys: \(current.keyPressCount), clicks: \(current.mouseClickCount))")
                } else {
                    self.logger.info("Saved \(samples.count) samples (no current sample)")
                }
            } catch {
                self.logger.error("Failed to write data to disk: \(error.localizedDescription)")
            }
        }
    }
    
    /// Delete all stored samples from disk.
    func deleteAllSamples() {
        queue.async {
            let emptyStore = Store(samples: [], currentSample: nil)
            guard let data = try? JSONEncoder().encode(emptyStore) else {
                self.logger.error("Failed to encode empty store for deletion")
                return
            }
            do {
                try data.write(to: self.fileURL, options: [.atomic])
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
            var samples: [UsageSample] = []
            
            // Generate data for the last 4 days
            for dayOffset in 0..<4 {
                guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let startOfDay = calendar.startOfDay(for: dayStart)
                
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
                    
                    samples.append(sample)
                }
            }
            
            // Sort by start time (newest first)
            samples.sort { $0.start > $1.start }
            
            // Save the test data
            let store = Store(samples: samples, currentSample: nil)
            guard let data = try? JSONEncoder().encode(store) else {
                self.logger.error("Failed to encode test data")
                return
            }
            do {
                try data.write(to: self.fileURL, options: [.atomic])
                self.logger.info("Generated and saved \(samples.count) test samples for the last 4 days")
            } catch {
                self.logger.error("Failed to save test data: \(error.localizedDescription)")
            }
        }
    }
}

