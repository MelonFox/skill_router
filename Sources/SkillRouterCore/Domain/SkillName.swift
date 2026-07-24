import Foundation

public struct SkillName: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw SkillRouterError.invalidSkillName(rawValue)
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: SkillName, rhs: SkillName) -> Bool {
        lhs.rawValue < rhs.rawValue
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

    public static func isValid(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count),
              value.first != "-",
              value.last != "-",
              !value.contains("--") else {
            return false
        }

        return value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) ||
                (byte >= 48 && byte <= 57) ||
                byte == 45
        }
    }
}
