import Foundation

public struct VersionedJSONCodec: Sendable {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            var data = try encoder.encode(value)
            data.append(0x0A)
            return data
        } catch {
            throw SkillRouterError.invalidJSON(error.localizedDescription)
        }
    }

    public func decodeRouterState(_ data: Data) throws -> RouterState {
        try validate(data, document: "state.json", supportedVersion: RouterState.currentSchemaVersion)
        var value: RouterState = try decode(data)
        value.normalize()
        return value
    }

    public func decodeProjectManifest(_ data: Data) throws -> ProjectManifest {
        try validate(data, document: ".skill-router.json", supportedVersion: ProjectManifest.currentSchemaVersion)
        var value: ProjectManifest = try decode(data)
        value.normalize()
        try value.validate()
        return value
    }

    public func decodeArtifactManifest(_ data: Data) throws -> ArtifactManifest {
        try validate(data, document: "制品清单", supportedVersion: ArtifactManifest.currentSchemaVersion)
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as SkillRouterError {
            throw error
        } catch {
            throw SkillRouterError.invalidJSON(error.localizedDescription)
        }
    }

    private func validate(_ data: Data, document: String, supportedVersion: Int) throws {
        var duplicateKeyValidator = JSONDuplicateKeyValidator()
        try duplicateKeyValidator.validate(data)
        let envelope: SchemaEnvelope = try decode(data)
        guard envelope.schemaVersion == supportedVersion else {
            throw SkillRouterError.unsupportedSchema(document: document, version: envelope.schemaVersion)
        }
    }
}

private struct SchemaEnvelope: Decodable {
    let schemaVersion: Int
}

private struct JSONDuplicateKeyValidator {
    private var bytes: [UInt8] = []
    private var index = 0

    mutating func validate(_ data: Data) throws {
        bytes = Array(data)
        index = 0
        skipWhitespace()
        try parseValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw SkillRouterError.invalidJSON("根值之后存在多余内容")
        }
    }

    private mutating func parseValue() throws {
        skipWhitespace()
        guard index < bytes.count else {
            throw SkillRouterError.invalidJSON("JSON 意外结束")
        }
        switch bytes[index] {
        case 0x7B: try parseObject()
        case 0x5B: try parseArray()
        case 0x22: _ = try parseString()
        case 0x74: try consume("true")
        case 0x66: try consume("false")
        case 0x6E: try consume("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw SkillRouterError.invalidJSON("位置 \(index) 存在非法值")
        }
    }

    private mutating func parseObject() throws {
        index += 1
        skipWhitespace()
        if consumeIf(0x7D) { return }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw SkillRouterError.invalidJSON("对象键必须是字符串")
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw SkillRouterError.invalidJSON("对象包含重复字段：\(key)")
            }
            skipWhitespace()
            guard consumeIf(0x3A) else {
                throw SkillRouterError.invalidJSON("对象键后缺少冒号")
            }
            try parseValue()
            skipWhitespace()
            if consumeIf(0x7D) { return }
            guard consumeIf(0x2C) else {
                throw SkillRouterError.invalidJSON("对象成员之间缺少逗号")
            }
        }
    }

    private mutating func parseArray() throws {
        index += 1
        skipWhitespace()
        if consumeIf(0x5D) { return }
        while true {
            try parseValue()
            skipWhitespace()
            if consumeIf(0x5D) { return }
            guard consumeIf(0x2C) else {
                throw SkillRouterError.invalidJSON("数组成员之间缺少逗号")
            }
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if escaped {
                if byte == 0x75 {
                    guard index + 4 <= bytes.count,
                          bytes[index..<(index + 4)].allSatisfy(Self.isHexDigit) else {
                        throw SkillRouterError.invalidJSON("字符串包含非法 Unicode 转义")
                    }
                    index += 4
                } else if ![0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(byte) {
                    throw SkillRouterError.invalidJSON("字符串包含非法转义")
                }
                escaped = false
            } else if byte == 0x5C {
                escaped = true
            } else if byte == 0x22 {
                let data = Data(bytes[start..<index])
                do {
                    return try JSONDecoder().decode(String.self, from: data)
                } catch {
                    throw SkillRouterError.invalidJSON("字符串编码无效")
                }
            } else if byte < 0x20 {
                throw SkillRouterError.invalidJSON("字符串包含控制字符")
            }
        }
        throw SkillRouterError.invalidJSON("字符串未闭合")
    }

    private mutating func parseNumber() throws {
        let start = index
        if consumeIf(0x2D), index >= bytes.count {
            throw SkillRouterError.invalidJSON("数字不完整")
        }
        if consumeIf(0x30) {
            if index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                throw SkillRouterError.invalidJSON("数字不能包含前导零")
            }
        } else {
            guard consumeDigits(requireOne: true) else {
                throw SkillRouterError.invalidJSON("数字整数部分无效")
            }
        }
        if consumeIf(0x2E), !consumeDigits(requireOne: true) {
            throw SkillRouterError.invalidJSON("数字小数部分无效")
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            guard consumeDigits(requireOne: true) else {
                throw SkillRouterError.invalidJSON("数字指数部分无效")
            }
        }
        guard index > start else {
            throw SkillRouterError.invalidJSON("数字无效")
        }
    }

    @discardableResult
    private mutating func consumeDigits(requireOne: Bool) -> Bool {
        let start = index
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        return !requireOne || index > start
    }

    private mutating func consume(_ literal: StaticString) throws {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else {
            throw SkillRouterError.invalidJSON("位置 \(index) 存在非法字面量")
        }
        index += expected.count
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
}
