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
