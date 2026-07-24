import Foundation

public struct ParsedSkillManifest: Equatable, Sendable {
    public let name: SkillName
    public let frontmatter: [String: String]

    public init(name: SkillName, frontmatter: [String: String]) {
        self.name = name
        self.frontmatter = frontmatter
    }
}

public struct SkillManifestParser: Sendable {
    public init() {}

    public func parse(fileAt url: URL) throws -> ParsedSkillManifest {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return try parse(content)
        } catch let error as SkillRouterError {
            throw error
        } catch {
            throw SkillRouterError.malformedSkillManifest(error.localizedDescription)
        }
    }

    public func parse(_ content: String) throws -> ParsedSkillManifest {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else {
            throw SkillRouterError.malformedSkillManifest("缺少起始 YAML frontmatter 分隔符")
        }
        guard let end = lines.dropFirst().firstIndex(of: "---") else {
            throw SkillRouterError.malformedSkillManifest("缺少结束 YAML frontmatter 分隔符")
        }

        var values: [String: String] = [:]
        var index = 1
        while index < end {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            index += 1

            if trimmed.isEmpty || trimmed.hasPrefix("#") || rawLine.first?.isWhitespace == true {
                continue
            }
            guard let colon = rawLine.firstIndex(of: ":") else {
                throw SkillRouterError.malformedSkillManifest("第 \(index) 行不是合法的顶层键值")
            }
            let key = String(rawLine[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(rawLine[rawLine.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw SkillRouterError.malformedSkillManifest("第 \(index) 行键名为空")
            }

            if value == "|" || value == ">" {
                var block: [String] = []
                while index < end, lines[index].first?.isWhitespace == true {
                    block.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = value == "|" ? block.joined(separator: "\n") : block.joined(separator: " ")
            } else {
                value = try decodeScalar(value, line: index)
            }
            values[key] = value
        }

        guard let rawName = values["name"], !rawName.isEmpty else {
            throw SkillRouterError.malformedSkillManifest("frontmatter 缺少 name")
        }
        return ParsedSkillManifest(name: try SkillName(rawValue: rawName), frontmatter: values)
    }

    private func decodeScalar(_ source: String, line: Int) throws -> String {
        guard !source.isEmpty else { return "" }
        if source.first == "\"" {
            guard source.last == "\"", source.count >= 2 else {
                throw SkillRouterError.malformedSkillManifest("第 \(line) 行双引号未闭合")
            }
            let inner = String(source.dropFirst().dropLast())
            var result = ""
            var escaped = false
            for character in inner {
                if escaped {
                    switch character {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default:
                        throw SkillRouterError.malformedSkillManifest("第 \(line) 行包含不支持的转义")
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            guard !escaped else {
                throw SkillRouterError.malformedSkillManifest("第 \(line) 行转义未闭合")
            }
            return result
        }
        if source.first == "'" {
            guard source.last == "'", source.count >= 2 else {
                throw SkillRouterError.malformedSkillManifest("第 \(line) 行单引号未闭合")
            }
            return String(source.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }

        if let comment = source.range(of: " #") {
            return String(source[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return source
    }
}
