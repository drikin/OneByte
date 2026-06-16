import Foundation

/// Manages the user dictionary for OneByte IME.
/// Dictionary file: ~/.onebyte/user_dict.json
/// All keys are normalized to lowercase.
struct UserDictionary: Sendable {
    private var entries: [String: String] = [:]
    private let fileURL: URL
    private let lock = NSLock()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".onebyte")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("user_dict.json")
        load()
    }

    /// Load dictionary from file
    mutating func load() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            entries = [:]
            return
        }
        entries = json
    }

    /// Save dictionary to file
    func save() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Add or update an entry. Key is normalized to lowercase.
    mutating func set(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key.lowercased()] = value
        save()
    }

    /// Remove an entry. Key is normalized to lowercase.
    mutating func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key.lowercased())
        save()
    }

    /// Look up a normalized key.
    func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key.lowercased()]
    }

    /// Check if a key exists (lowercased)
    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.keys.contains(key.lowercased())
    }

    /// All entries (for UI display)
    var allEntries: [(key: String, value: String)] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Count
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // ── Dictionary matching with placeholder substitution ──

    /// Match dictionary entries in the input text using longest-match.
    /// Returns the text with placeholders substituted, and a mapping of placeholder IDs to values.
    /// Example: "watashi wa drikin desu" → ("watashi wa §0 desu", [0: "ドリキン"])
    func matchAndReplace(_ text: String) -> (modified: String, placeholders: [Int: String]) {
        let lower = text.lowercased()
        var placeholders: [Int: String] = [:]
        var result = text  // Keep original case for non-matched parts
        var pid = 0

        lock.lock()
        defer { lock.unlock() }

        // Sort keys by length descending for longest-match
        let sortedKeys = entries.keys.sorted { $0.count > $1.count }

        for key in sortedKeys {
            guard let value = entries[key] else { continue }
            // Search in lowercased version but replace in original
            var searchRange = lower.startIndex..<lower.endIndex
            while let range = lower.range(of: key, options: [], range: searchRange) {
                // Make sure it's a word boundary (space or start/end)
                let before = range.lowerBound > lower.startIndex ? lower[lower.index(before: range.lowerBound)] : " "
                let after = range.upperBound < lower.endIndex ? lower[range.upperBound] : " "
                if before.isWhitespace && after.isWhitespace {
                    let placeholder = "§\(pid)"
                    result.replaceSubrange(range, with: placeholder)
                    placeholders[pid] = value
                    pid += 1
                    // Update search range to skip the inserted placeholder
                    let newEnd = result.index(result.startIndex, offsetBy: placeholder.count)
                    searchRange = newEnd..<result.endIndex
                } else {
                    searchRange = range.upperBound..<lower.endIndex
                }
            }
        }

        return (result, placeholders)
    }

    /// Restore placeholders in LLM output with dictionary values.
    func restorePlaceholders(in text: String, placeholders: [Int: String]) -> String {
        var result = text
        for (pid, value) in placeholders.sorted(by: { $0.key > $1.key }) {
            result = result.replacingOccurrences(of: "§\(pid)", with: value)
        }
        return result
    }
}
