import Foundation
import SwiftUI

// MARK: - Markdown blocks

enum MarkdownBlocks {
    struct Block: Identifiable {
        enum Kind {
            case heading(Int)
            case paragraph
            case bullet
            case numbered(Int)
            case quote
            case code(String?)
        }

        let id: Int
        let kind: Kind
        let text: String
    }

    static func parse(_ raw: String) -> [Block] {
        let text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(Block(id: blocks.count, kind: .paragraph, text: paragraph.joined(separator: " ")))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(Block(id: blocks.count, kind: .code(language.isEmpty ? nil : language), text: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(Block(id: blocks.count, kind: .heading(heading.level), text: heading.text))
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var value = lines[i].trimmingCharacters(in: .whitespaces)
                    value = String(value.dropFirst())
                    if value.hasPrefix(" ") { value = String(value.dropFirst()) }
                    quote.append(value)
                    i += 1
                }
                blocks.append(Block(id: blocks.count, kind: .quote, text: quote.joined(separator: "\n")))
                continue
            }

            if bullet(trimmed) != nil {
                flushParagraph()
                while i < lines.count, let item = bullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    blocks.append(Block(id: blocks.count, kind: .bullet, text: item))
                    i += 1
                }
                continue
            }

            if let firstNumbered = numbered(trimmed) {
                flushParagraph()
                var number = firstNumbered.number
                while i < lines.count, let item = numbered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    blocks.append(Block(id: blocks.count, kind: .numbered(number), text: item.text))
                    number += 1
                    i += 1
                }
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        return (hashes.count, String(rest.dropFirst()))
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (number, String(rest.dropFirst(2)))
    }
}

@MainActor
final class MarkdownCache {
    static let shared = MarkdownCache()
    private var storage: [String: [MarkdownBlocks.Block]] = [:]
    private var order: [String] = []

    func blocks(for text: String) -> [MarkdownBlocks.Block] {
        if let hit = storage[text] { return hit }
        let blocks = MarkdownBlocks.parse(text)
        storage[text] = blocks
        order.append(text)
        while order.count > 80, let first = order.first {
            order.removeFirst()
            storage[first] = nil
        }
        return blocks
    }
}

// MARK: - Tool / command output

struct OutputSection: Identifiable {
    enum Kind: Equatable { case command, output, error, json, text }
    let id = UUID()
    let kind: Kind
    let label: String
    let text: String
}

enum OutputSections {
    static func stripANSI(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func build(_ raw: String) -> [OutputSection] {
        let cleaned = stripANSI(raw)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [OutputSection(kind: .text, label: "Output", text: "No output was recorded for this activity.")]
        }
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [OutputSection(kind: .text, label: "Output", text: cleaned)]
        }
        guard let dictionary = object as? [String: Any] else {
            return [OutputSection(kind: .json, label: "Result", text: pretty(object))]
        }

        var sections: [OutputSection] = []
        var used = Set<String>()
        for key in ["command", "cmd", "args", "argv"] where dictionary[key] != nil {
            if let text = stringValue(dictionary[key]), !text.isEmpty {
                sections.append(OutputSection(kind: .command, label: "Command", text: text))
                used.insert(key)
            }
        }
        for key in ["stderr", "error", "errors"] where dictionary[key] != nil {
            if let text = stringValue(dictionary[key]), !text.isEmpty {
                sections.append(OutputSection(kind: .error, label: "Error", text: text))
                used.insert(key)
            }
        }
        for key in ["output", "stdout", "result", "content", "text", "message"] where dictionary[key] != nil {
            if let text = stringValue(dictionary[key]), !text.isEmpty {
                sections.append(OutputSection(kind: .output, label: "Output", text: text))
                used.insert(key)
            }
        }
        let remaining = dictionary.filter { !used.contains($0.key) }
        if !remaining.isEmpty {
            sections.append(OutputSection(kind: .json, label: "Details", text: pretty(remaining)))
        }
        if sections.isEmpty {
            sections.append(OutputSection(kind: .text, label: "Output", text: cleaned))
        }
        return sections
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            let parts = array.compactMap { stringValue($0) }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        case let dictionary as [String: Any]:
            return pretty(dictionary)
        case .none:
            return nil
        case .some(let other):
            return String(describing: other)
        }
    }

    private static func pretty(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return text
    }
}
