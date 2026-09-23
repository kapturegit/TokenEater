import Foundation
import Combine

final class TokenFileMonitor: TokenFileMonitorProtocol {
    private let subject = PassthroughSubject<Void, Never>()
    private let codexSubject = PassthroughSubject<Void, Never>()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let debounceInterval: TimeInterval
    /// Per-vendor debounce: one shared timestamp would let a busy Claude
    /// refresh swallow a Codex event that landed inside the same window.
    private var lastEmit: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.tokeneater.filemonitor", qos: .utility)
    private let watchedDirectories: [String]
    private let watchedFilenames: [String: String] // directory -> filename
    private var lastModDates: [String: Date] = [:]
    /// Directory whose events route to `codexSubject` instead of `subject`.
    private let codexDirectory: String?

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    var codexCredentialsChanged: AnyPublisher<Void, Never> { codexSubject.eraseToAnyPublisher() }

    init(debounceInterval: TimeInterval = 2.0) {
        self.debounceInterval = debounceInterval
        guard let pw = getpwuid(getuid()) else {
            watchedDirectories = []
            watchedFilenames = [:]
            codexDirectory = nil
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        let claudeDir = home + "/Library/Application Support/Claude"
        let dotClaudeDir = home + "/.claude"
        // `CODEX_HOME` relocates the Codex config directory; match
        // `CodexAuthReader` so a relocated install is still watched.
        let codexDir: String = {
            if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
                return (override as NSString).expandingTildeInPath
            }
            return home + "/.codex"
        }()
        codexDirectory = codexDir
        watchedDirectories = [claudeDir, dotClaudeDir, codexDir]
        watchedFilenames = [
            claudeDir: "config.json",
            dotClaudeDir: ".credentials.json",
            codexDir: "auth.json",
        ]
    }

    func startMonitoring() {
        stopMonitoring()
        for dir in watchedDirectories {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: .write, queue: queue
            )
            source.setEventHandler { [weak self] in self?.handleDirectoryChange(dir) }
            source.setCancelHandler { close(fd) }
            sources.append(source)
            source.resume()
            // Record initial modification date
            if let filename = watchedFilenames[dir] {
                lastModDates[dir + "/" + filename] = modDate(dir + "/" + filename)
            }
        }
    }

    func stopMonitoring() {
        for source in sources { source.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    private func handleDirectoryChange(_ dir: String) {
        guard let filename = watchedFilenames[dir] else { return }
        let path = dir + "/" + filename
        let newDate = modDate(path)
        guard let date = newDate, date != lastModDates[path] else { return }
        lastModDates[path] = date
        let now = Date()
        guard now.timeIntervalSince(lastEmit[dir] ?? .distantPast) >= debounceInterval else { return }
        lastEmit[dir] = now
        if dir == codexDirectory {
            codexSubject.send(())
        } else {
            subject.send(())
        }
    }

    private func modDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    deinit { stopMonitoring() }
}
