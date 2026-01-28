import Foundation

/// Very small JSON-backed persistence layer for finalized 5‑minute usage windows.
/// This keeps all `UsageSample` windows so we can build daily/weekly analytics later.
final class PersistenceController {
    static let shared = PersistenceController()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "ActivityTracker.Persistence")

    private struct Store: Codable {
        var samples: [UsageSample]
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

    /// Load all stored samples from disk. Returns an empty array if the file is missing or invalid.
    func loadSamples() -> [UsageSample] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            do {
                let store = try JSONDecoder().decode(Store.self, from: data)
                return store.samples
            } catch {
                return []
            }
        }
    }

    /// Persist the given samples to disk, overwriting any previous contents.
    func saveSamples(_ samples: [UsageSample]) {
        queue.async {
            let store = Store(samples: samples)
            guard let data = try? JSONEncoder().encode(store) else { return }
            try? data.write(to: self.fileURL, options: [.atomic])
        }
    }
}

