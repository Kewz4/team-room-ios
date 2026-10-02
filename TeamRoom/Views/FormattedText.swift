import SwiftUI
import UIKit

/// Markdown body for messages and reports. Reads pre-rendered AttributedStrings from MarkdownRenderer, so a
/// redraw never re-parses Markdown. Text selection lives in the message's "Select Text" action (as in the
/// Claude and ChatGPT apps) rather than on every paragraph, which kept long conversations from scrolling smoothly.
struct MarkdownText: View {
    let text: String
    var selectable = false

    var body: some View {
        let rendered = MarkdownRenderer.shared.render(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rendered.blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder private func blockView(_ block: RenderedBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.attributed)
                .font(level <= 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(Tokens.textPrimary)
                .padding(.top, level <= 2 ? 4 : 0)
                .modifier(Selectable(enabled: selectable))
        case .paragraph:
            Text(block.attributed)
                .font(TypeScale.body)
                .lineSpacing(3)
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Selectable(enabled: selectable))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text("•")
                    .font(TypeScale.body)
                    .foregroundStyle(Tokens.textTertiary)
                Text(block.attributed)
                    .font(TypeScale.body)
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(Selectable(enabled: selectable))
            }
        case .numbered(let number):
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text("\(number).")
                    .font(TypeScale.body.monospacedDigit())
                    .foregroundStyle(Tokens.textTertiary)
                    .frame(minWidth: 20, alignment: .trailing)
                Text(block.attributed)
                    .font(TypeScale.body)
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(Selectable(enabled: selectable))
            }
        case .quote:
            HStack(alignment: .top, spacing: Tokens.Space.s) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Tokens.hairline)
                    .frame(width: 3)
                Text(block.attributed)
                    .font(TypeScale.body)
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(Selectable(enabled: selectable))
            }
        case .code(let language):
            CodeBlock(text: block.text, language: language)
        case .table(let table):
            MarkdownTableView(table: table, cells: block.cells)
        }
    }
}

private struct Selectable: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}

/// Fenced code with a language label and a copy button, scrolling sideways instead of wrapping.
struct CodeBlock: View {
    let text: String
    var language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(TypeScale.monoSmall)
                    .foregroundStyle(Tokens.textTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(TypeScale.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Tokens.textSecondary)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
            }
            .padding(.horizontal, Tokens.Space.s + 2)
            .padding(.vertical, 6)
            Divider().overlay(Tokens.hairline)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(TypeScale.mono)
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(Tokens.Space.s + 2)
            }
        }
        .background(Tokens.surfaceAlt, in: RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Code: \(text.prefix(200))")
    }
}

struct MarkdownTableView: View {
    let table: MarkdownBlocks.Table
    let cells: [[AttributedString]]

    var body: some View {
        if table.headers.count <= 3 {
            fittedGrid
        } else {
            scrollingTable
        }
    }

    /// Up to three columns fit the screen: columns share the width and long cells wrap.
    private var fittedGrid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<cells.count, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Tokens.hairline).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        let value = column < cells[index].count ? cells[index][column] : AttributedString()
                        Text(value)
                            .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(Tokens.textPrimary)
                            .multilineTextAlignment(textAlignment(column))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(column))
                            .background(index == 0 ? Tokens.surfaceAlt : Color.clear)
                            .accessibilityLabel(index == 0 ? table.headers[column] : "\(table.headers[column]): \(String(value.characters))")
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.s).stroke(Tokens.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.s))
        .accessibilityIdentifier("markdown-table")
    }

    private var scrollingTable: some View {
        let widths = table.headers.indices.map(columnWidth)
        return ScrollView(.horizontal) {
            VStack(spacing: 0) {
                row(0, header: true, widths: widths)
                    .background(Tokens.surfaceAlt)
                ForEach(1..<max(cells.count, 1), id: \.self) { index in
                    Rectangle().fill(Tokens.hairline).frame(height: 1)
                    row(index, header: false, widths: widths)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.s).stroke(Tokens.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.s))
            .padding(1)
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier("markdown-table")
    }

    @ViewBuilder private func row(_ index: Int, header: Bool, widths: [CGFloat]) -> some View {
        if index < cells.count {
            HStack(alignment: .top, spacing: 0) {
                ForEach(table.headers.indices, id: \.self) { column in
                    let value = column < cells[index].count ? cells[index][column] : AttributedString()
                    Text(value)
                        .font(header ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(Tokens.textPrimary)
                        .multilineTextAlignment(textAlignment(column))
                        .frame(width: widths[column], alignment: alignment(column))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .accessibilityLabel(header ? table.headers[column] : "\(table.headers[column]): \(String(value.characters))")
                }
            }
        }
    }

    private func columnWidth(_ index: Int) -> CGFloat {
        let longest = ([table.headers[index]] + table.rows.map { index < $0.count ? $0[index] : "" }).map(\.count).max() ?? 10
        return min(240, max(100, CGFloat(longest) * 7))
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

/// Plain monospaced output (tool results, logs) with an optional "show full output" toggle.
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

/// Full-screen, selectable copy of a message (the "Select Text" action).
struct SelectTextSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(TypeScale.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Tokens.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share text")
                }
            }
        }
    }
}
