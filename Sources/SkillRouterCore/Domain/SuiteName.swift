import Foundation

public struct SuiteName: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 128 else {
            throw SkillRouterError.invalidSuiteName(rawValue)
        }
        self.rawValue = value
    }

    public static func < (lhs: SuiteName, rhs: SuiteName) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}
