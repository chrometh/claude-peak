import Foundation

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published var tokensPerSecond: Double = 0
    @Published var remoteConnected: Bool = false

    private let claudeDir: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileHandles: [URL: UInt64] = [:] // file -> last read offset
    private var recentTokens: [(date: Date, tokens: Int)] = []
    private var remoteTokens: [(date: Date, tokens: Int)] = []
    private var scanTimer: Timer?
    private var remoteTimer: Timer?
    private let settings = AppSettings.shared

    init() {
        claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func start() {
        // Scan every 2 seconds for new tokens in JSONL files
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanForNewTokens()
            }
        }
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchRemoteTokens()
            }
        }
        scanForNewTokens()
        Task { await fetchRemoteTokens() }
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
        remoteTimer?.invalidate()
        remoteTimer = nil
    }

    private func scanForNewTokens() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-60) // only check files modified in last 60s

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Only process recently modified files
            if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modDate < cutoff {
                continue
            }

            readNewLines(from: fileURL)
        }

        // Clean old entries (older than 30 seconds)
        let windowStart = Date().addingTimeInterval(-30)
        recentTokens.removeAll { $0.date < windowStart }
        remoteTokens.removeAll { $0.date < windowStart }

        recalculate()
    }

    private func recalculate() {
        let localTotal = recentTokens.reduce(0) { $0 + $1.tokens }
        let remoteTotal = remoteTokens.reduce(0) { $0 + $1.tokens }
        let window: Double = 30
        tokensPerSecond = Double(localTotal + remoteTotal) / window
        Log.info("TPS: \(Int(tokensPerSecond)) (local: \(localTotal), remote: \(remoteTotal), remoteEntries: \(remoteTokens.count))")
    }

    private func fetchRemoteTokens() async {
        guard settings.remoteEnabled else {
            if remoteConnected { remoteConnected = false }
            remoteTokens.removeAll()
            return
        }

        let urlString = "http://\(settings.remoteHost):\(settings.remotePort)/api/activity"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            Log.info("Remote fetch: \(urlString)")
            let (data, _) = try await URLSession.shared.data(for: request)
            Log.info("Remote response: \(data.count) bytes")
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["recentTokens"] as? [[String: Any]] else {
                Log.info("Remote parse failed")
                remoteConnected = false
                return
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()

            remoteTokens = entries.compactMap { entry in
                guard let dateStr = entry["date"] as? String else { return nil }
                let tokens: Int
                if let t = entry["tokens"] as? Int {
                    tokens = t
                } else if let t = entry["tokens"] as? Double {
                    tokens = Int(t)
                } else {
                    return nil
                }
                let date = formatter.date(from: dateStr) ?? fallback.date(from: dateStr) ?? Date()
                return (date: date, tokens: tokens)
            }

            remoteConnected = true
            recalculate()
        } catch {
            Log.info("Remote error: \(error)")
            remoteConnected = false
            remoteTokens.removeAll()
            recalculate()
        }
    }

    private func readNewLines(from url: URL) {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fileHandle.close() }

        let lastOffset = fileHandles[url] ?? {
            // First time seeing this file: seek to end (only read new data)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return size
        }()

        fileHandle.seek(toFileOffset: lastOffset)
        let newData = fileHandle.readDataToEndOfFile()
        let currentOffset = fileHandle.offsetInFile
        fileHandles[url] = currentOffset

        guard !newData.isEmpty,
              let text = String(data: newData, encoding: .utf8) else { return }

        let now = Date()
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            let total = input + output + cacheRead + cacheCreate

            if total > 0 {
                recentTokens.append((date: now, tokens: total))
            }
        }
    }
}
