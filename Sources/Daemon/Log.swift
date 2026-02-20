import Foundation
import os

private let logger = Logger(subsystem: "glass.kagerou.harmaline", category: "daemon")

private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private let logFileURL: URL = {
    let path = "/Library/Logs/Harmaline.log"
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    return URL(fileURLWithPath: path)
}()

func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")

    let line = "[\(logDateFormatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8),
          let handle = try? FileHandle(forWritingTo: logFileURL)
    else { return }
    handle.seekToEndOfFile()
    handle.write(data)
    try? handle.close()
}
