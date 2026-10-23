import Foundation

// Use macOS's own bookmark encoder for Finder background references.
let file = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try file.bookmarkData(options: [.suitableForBookmarkFile],
    includingResourceValuesForKeys: nil, relativeTo: file.deletingLastPathComponent())
FileHandle.standardOutput.write(data)
