import Foundation

/// Append-only newline-delimited JSON file with one rotation generation.
/// Not thread-safe: the owner serializes access on its own queue.
final class JSONLinesFile {
    let url: URL
    private let limit: UInt64
    private var handle: FileHandle?
    private var bytesWritten: UInt64 = 0
    init(url: URL, limit: UInt64) {
        self.url = url
        self.limit = limit
    }
    func append(_ line: Data) throws {
        if handle == nil { try open() }
        if bytesWritten + UInt64(line.count) > limit { try rotate() }
        try handle?.write(contentsOf: line)
        bytesWritten += UInt64(line.count)
    }
    func synchronize() { try? handle?.synchronize() }
    private func open() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        handle = try FileHandle(forWritingTo: url)
        bytesWritten = try handle?.seekToEnd() ?? 0
    }
    private func rotate() throws {
        try handle?.close()
        handle = nil
        let manager = FileManager.default
        let previous = url.deletingPathExtension().appendingPathExtension("previous.jsonl")
        if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
        try manager.moveItem(at: url, to: previous)
        try open()
    }
}
