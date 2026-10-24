import Charts
import Foundation
import SwiftUI

extension KeyedDecodingContainer {
    /// A number the server may send as a JSON number or a numeric string; anything else is dropped, never thrown.
    func lenientNumber(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Double(text), value.isFinite { return value }
        return nil
    }

    func lenientString(_ key: Key) -> String? {
        try? decodeIfPresent(String.self, forKey: key)
    }
}

/// The money of an API-credit worker (Rigel, Lyra): today against its daily cap, the cycle against the monthly credit,
/// and the last 14 days. Dollars are numbers. Every field is optional on this side: one bad value never blanks the app.
struct AgentBudget: Codable, Hashable {
    struct Today: Codable, Hashable {
        var day: String?
        var spent: Double?
        var cap: Double?
        var left: Double?
    }

    struct Cycle: Codable, Hashable {
        var start: String?
        var renewsAt: String?
        var credit: Double?
        var spent: Double?
        var left: Double?
        var daysLeft: Double?
    }

    struct Day: Codable, Hashable, Identifiable {
        var day: String
        var spent: Double
        var id: String { day }
    }

    var kind: String?
    var currency: String?
    var model: String?
    var effort: String?
    var pacing: String?
    var today: Today?
    var cycle: Cycle?
    var history: [Day] = []
    var lastRunAt: String?
    var observedAt: String?
    var source: String?

    /// The list card needs today's spend and cap; without both the agent falls back to its balance chip.
    var showsToday: Bool { today?.spent != nil && (today?.cap ?? 0) > 0 }
    var showsCycle: Bool { cycle?.spent != nil && (cycle?.credit ?? 0) > 0 }
    var hasAnything: Bool { showsToday || showsCycle }

    var todayFraction: Double { Self.fraction(today?.spent, today?.cap) }
    var cycleFraction: Double { Self.fraction(cycle?.spent, cycle?.credit) }

    static func fraction(_ spent: Double?, _ total: Double?) -> Double {
        guard let spent, let total, total > 0 else { return 0 }
        return min(max(spent / total, 0), 1)
    }

    /// "$1.20"; whole-dollar totals drop the cents ("$200"). Other currencies lead with their code.
    func money(_ value: Double, whole: Bool = false) -> String {
        let code = (currency ?? "USD").uppercased()
        let prefix = code == "USD" ? "$" : code + " "
        let rounded = (value * 100).rounded() / 100
        if whole, rounded == rounded.rounded() { return prefix + String(format: "%.0f", rounded) }
        return prefix + String(format: "%.2f", rounded)
    }

    var todayLine: String? {
        guard showsToday, let spent = today?.spent, let cap = today?.cap else { return nil }
        return "Today \(money(spent)) / \(money(cap))"
    }

    var cycleLine: String? {
        guard showsCycle, let spent = cycle?.spent, let credit = cycle?.credit else { return nil }
        var line = "This cycle \(money(spent)) of \(money(credit, whole: true))"
        if let renews = Self.shortDate(cycle?.renewsAt) { line += " · renews \(renews)" }
        return line
    }

    /// "Nov 14" from an ISO time or a plain day. Cycles end at 00:00 UTC on the renewal date, so UTC names the day.
    static func shortDate(_ text: String?) -> String? {
        guard let text, text.count >= 10 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(text.prefix(10))) else { return nil }
        parser.dateFormat = "MMM d"
        return parser.string(from: date)
    }
}

extension AgentBudget {
    private enum CodingKeys: String, CodingKey {
        case kind, currency, model, effort, pacing, today, cycle, history, lastRunAt, observedAt, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenientString(.kind)
        currency = c.lenientString(.currency)
        model = c.lenientString(.model)
        effort = c.lenientString(.effort)
        pacing = c.lenientString(.pacing)
        today = try? c.decodeIfPresent(Today.self, forKey: .today)
        cycle = try? c.decodeIfPresent(Cycle.self, forKey: .cycle)
        history = c.contains(.history) ? c.lossy(Day.self, forKey: .history) : []
        lastRunAt = c.lenientString(.lastRunAt)
        observedAt = c.lenientString(.observedAt)
        source = c.lenientString(.source)
    }
}

extension AgentBudget.Today {
    private enum CodingKeys: String, CodingKey { case day, spent, cap, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = c.lenientString(.day)
        spent = c.lenientNumber(.spent)
        cap = c.lenientNumber(.cap)
        left = c.lenientNumber(.left)
    }
}

extension AgentBudget.Cycle {
    private enum CodingKeys: String, CodingKey { case start, renewsAt, credit, spent, left, daysLeft }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenientString(.start)
        renewsAt = c.lenientString(.renewsAt)
        credit = c.lenientNumber(.credit)
        spent = c.lenientNumber(.spent)
        left = c.lenientNumber(.left)
        daysLeft = c.lenientNumber(.daysLeft)
    }
}

extension AgentBudget.Day {
    private enum CodingKeys: String, CodingKey { case day, spent }

    /// A day without a name is useless on a chart, so it throws and the lossy list skips it; a bad amount counts as $0.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        spent = c.lenientNumber(.spent) ?? 0
    }
}

/// List card: "Today $1.20 / $9.20" over a thin bar, in the slot the balance chip used to take.
struct BudgetMeter: View {
    let budget: AgentBudget
    let color: Color
    @ScaledMetric(relativeTo: .caption2) private var barWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(budget.todayLine ?? "")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Tokens.textSecondary)
                .lineLimit(1)
            BudgetBar(fraction: budget.todayFraction, color: color, over: (budget.today?.left ?? 1) <= 0)
                .frame(width: barWidth, height: 4)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(budget.todayLine ?? "")
        .accessibilityIdentifier("budget-meter")
    }

    static func shows(_ usage: AgentUsage?) -> Bool { usage?.budget?.showsToday == true }
}

struct BudgetBar: View {
    let fraction: Double
    let color: Color
    var over = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.surfaceAlt)
                Capsule().fill(over ? Tokens.failure : color)
                    .frame(width: max(fraction > 0 ? 3 : 0, proxy.size.width * fraction))
            }
        }
    }
}

/// The room's money panel under the status strip: two bars, and a tap opens the 14-day chart.
struct BudgetPanel: View {
    let budget: AgentBudget
    let color: Color
    @State private var expanded = BudgetPanel.startsOpen

    static var startsOpen: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ui-budget-open")
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    if let today = budget.todayLine { row(today, fraction: budget.todayFraction, over: (budget.today?.left ?? 1) <= 0) }
                    if let cycle = budget.cycleLine { row(cycle, fraction: budget.cycleFraction, over: false) }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("budget-panel-toggle")
            if expanded {
                BudgetChart(budget: budget, color: color)
                if let note = footnote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Tokens.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.hairline).frame(height: 0.5) }
        .accessibilityIdentifier("budget-panel")
    }

    private var footnote: String? {
        var parts: [String] = []
        if let left = budget.cycle?.left { parts.append("\(budget.money(left)) left this cycle") }
        if let days = budget.cycle?.daysLeft { parts.append("\(String(format: "%.1f", days)) days to go") }
        if budget.pacing == "flat" { parts.append("flat daily cap") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ text: String, fraction: Double, over: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Tokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.trailing, 18)
            BudgetBar(fraction: fraction, color: color, over: over)
                .frame(height: 5)
        }
    }
}

/// The last 14 days of spend as bars, today's in full colour, with the daily cap as a dashed line.
struct BudgetChart: View {
    let budget: AgentBudget
    let color: Color

    var body: some View {
        let days = budget.history
        let cap = budget.today?.cap ?? 0
        let top = max(max(days.map(\.spent).max() ?? 0, cap) * 1.15, 1)
        let today = budget.today?.day ?? days.last?.day
        VStack(alignment: .leading, spacing: 2) {
            Text("Last 14 days")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Tokens.textSecondary)
            if days.isEmpty {
                Text("No spend recorded yet.")
                    .font(.caption2)
                    .foregroundStyle(Tokens.textTertiary)
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("Day", day.day), y: .value("Spent", day.spent))
                            .foregroundStyle(day.day == today ? color : color.opacity(0.45))
                    }
                    if cap > 0 {
                        RuleMark(y: .value("Daily cap", cap))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Tokens.textTertiary)
                    }
                }
                .chartYScale(domain: 0...top)
                .chartXAxis {
                    AxisMarks(values: ticks(days)) { value in
                        AxisValueLabel {
                            if let day = value.as(String.self) {
                                Text(AgentBudget.shortDate(day) ?? day).font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Tokens.hairline)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(budget.money(amount, whole: true)).font(.system(size: 9))
                            }
                        }
                    }
                }
                .frame(height: 96)
                // One element with the spoken summary: Swift Charts otherwise publishes one element per bar, and the chart's
                // own identifier never reaches VoiceOver or the UI tests.
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("budget-chart")
                .accessibilityLabel(summary(days))
            }
        }
    }

    private func ticks(_ days: [AgentBudget.Day]) -> [String] {
        days.enumerated().filter { $0.offset % 4 == 0 || $0.offset == days.count - 1 }.map(\.element.day)
    }

    private func summary(_ days: [AgentBudget.Day]) -> String {
        "Spend over the last \(days.count) days, \(budget.money(days.reduce(0) { $0 + $1.spent })) in total"
    }
}
