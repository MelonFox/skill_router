import Foundation

public struct DirectoryCopier {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func copy(
        from source: URL,
        to destination: URL,
        excludingNames: Set<String> = []
    ) throws {
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: linkDestination)
            return
        }
        if values.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children where !excludingNames.contains(child.lastPathComponent) {
                try copy(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    excludingNames: excludingNames
                )
            }
            return
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
