import Foundation
import SwiftUI

// MARK: - Markdown blocks

enum MarkdownBlocks {
    enum ColumnAlignment: Equatable { case leading, center, trailing }
    struct Table {
        let headers: [String]
        let rows: [[String]]
        let alignments: [ColumnAlignment]
    }
    struct Block: Identifiable {
        enum Kind {
            case heading(Int)
            case paragraph
            case bullet
            case numbered(Int)
            case quote
            case code(String?)
            case table(Table)
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

            if i + 1 < lines.count, trimmed.contains("|"),
               let alignments = tableDelimiter(lines[i + 1]),
               tableCells(trimmed).count == alignments.count {
                flushParagraph()
                let headers = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|"), !row.hasPrefix("```") else { break }
                    let cells = tableCells(row)
                    rows.append(Array((cells + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    i += 1
                }
                blocks.append(Block(id: blocks.count, kind: .table(Table(headers: headers, rows: rows, alignments: alignments)), text: ""))
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
        return (try? AttributedString(markdown: LinkRouting.prepareMarkdown(text), options: options)) ?? AttributedString(text)
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

    static func tableCells(_ line: String) -> [String] {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        var cells: [String] = []
        var cell = ""
        var index = 0
        var codeTicks = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                index += 1
                if characters[index] != "|" { cell.append("\\") }
                cell.append(characters[index])
            } else if character == "`" {
                var count = 1
                while index + count < characters.count, characters[index + count] == "`" { count += 1 }
                if codeTicks == 0 { codeTicks = count } else if codeTicks == count { codeTicks = 0 }
                cell += String(repeating: "`", count: count)
                index += count - 1
            } else if character == "|", codeTicks == 0 {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
            index += 1
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if characters.first == "|", cells.first == "" { cells.removeFirst() }
        if characters.last == "|", cells.last == "" { cells.removeLast() }
        return cells
    }

    private static func tableDelimiter(_ line: String) -> [ColumnAlignment]? {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [ColumnAlignment] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            let dashes = value.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard dashes.count >= 3, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(value.hasSuffix(":") ? (value.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return alignments
    }
}

/// One parsed block with its inline Markdown already converted to an AttributedString.
struct RenderedBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        case bullet
        case numbered(Int)
        case quote
        case code(String?)
        case table(MarkdownBlocks.Table)
    }

    let id: Int
    let kind: Kind
    let text: String
    let attributed: AttributedString
    /// Pre-rendered table cells, row-major; empty for other kinds.
    let cells: [[AttributedString]]
}

struct RenderedMarkdown {
    let blocks: [RenderedBlock]

    init(_ text: String) {
        blocks = MarkdownBlocks.parse(text).map { block in
            switch block.kind {
            case .heading(let level):
                return RenderedBlock(id: block.id, kind: .heading(level), text: block.text, attributed: MarkdownBlocks.inline(block.text), cells: [])
            case .paragraph:
                return RenderedBlock(id: block.id, kind: .paragraph, text: block.text, attributed: MarkdownBlocks.inline(block.text), cells: [])
            case .bullet:
                return RenderedBlock(id: block.id, kind: .bullet, text: block.text, attributed: MarkdownBlocks.inline(block.text), cells: [])
            case .numbered(let number):
                return RenderedBlock(id: block.id, kind: .numbered(number), text: block.text, attributed: MarkdownBlocks.inline(block.text), cells: [])
            case .quote:
                return RenderedBlock(id: block.id, kind: .quote, text: block.text, attributed: MarkdownBlocks.inline(block.text), cells: [])
            case .code(let language):
                return RenderedBlock(id: block.id, kind: .code(language), text: block.text, attributed: AttributedString(block.text), cells: [])
            case .table(let table):
                let cells = ([table.headers] + table.rows).map { row in row.map { MarkdownBlocks.inline($0) } }
                return RenderedBlock(id: block.id, kind: .table(table), text: "", attributed: AttributedString(), cells: cells)
            }
        }
    }
}

/// Thread-safe cache of rendered Markdown. Rendering is pure, so history can be warmed off the main thread
/// and views only read finished AttributedStrings (inline Markdown used to be re-parsed on every redraw).
final class MarkdownRenderer: @unchecked Sendable {
    static let shared = MarkdownRenderer()

    private final class Box {
        let value: RenderedMarkdown
        init(_ value: RenderedMarkdown) { self.value = value }
    }

    private let cache = NSCache<NSString, Box>()

    init() {
        cache.countLimit = 600
        cache.totalCostLimit = 6_000_000
    }

    func render(_ text: String) -> RenderedMarkdown {
        let key = text as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let value = RenderedMarkdown(text)
        cache.setObject(Box(value), forKey: key, cost: text.utf16.count)
        return value
    }

    /// Renders texts on a background thread so the first scroll through a conversation is smooth.
    func warm(_ texts: [String]) {
        let pending = texts.filter { !$0.isEmpty && cache.object(forKey: $0 as NSString) == nil }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) { [self] in
            for text in pending { _ = render(text) }
        }
    }
}

// MARK: - Tool / command output

struct OutputSection: Identifiable {
    enum Kind: Equatable { case command, output, error, json, text }
    var id: String { label + ":" + String(text.count) + ":" + String(text.prefix(24)) }
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
