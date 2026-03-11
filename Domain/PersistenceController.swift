import Foundation
import os.log

/// CSV-backed persistence layer for storing usage samples.
///
/// Finalized samples are stored per day in compact CSV files (`usage_yyyy-MM-dd.csv`) with
/// 5-minute bucket rows, while `daily_index.json` stores fast day-level totals for analytics.
///
/// On first run, legacy JSON day files are migrated into the CSV format.
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

    private let csvHeader = "b,k,c,s,mp\n"
    private let bucketDuration: TimeInterval = 5 * 60
    private let bucketsPerDay = 24 * 60 / 5

    private nonisolated struct CurrentSampleStore: Codable {
        var currentSample: UsageSample
    }

    private nonisolated struct DailyIndexFile: Codable {
        var version: Int
        var days: [String: DailyIndexEntry]
    }

    private nonisolated struct DailyIndexEntry: Codable {
        var keyPressCount: Int
        var mouseClickCount: Int
        var scrollTicks: Int
        var mousePixels: Int
        var activeBuckets: Int
    }

    private nonisolated struct BucketTotals {
        var keyPressCount: Int
        var mouseClickCount: Int
        var scrollTicks: Int
        var mousePixels: Int

        var hasActivity: Bool {
            keyPressCount > 0 || mouseClickCount > 0 || scrollTicks > 0 || mousePixels > 0
        }
    }

    init(dataDirectory: URL? = nil) {
        let fm = FileManager.default
        let dir = dataDirectory ?? Self.defaultDataDirectory()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        self.dataDirectory = dir
    }

    private static func defaultDataDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("TendonTally", isDirectory: true)
    }

    private func csvURL(for dayStart: Date) -> URL {
        let dateString = dateFormatter.string(from: dayStart)
        return dataDirectory.appendingPathComponent("usage_\(dateString).csv", isDirectory: false)
    }

    private func dayFromCSVFilename(_ fileURL: URL) -> Date? {
        let name = fileURL.lastPathComponent
        guard name.hasPrefix("usage_"), name.hasSuffix(".csv") else { return nil }
        let dateString = String(name.dropFirst("usage_".count).dropLast(".csv".count))
        return dateFormatter.date(from: dateString)
    }

    private var currentSampleURL: URL {
        dataDirectory.appendingPathComponent("current.json", isDirectory: false)
    }

    private var dailyIndexURL: URL {
        dataDirectory.appendingPathComponent("daily_index.json", isDirectory: false)
    }

    /// Load all stored samples and the current in-progress sample from disk.
    ///
    /// The current sample is returned as-is without time validation — the caller
    /// is responsible for deciding whether to continue or finalize it.
    func loadSamples() -> (samples: [UsageSample], currentSample: UsageSample?) {
        queue.sync {
            var allSamples: [UsageSample] = []
            let fm = FileManager.default
            let calendar = Calendar.current

            do {
                let files = try fm.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)
                let dailyCSVFiles = files
                    .filter { $0.lastPathComponent.hasPrefix("usage_") && $0.pathExtension == "csv" }
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

                for fileURL in dailyCSVFiles {
                    guard let dayStart = dayFromCSVFilename(fileURL) else { continue }
                    let buckets = loadDayBuckets(from: fileURL)

                    for (bucketIndex, totals) in buckets.sorted(by: { $0.key < $1.key }) {
                        let start = dayStart.addingTimeInterval(TimeInterval(bucketIndex) * bucketDuration)
                        let end = start.addingTimeInterval(bucketDuration)
                        allSamples.append(
                            UsageSample(
                                id: UUID(),
                                start: start,
                                end: end,
                                keyPressCount: totals.keyPressCount,
                                mouseClickCount: totals.mouseClickCount,
                                scrollTicks: totals.scrollTicks,
                                scrollDistance: 0,
                                mouseDistance: Double(totals.mousePixels)
                            )
                        )
                    }
                }
            } catch {
                logger.info("No existing CSV files found, starting fresh")
            }

            // Load current sample without time validation
            var currentSample: UsageSample? = nil
            if let currentData = try? Data(contentsOf: currentSampleURL) {
                do {
                    let currentStore = try JSONDecoder().decode(CurrentSampleStore.self, from: currentData)
                    currentSample = currentStore.currentSample
                    let formatter = ISO8601DateFormatter()
                    logger.info("Loaded current sample from \(formatter.string(from: currentStore.currentSample.start))")
                } catch {
                    logger.warning("Failed to decode current sample: \(error.localizedDescription)")
                }
            }

            // Ensure loaded rows are valid and ordered newest-first for caller compatibility.
            allSamples = allSamples
                .filter { sample in
                    let startOfDay = calendar.startOfDay(for: sample.start)
                    return sample.start >= startOfDay && sample.end > sample.start
                }
                .sorted { $0.start > $1.start }

            logger.info("Loaded \(allSamples.count) finalized samples from disk")
            return (allSamples, currentSample)
        }
    }

    /// Save a finalized sample to the appropriate daily file.
    func saveFinalizedSample(_ sample: UsageSample) {
        queue.async {
            self.writeFinalizedSampleOnQueue(sample)
        }
    }

    /// Save a finalized sample synchronously (blocks until written).
    func saveFinalizedSampleSync(_ sample: UsageSample) {
        queue.sync {
            self.writeFinalizedSampleOnQueue(sample)
        }
    }

    private func writeFinalizedSampleOnQueue(_ sample: UsageSample) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: sample.start)
        let dayFileURL = csvURL(for: dayStart)
        let bucketIndex = bucketIndexForDate(sample.start, calendar: calendar)

        guard bucketIndex >= 0 && bucketIndex < bucketsPerDay else {
            logger.warning("Skipping sample with invalid 5-minute bucket index")
            return
        }

        var dayBuckets = loadDayBuckets(from: dayFileURL)
        let totals = BucketTotals(
            keyPressCount: sample.keyPressCount,
            mouseClickCount: sample.mouseClickCount,
            scrollTicks: sample.scrollTicks,
            mousePixels: max(0, Int(sample.mouseDistance.rounded()))
        )

        if totals.hasActivity {
            dayBuckets[bucketIndex] = totals
        } else {
            dayBuckets.removeValue(forKey: bucketIndex)
        }

        writeDayBuckets(dayBuckets, to: dayFileURL)
        updateDailyIndex(for: dayStart, buckets: dayBuckets)
        logger.debug("Saved finalized bucket \(bucketIndex) for day \(dayFileURL.lastPathComponent)")
    }

    /// Save the current sample asynchronously.
    func saveCurrentSample(_ currentSample: UsageSample) {
        queue.async {
            self.writeCurrentSample(currentSample)
        }
    }

    /// Save the current sample synchronously (blocks until written). Use during shutdown.
    func saveCurrentSampleSync(_ currentSample: UsageSample) {
        queue.sync {
            self.writeCurrentSample(currentSample)
        }
    }

    private func writeCurrentSample(_ currentSample: UsageSample) {
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

    /// Delete the current sample file (e.g. after finalizing a restored expired sample).
    func deleteCurrentSample() {
        queue.async {
            let fm = FileManager.default
            if fm.fileExists(atPath: self.currentSampleURL.path) {
                try? fm.removeItem(at: self.currentSampleURL)
            }
        }
    }

    /// Delete all stored samples from disk asynchronously.
    func deleteAllSamples(completion: (() -> Void)? = nil) {
        queue.async {
            self.removeAllSamplesOnQueue()
            guard let completion else { return }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Delete all stored samples from disk synchronously.
    func deleteAllSamplesSync() {
        queue.sync {
            self.removeAllSamplesOnQueue()
        }
    }

    private func removeAllSamplesOnQueue() {
        let fm = FileManager.default
        do {
            let files = try fm.contentsOfDirectory(at: self.dataDirectory, includingPropertiesForKeys: nil)
            let usageFiles = files.filter { fileURL in
                fileURL.lastPathComponent.hasPrefix("usage_") &&
                (fileURL.pathExtension == "csv" || fileURL.pathExtension == "json")
            }
            for fileURL in usageFiles {
                try? fm.removeItem(at: fileURL)
            }

            if fm.fileExists(atPath: self.currentSampleURL.path) {
                try fm.removeItem(at: self.currentSampleURL)
            }
            if fm.fileExists(atPath: self.dailyIndexURL.path) {
                try fm.removeItem(at: self.dailyIndexURL)
            }

            self.logger.info("Deleted all stored samples")
        } catch {
            self.logger.error("Failed to delete samples: \(error.localizedDescription)")
        }
    }

    /// Generate test data for the last 4 days with 5-minute intervals.
    func generateTestData() {
        queue.async {
            let calendar = Calendar.current
            let now = Date()

            self.removeAllSamplesOnQueue()

            for dayOffset in 0..<4 {
                guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                let dayStart = calendar.startOfDay(for: dayDate)
                let dayURL = self.csvURL(for: dayStart)
                var dayBuckets: [Int: BucketTotals] = [:]

                for bucketIndex in 0..<self.bucketsPerDay {
                    let bucketStart = dayStart.addingTimeInterval(TimeInterval(bucketIndex) * self.bucketDuration)
                    let bucketEnd = bucketStart.addingTimeInterval(self.bucketDuration)
                    if bucketEnd > now { break }

                    let hour = calendar.component(.hour, from: bucketStart)
                    let isWorkingHours = hour >= 9 && hour < 17
                    let isActiveBucket = Double.random(in: 0...1) < (isWorkingHours ? 0.85 : 0.35)
                    guard isActiveBucket else { continue }

                    let baseKeys = isWorkingHours ? 450 : 100
                    let baseClicks = isWorkingHours ? 220 : 50
                    let baseScroll = isWorkingHours ? 12000 : 3000
                    let baseMouse = isWorkingHours ? 120000 : 30000
                    let randomFactor = Double.random(in: 0.7...1.3)

                    dayBuckets[bucketIndex] = BucketTotals(
                        keyPressCount: Int(Double(baseKeys) * randomFactor),
                        mouseClickCount: Int(Double(baseClicks) * randomFactor),
                        scrollTicks: Int(Double(baseScroll) * randomFactor),
                        mousePixels: Int(Double(baseMouse) * randomFactor)
                    )
                }

                self.writeDayBuckets(dayBuckets, to: dayURL)
                self.updateDailyIndex(for: dayStart, buckets: dayBuckets)
                self.logger.info("Generated \(dayBuckets.count) 5-minute test buckets for \(self.dateFormatter.string(from: dayStart))")
            }
        }
    }

    // MARK: - CSV / Index helpers

    private func loadDayBuckets(from fileURL: URL) -> [Int: BucketTotals] {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var buckets: [Int: BucketTotals] = [:]
        let lines = content.split(whereSeparator: \.isNewline)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if line == "b,k,c,s,mp" { continue }

            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 5,
                  let bucketIndex = Int(parts[0]),
                  let keys = Int(parts[1]),
                  let clicks = Int(parts[2]),
                  let scroll = Int(parts[3]),
                  let mousePixels = Int(parts[4]) else {
                continue
            }

            guard bucketIndex >= 0 && bucketIndex < bucketsPerDay else {
                continue
            }

            buckets[bucketIndex] = BucketTotals(
                keyPressCount: keys,
                mouseClickCount: clicks,
                scrollTicks: scroll,
                mousePixels: mousePixels
            )
        }

        return buckets
    }

    private func writeDayBuckets(_ buckets: [Int: BucketTotals], to fileURL: URL) {
        let activeBuckets = buckets.filter { $0.value.hasActivity }

        if activeBuckets.isEmpty {
            let fm = FileManager.default
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: fileURL)
            }
            return
        }

        var output = csvHeader
        for bucketIndex in activeBuckets.keys.sorted() {
            guard let totals = activeBuckets[bucketIndex] else { continue }
            output += "\(bucketIndex),\(totals.keyPressCount),\(totals.mouseClickCount),\(totals.scrollTicks),\(totals.mousePixels)\n"
        }

        do {
            try output.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Failed to write CSV day file \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func bucketIndexForDate(_ date: Date, calendar: Calendar) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let secondsIntoDay = max(0, Int(date.timeIntervalSince(startOfDay)))
        return secondsIntoDay / Int(bucketDuration)
    }

    private func loadDailyIndexOnQueue() -> [String: DailyIndexEntry] {
        guard let data = try? Data(contentsOf: dailyIndexURL) else {
            return [:]
        }

        do {
            let indexFile = try JSONDecoder().decode(DailyIndexFile.self, from: data)
            return indexFile.days
        } catch {
            logger.warning("Failed to decode daily index: \(error.localizedDescription)")
            return [:]
        }
    }

    private func writeDailyIndexOnQueue(_ days: [String: DailyIndexEntry]) {
        let file = DailyIndexFile(version: 1, days: days)
        guard let data = try? JSONEncoder().encode(file) else {
            logger.error("Failed to encode daily index")
            return
        }

        do {
            try data.write(to: dailyIndexURL, options: [.atomic])
        } catch {
            logger.error("Failed to write daily index: \(error.localizedDescription)")
        }
    }

    private func updateDailyIndex(for dayStart: Date, buckets: [Int: BucketTotals]) {
        let dayKey = dateFormatter.string(from: dayStart)
        let activeBuckets = buckets.values.filter(\.hasActivity)

        var days = loadDailyIndexOnQueue()
        if activeBuckets.isEmpty {
            days.removeValue(forKey: dayKey)
            writeDailyIndexOnQueue(days)
            return
        }

        let entry = DailyIndexEntry(
            keyPressCount: activeBuckets.reduce(0) { $0 + $1.keyPressCount },
            mouseClickCount: activeBuckets.reduce(0) { $0 + $1.mouseClickCount },
            scrollTicks: activeBuckets.reduce(0) { $0 + $1.scrollTicks },
            mousePixels: activeBuckets.reduce(0) { $0 + $1.mousePixels },
            activeBuckets: activeBuckets.count
        )

        days[dayKey] = entry
        writeDailyIndexOnQueue(days)
    }

}
