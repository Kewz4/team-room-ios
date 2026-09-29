import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        let blocks = MarkdownCache.shared.blocks(for: text)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    Text(MarkdownBlocks.inline(block.text))
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                case .paragraph:
                    Text(MarkdownBlocks.inline(block.text))
                        .font(TypeScale.body)
                        .lineSpacing(3)
                        .foregroundStyle(Tokens.textPrimary)
                        .textSelection(.enabled)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text("•")
                            .font(TypeScale.body)
                            .foregroundStyle(Tokens.textTertiary)
                        Text(MarkdownBlocks.inline(block.text))
                            .font(TypeScale.body)
                            .lineSpacing(3)
                            .foregroundStyle(Tokens.textPrimary)
                            .textSelection(.enabled)
                    }
                case .numbered(let number):
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text("\(number).")
                            .font(TypeScale.captionMedium)
                            .foregroundStyle(Tokens.textTertiary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(MarkdownBlocks.inline(block.text))
                            .font(TypeScale.body)
                            .lineSpacing(3)
                            .foregroundStyle(Tokens.textPrimary)
                            .textSelection(.enabled)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: Tokens.Space.s) {
                        Rectangle()
                            .fill(Tokens.hairline)
                            .frame(width: 2)
                        Text(MarkdownBlocks.inline(block.text))
                            .font(TypeScale.body)
                            .foregroundStyle(Tokens.textSecondary)
                            .textSelection(.enabled)
                    }
                case .code:
                    CodeText(text: block.text)
                case .table(let table):
                    MarkdownTableView(table: table)
                }
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 20
        case 3: return 18
        default: return 17
        }
    }
}

struct MarkdownTableView: View {
    let table: MarkdownBlocks.Table

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                row(table.headers, header: true)
                    .background(Tokens.surfaceAlt)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                    Rectangle().fill(Tokens.hairline).frame(height: 1)
                    row(cells, header: false)
                }
            }
            .overlay(Rectangle().stroke(Tokens.hairline, lineWidth: 1))
            .padding(1)
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier("markdown-table")
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(table.headers.indices, id: \.self) { index in
                Text(MarkdownBlocks.inline(cells[index]))
                    .font(.system(size: 14, weight: header ? .semibold : .regular))
                    .foregroundStyle(Tokens.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(textAlignment(index))
                    .frame(width: columnWidth(index), alignment: alignment(index))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityLabel(header ? cells[index] : "\(table.headers[index]): \(cells[index])")
            }
        }
    }

    private func columnWidth(_ index: Int) -> CGFloat {
        let longest = ([table.headers[index]] + table.rows.map { $0[index] }).map(\.count).max() ?? 10
        return min(220, max(110, CGFloat(longest) * 6.5))
    }

    private func alignment(_ index: Int) -> Alignment {
        switch table.alignments[index] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ index: Int) -> TextAlignment {
        switch table.alignments[index] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct CodeText: View {
    let text: String
    var collapsible = false
    var tint: Color?

    @State private var expanded = false

    private var isTruncated: Bool { collapsible && !expanded && text.count > 3500 }

    private var display: String {
        isTruncated ? String(text.prefix(3500)) + "\n… truncated" : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(display)
                .font(TypeScale.mono)
                .foregroundStyle(tint ?? Tokens.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if collapsible && text.count > 3500 {
                Button(expanded ? "Show less" : "Show full output (\(text.count) characters)") {
                    expanded.toggle()
                }
                .font(TypeScale.captionMedium)
                .foregroundStyle(Tokens.accent)
            }
        }
        .padding(Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surfaceAlt, in: RoundedRectangle(cornerRadius: Tokens.Radius.s, style: .continuous))
    }
}
