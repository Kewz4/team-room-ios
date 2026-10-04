import SwiftUI
import Charts

/// Project board: overall progress, decisions waiting on Kewz, who is doing what, goals and milestones from
/// team-hub/PLAN.json, charts measured from real files (work finished per day, lore quests per region, engine
/// milestones) and the live work board of every request in flight — in the spirit of an agent Kanban.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var column = "running"
    @State private var selectedUnit: WorkUnit?
    @State private var selectedDecision: Decision?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let report = model.board.report {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        OverviewCard(report: report, loadedAt: model.board.loadedAt)
                        if !report.decisions.isEmpty { decisions(report) }
                        lanes(report)
                        goals(report)
                        charts(report)
                        workBoard(report)
                        Text("Goals and milestones come from team-hub/PLAN.json, kept current by the coordinators. Quest counts, engine milestones and work units are measured live by the PC.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Tokens.textTertiary)
                            .padding(.bottom, Tokens.Space.l)
                    }
                    .padding(.horizontal, Tokens.Space.m)
                    .padding(.top, Tokens.Space.s)
                } else if model.board.loading {
                    ProgressView("Loading the board…").padding(.top, 80).frame(maxWidth: .infinity)
                } else {
                    EmptyStateView(title: "No board yet", message: model.board.error ?? "Pull to refresh once the PC is reachable.", systemImage: "chart.bar")
                }
            }
            .background(Tokens.background)
            .navigationTitle("Board")
            .toolbar { SettingsToolbarItem(router: model.router) }
            .safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
            .refreshable { await model.refreshBoard(fresh: true) }
            .task {
                while !Task.isCancelled {
                    await model.refreshBoard()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .navigationDestination(for: Goal.self) { goal in
                GoalDetailView(goalId: goal.id)
            }
            .sheet(item: $selectedUnit) { unit in WorkUnitSheet(unit: unit) }
            .sheet(item: $selectedDecision) { decision in DecisionSheet(decision: decision) }
        }
    }

    // MARK: Sections

    private func decisions(_ report: ProgressReport) -> some View {
        BoardSection(title: "Waiting on you", systemImage: "hand.raised", tint: Tokens.working) {
            VStack(spacing: 0) {
                ForEach(report.decisions) { decision in
                    Button {
                        if decision.kind == "prompt", let agentId = decision.agentId {
                            model.router.openAgent(agentId)
                        } else {
                            selectedDecision = decision
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: decision.kind == "prompt" ? "bubble.left.and.exclamationmark.bubble.right" : "checklist")
                                .foregroundStyle(Tokens.working)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(decision.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Tokens.textPrimary)
                                    .multilineTextAlignment(.leading)
                                if let detail = decision.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Tokens.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tokens.textTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if decision.id != report.decisions.last?.id { Divider() }
                }
            }
        }
    }

    private func lanes(_ report: ProgressReport) -> some View {
        BoardSection(title: "Team right now", systemImage: "person.3") {
            VStack(spacing: 0) {
                ForEach(report.lanes) { lane in
                    Button { model.router.openAgent(lane.agentId) } label: {
                        LaneRow(lane: lane)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lane-" + lane.agentId)
                    if lane.id != report.lanes.last?.id { Divider().padding(.leading, 44) }
                }
            }
        }
    }

    /// 1.2 (Kewz, 2026-10-04: "update the board section"): the redrawn board groups its goals into two tracks, the
    /// ten-region phase and the pack, each with its own weighted percent. A plan without tracks shows one list.
    @ViewBuilder private func goals(_ report: ProgressReport) -> some View {
        let tracks = GoalTrack.group(report.goals)
        if tracks.count > 1 {
            ForEach(tracks) { track in
                BoardSection(title: "\(track.title) · \(track.percent)%", systemImage: track.systemImage) {
                    goalList(track.goals)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("track-" + track.id)
            }
        } else {
            BoardSection(title: "Goals", systemImage: "flag.checkered") {
                goalList(report.goals)
                if report.goals.isEmpty {
                    Text("No goals in PLAN.json yet. Ask the team chat to set them up.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                }
            }
        }
    }

    private func goalList(_ goals: [Goal]) -> some View {
        VStack(spacing: 10) {
            ForEach(goals) { goal in
                NavigationLink(value: goal) {
                    GoalCard(goal: goal)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("goal-" + goal.id)
            }
        }
    }

    @ViewBuilder private func charts(_ report: ProgressReport) -> some View {
        if !report.series.isEmpty {
            BoardSection(title: "Work finished · last 14 days", systemImage: "chart.bar.xaxis") {
                ThroughputChart(points: report.series)
            }
        }
        if let lore = report.metrics?.loreQuests, let regions = lore.byRegion, !regions.isEmpty {
            BoardSection(title: "Lore quests · \(lore.value) of \(lore.target)", systemImage: "book.closed") {
                LoreChart(regions: regions)
            }
        }
        if let rows = report.metrics?.engineMilestones?.rows, !rows.isEmpty {
            BoardSection(title: "Quest engine milestones", systemImage: "gearshape.2") {
                EngineMilestonesRow(rows: rows)
            }
        }
    }

    private func workBoard(_ report: ProgressReport) -> some View {
        let columns = [("running", "Running"), ("queued", "Queued"), ("blocked", "Blocked"), ("done", "Done"), ("failed", "Failed")]
        let units = report.work?.columns.units(column) ?? []
        return BoardSection(title: "Work board", systemImage: "rectangle.split.3x1") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(columns, id: \.0) { item in
                            let selected = column == item.0
                            Button {
                                column = item.0
                            } label: {
                                HStack(spacing: 5) {
                                    Text(item.1)
                                    Text("\(report.work?.totals?[item.0] ?? 0)")
                                        .monospacedDigit()
                                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Tokens.textTertiary)
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? Color.white : Tokens.textPrimary)
                                .background(selected ? Tokens.accent : Tokens.surfaceAlt, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .accessibilityIdentifier("work-columns")
                if units.isEmpty {
                    Text(emptyText)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .padding(.vertical, 8)
                }
                ForEach(units.prefix(40)) { unit in
                    Button { selectedUnit = unit } label: { WorkUnitRow(unit: unit) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyText: String {
        switch column {
        case "running": return "Nobody is running a request right now."
        case "queued": return "Nothing is waiting."
        case "blocked": return "Nothing is blocked."
        case "failed": return "No failures in the last week."
        default: return "Nothing finished in the last week."
        }
    }
}

// MARK: - Building blocks

struct BoardSection<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = Tokens.textSecondary
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.l, style: .continuous).stroke(Tokens.hairline, lineWidth: 0.5))
    }
}

struct ProgressRing: View {
    let percent: Int
    var size: CGFloat = 92
    var line: CGFloat = 10
    var color: Color = Tokens.accent
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.surfaceAlt, lineWidth: line)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Tokens.textPrimary)
                Text("overall")
                    .font(.system(size: size * 0.11, weight: .medium))
                    .foregroundStyle(Tokens.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { shown = Double(percent) / 100 } else { withAnimation(.easeOut(duration: 0.8)) { shown = Double(percent) / 100 } }
        }
        .onChange(of: percent) { _, value in
            if reduceMotion { shown = Double(value) / 100 } else { withAnimation(.easeOut(duration: 0.5)) { shown = Double(value) / 100 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall progress \(percent) percent")
    }
}

struct ProgressBar: View {
    let percent: Int
    var color: Color = Tokens.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.surfaceAlt)
                Capsule().fill(color).frame(width: max(height, geometry.size.width * CGFloat(min(max(percent, 0), 100)) / 100))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent")
    }
}

struct OverviewCard: View {
    let report: ProgressReport
    let loadedAt: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ProgressRing(percent: report.overall.percent)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.project?.name ?? "Project")
                    .font(.headline)
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = report.project?.summary {
                    Text(summary)
                        .font(TypeScale.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .lineLimit(4)
                }
                // 1.1: pills keep their width and wrap as whole capsules (FlowRow) instead of squeezing.
                FlowRow(spacing: 6) {
                    let done = report.milestones.filter { $0.status == "done" }.count
                    Pill(text: "\(done)/\(report.milestones.count) milestones", color: Tokens.accent, systemImage: "flag")
                    let blocked = report.milestones.filter { $0.status == "blocked" }.count
                    if blocked > 0 { Pill(text: "\(blocked) blocked", color: Tokens.failure, systemImage: "exclamationmark.octagon") }
                }
                if let updated = report.plan?.updatedAt {
                    RelativeTimeText(iso: updated, prefix: "Plan updated ")
                        .font(.caption2)
                        .foregroundStyle(Tokens.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Tokens.accentSoft, Tokens.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).stroke(Tokens.hairline, lineWidth: 0.5))
        .accessibilityIdentifier("board-overview")
    }
}

struct LaneRow: View {
    let lane: WorkLane

    var body: some View {
        let worker = AgentStyle.worker(forId: lane.agentId)
        HStack(alignment: .top, spacing: 10) {
            AgentAvatar(worker: worker, size: 32, state: lane.state, showRing: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(lane.name).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.textPrimary)
                    Spacer(minLength: 4)
                    if let finished = lane.finishedToday, finished > 0 {
                        Text("\(finished) done today").font(.caption2).foregroundStyle(Tokens.textTertiary)
                    }
                }
                Text(nowLine)
                    .font(TypeScale.caption)
                    .foregroundStyle(lane.state == "working" ? Tokens.working : Tokens.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                FlowRow(spacing: 6) {
                    if let queued = lane.queued, queued > 0 { Pill(text: "\(queued) queued", color: Tokens.info) }
                    if let blocked = lane.blocked, blocked > 0 { Pill(text: "\(blocked) blocked", color: Tokens.failure) }
                    if lane.hold != nil { Pill(text: "hold", color: Tokens.textSecondary, systemImage: "pause.circle") }
                    if let hours = lane.hoursToday, hours > 0 { Pill(text: String(format: "%.1fh today", hours), color: Tokens.textSecondary) }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var nowLine: String {
        if let running = lane.running { return "Now: " + running }
        if let now = lane.now { return "Now: " + now }
        if let hold = lane.hold?.reason { return "On hold — " + hold }
        return lane.state == "idle" ? "Idle" : "Waiting"
    }
}

/// One board track: the goals in one PLAN.json track and their weighted percent (the weights the PC uses).
struct GoalTrack: Identifiable {
    let id: String
    let goals: [Goal]

    var title: String {
        switch id {
        case "ten-region": return "Ten-region phase"
        case "pack": return "Pack improvements"
        case "": return "Other goals"
        default: return id.prefix(1).uppercased() + id.dropFirst().replacingOccurrences(of: "-", with: " ")
        }
    }

    var systemImage: String {
        switch id {
        case "ten-region": return "map"
        case "pack": return "shippingbox"
        default: return "flag.checkered"
        }
    }

    var percent: Int {
        // Like the PC (Number(weight) || 1): no weight, or 0, counts as 1.
        let weights = goals.map { goal -> Double in
            if let weight = goal.weight, weight > 0 { return weight }
            return 1
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let sum = zip(goals, weights).reduce(0.0) { $0 + Double($1.0.percent ?? 0) * $1.1 }
        return Int((sum / total).rounded())
    }

    /// Tracks in the order their first goal appears in the plan; goals without a track come last.
    static func group(_ goals: [Goal]) -> [GoalTrack] {
        var order: [String] = []
        var byTrack: [String: [Goal]] = [:]
        for goal in goals {
            let key = goal.track ?? ""
            if byTrack[key] == nil { order.append(key) }
            byTrack[key, default: []].append(goal)
        }
        let keys = order.filter { !$0.isEmpty } + (order.contains("") ? [""] : [])
        return keys.map { GoalTrack(id: $0, goals: byTrack[$0] ?? []) }
    }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        let color = goal.status == "blocked" ? Tokens.failure : AgentStyle.color(goal.owner)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text("\(goal.percent ?? 0)%")
                    .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressBar(percent: goal.percent ?? 0, color: color)
            HStack(spacing: 6) {
                if let owner = goal.owner {
                    AgentAvatar(worker: owner, size: 16)
                    Text(goal.ownerName ?? AgentStyle.displayName(owner)).font(.caption2).foregroundStyle(Tokens.textSecondary)
                }
                Text("·").font(.caption2).foregroundStyle(Tokens.textTertiary)
                Text(goal.metricLabel ?? "\(goal.doneMilestones ?? 0) of \(goal.milestoneCount ?? 0) milestones")
                    .font(.caption2)
                    .foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Tokens.textTertiary)
            }
        }
        .padding(12)
        .background(Tokens.surfaceAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: Tokens.Radius.m, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct ThroughputChart: View {
    let points: [ActivityPoint]
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        let names = Array(Set(points.map { $0.name ?? $0.agentId })).sorted()
        let colors = names.map { AgentStyle.color($0.lowercased()) }
        let total = points.reduce(0) { $0 + $1.finished }
        VStack(alignment: .leading, spacing: 6) {
            Text("\(total) requests finished · \(String(format: "%.0f", points.reduce(0) { $0 + $1.hours })) active hours")
                .font(TypeScale.caption)
                .foregroundStyle(Tokens.textSecondary)
            Chart(points.filter { $0.finished > 0 }) { point in
                BarMark(
                    x: .value("Day", Self.dayParser.date(from: point.day) ?? Date(), unit: .day),
                    y: .value("Finished", point.finished)
                )
                .foregroundStyle(by: .value("Teammate", point.name ?? point.agentId))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 180)
            .accessibilityLabel("Finished requests per day by teammate")
        }
    }
}

struct LoreChart: View {
    let regions: [RegionCount]

    private var target: Int { regions.first?.target ?? 20 }
    /// Rounded up to the next ten so the last axis label is never clipped.
    private var upper: Int { ((max(target + 8, (regions.map(\.count).max() ?? 0) + 4) + 9) / 10) * 10 }

    var body: some View {
        Chart {
            ForEach(regions) { region in
                BarMark(x: .value("Quests", region.count), y: .value("Region", region.label ?? region.region))
                    .foregroundStyle(region.count >= target ? Tokens.idle : AgentStyle.color("nova"))
                    .cornerRadius(3)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(region.count)").font(.caption2.monospacedDigit()).foregroundStyle(Tokens.textSecondary)
                    }
            }
            RuleMark(x: .value("Target", target))
                .foregroundStyle(Tokens.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: 0...upper)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, to: upper, by: 10))) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(regions.count) * 26 + 24)
        .accessibilityLabel("Lore quests per region against a target of \(target)")
        Text("Dashed line: the \(target)-quest target per region.")
            .font(.caption2)
            .foregroundStyle(Tokens.textTertiary)
    }
}

struct EngineMilestonesRow: View {
    let rows: [EngineMilestone]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rows) { row in
                    VStack(spacing: 4) {
                        Text(row.id)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                        Image(systemName: row.runtimeVerified == true ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(row.runtimeVerified == true ? Tokens.idle : Tokens.working)
                        Text(row.unitTests.map { "\($0) tests" } ?? "—")
                            .font(.caption2)
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    .frame(width: 64)
                    .padding(.vertical, 8)
                    .background(Tokens.surfaceAlt.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.id), \(row.runtimeVerified == true ? "verified in game" : "not yet run in game"), \(row.unitTests ?? 0) unit tests")
                }
            }
        }
        Text("Seal = verified in a real game run; outline = static checks only so far.")
            .font(.caption2)
            .foregroundStyle(Tokens.textTertiary)
    }
}

struct WorkUnitRow: View {
    let unit: WorkUnit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AgentAvatar(worker: AgentStyle.worker(forId: unit.agentId ?? (unit.to ?? "")), size: 28)
                if let from = unit.from, from != "relay" {
                    AgentAvatar(worker: from == "coordinator" ? "coordinator" : from, size: 14)
                        .overlay(Circle().stroke(Tokens.surface, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(unit.title)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("\(AgentStyle.displayName(unit.from)) → \(unit.toName ?? AgentStyle.displayName(unit.to))")
                        .font(.caption2)
                        .foregroundStyle(Tokens.textSecondary)
                    if let kind = unit.kind { Pill(text: kind, color: Tokens.textSecondary) }
                    Spacer(minLength: 0)
                    RelativeTimeText(iso: unit.completedAt ?? unit.startedAt ?? unit.createdAt)
                        .font(.caption2)
                        .foregroundStyle(Tokens.textTertiary)
                }
                if let reason = unit.reason ?? unit.error, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(unit.state == "failed" ? Tokens.failure : Tokens.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct WorkUnitSheet: View {
    let unit: WorkUnit
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(unit.title).font(.body)
                    LabeledContent("From", value: AgentStyle.displayName(unit.from))
                    LabeledContent("To", value: unit.toName ?? AgentStyle.displayName(unit.to))
                    LabeledContent("State", value: unit.state.capitalized)
                    if let kind = unit.kind { LabeledContent("Kind", value: kind) }
                }
                Section("Timeline") {
                    if let created = TimeFormat.date(unit.createdAt) { LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened)) }
                    if let started = TimeFormat.date(unit.startedAt) { LabeledContent("Started", value: started.formatted(date: .abbreviated, time: .shortened)) }
                    if let completed = TimeFormat.date(unit.completedAt) { LabeledContent("Finished", value: completed.formatted(date: .abbreviated, time: .shortened)) }
                }
                if let reason = unit.reason ?? unit.error {
                    Section(unit.state == "failed" ? "Error" : "Why it is waiting") { Text(reason).font(TypeScale.footnote) }
                }
                if let agentId = unit.agentId {
                    Section {
                        Button("Open \(unit.toName ?? "teammate")'s room") {
                            dismiss()
                            model.router.openAgent(agentId)
                        }
                    }
                }
                Section { Text(unit.id).font(TypeScale.monoSmall).foregroundStyle(Tokens.textTertiary).textSelection(.enabled) }
            }
            .navigationTitle("Work request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DecisionSheet: View {
    let decision: Decision
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(decision.title).font(.headline)
                    if let detail = decision.detail { Text(detail).font(.body) }
                }
                if let evidence = decision.evidence {
                    Section("Evidence") {
                        Button {
                            dismiss()
                            model.artifact = ArtifactRequest(path: evidence)
                        } label: {
                            Label(evidence, systemImage: "doc.text").font(.footnote).lineLimit(2)
                        }
                    }
                }
                Section {
                    Button {
                        dismiss()
                        model.roomDraft = "About “\(decision.title)”: "
                        model.router.tab = .team
                    } label: {
                        Label("Discuss in the team chat", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } footer: {
                    Text("Tell a coordinator your decision in the team chat; they record it in the plan and pass it on.")
                }
            }
            .navigationTitle("Decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct GoalDetailView: View {
    let goalId: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let report = model.board.report
        let goal = report?.goals.first { $0.id == goalId }
        let milestones = report?.milestones.filter { $0.goal == goalId } ?? []
        List {
            if let goal {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 14) {
                            ProgressRing(percent: goal.percent ?? 0, size: 64, line: 7, color: AgentStyle.color(goal.owner))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title).font(.headline)
                                if let owner = goal.owner {
                                    HStack(spacing: 6) {
                                        AgentAvatar(worker: owner, size: 18)
                                        Text(goal.ownerName ?? AgentStyle.displayName(owner))
                                            .font(TypeScale.caption)
                                            .foregroundStyle(Tokens.textSecondary)
                                    }
                                }
                                if let method = goal.method {
                                    Text(method).font(.caption2).foregroundStyle(Tokens.textTertiary)
                                }
                            }
                        }
                        if let summary = goal.summary { Text(summary).font(TypeScale.footnote).foregroundStyle(Tokens.textSecondary) }
                        if let note = goal.note { Text(note).font(TypeScale.footnote).foregroundStyle(Tokens.textSecondary) }
                    }
                    .padding(.vertical, 4)
                }
            }
            ForEach(milestones) { milestone in
                Section {
                    MilestoneRow(milestone: milestone)
                    ForEach(report?.tasks.filter { $0.milestone == milestone.id } ?? []) { task in
                        TaskRow(task: task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(goal?.title ?? "Goal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MilestoneRow: View {
    let milestone: Milestone
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                StatusBadge(status: milestone.status ?? "planned")
                Text(milestone.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(milestone.percent ?? 0)%").font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
            }
            ProgressBar(percent: milestone.percent ?? 0, color: StatusBadge.color(milestone.status ?? "planned"), height: 5)
            if let note = milestone.note { Text(note).font(TypeScale.caption).foregroundStyle(Tokens.textSecondary) }
            HStack(spacing: 6) {
                if let owner = milestone.owner {
                    AgentAvatar(worker: owner, size: 14)
                    Text(milestone.ownerName ?? AgentStyle.displayName(owner)).font(.caption2).foregroundStyle(Tokens.textSecondary)
                }
                if let method = milestone.method { Text("· " + method).font(.caption2).foregroundStyle(Tokens.textTertiary) }
                Spacer(minLength: 0)
                if let evidence = milestone.evidence, evidence.hasPrefix("workspace/") {
                    Button {
                        model.artifact = ArtifactRequest(path: evidence)
                    } label: {
                        Label("Evidence", systemImage: "doc.text").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TaskRow: View {
    let task: PlanTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(StatusBadge.color(task.status ?? "todo"))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline)
                HStack(spacing: 6) {
                    if let owner = task.owner { Text(task.ownerName ?? AgentStyle.displayName(owner)).font(.caption2).foregroundStyle(Tokens.textSecondary) }
                    Text("· " + (task.status ?? "todo")).font(.caption2).foregroundStyle(Tokens.textTertiary)
                }
                if let blocked = task.blockedBy { Text("Blocked by " + blocked).font(.caption2).foregroundStyle(Tokens.failure) }
            }
        }
    }

    private var icon: String {
        switch task.status {
        case "done": return "checkmark.circle.fill"
        case "running": return "circle.dotted.circle"
        case "blocked": return "exclamationmark.octagon"
        case "review": return "eye.circle"
        case "ready": return "play.circle"
        default: return "circle"
        }
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Self.color(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Self.color(status).opacity(0.13), in: Capsule())
    }

    static func color(_ status: String) -> Color {
        switch status {
        case "done": return Tokens.idle
        case "active", "running", "ready": return Tokens.accent
        case "review": return Tokens.info
        case "blocked", "failed": return Tokens.failure
        default: return Tokens.textTertiary
        }
    }
}
