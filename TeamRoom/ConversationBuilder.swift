import Foundation

struct ActivityGroup: Identifiable {
    let id: String
    var events: [LiveEvent]

    var running: Bool { events.contains { $0.status == "running" } }
    var failed: Bool { events.contains { $0.status == "failed" || $0.kind == "error" } }
    var lastTime: String? { events.last?.time ?? events.last?.updatedAt }

    var summary: String {
        var commands = 0
        var tools = 0
        var images = 0
        for event in events {
            if event.kind == "output" || event.id.hasSuffix(":stream") { continue }
            switch event.action {
            case "command": commands += 1
            case "image": images += 1
            default: tools += 1
            }
        }
        var parts: [String] = []
        if tools > 0 { parts.append("Used \(tools) tool\(tools == 1 ? "" : "s")") }
        if commands > 0 { parts.append("ran \(commands) command\(commands == 1 ? "" : "s")") }
        if images > 0 { parts.append("viewed \(images) image\(images == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append("\(events.count) event\(events.count == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    var availableImages: [EventImage] {
        events.flatMap { $0.images ?? [] }.filter { $0.status == "available" }
    }
}

enum ConversationItem: Identifiable {
    case message(ChatMessage)
    case activity(ActivityGroup)

    var id: String {
        switch self {
        case .message(let message): return "m:" + message.id
        case .activity(let group): return "g:" + group.id
        }
    }

    var time: Date? {
        switch self {
        case .message(let message): return TimeFormat.date(message.time)
        case .activity(let group): return TimeFormat.date(group.events.first?.time)
        }
    }
}

enum ConversationBuilder {
    static func items(messages: [ChatMessage], events: [LiveEvent], queue: [ChatMessage] = []) -> [ConversationItem] {
        struct Row {
            let time: Date?
            let priority: Int
            let sequence: Int
            let item: ConversationItem
        }
        var visibleMessages = messages
        // Queue items were previously drawn after all tool output. Put a delivered user message
        // at its dispatch time until its native transcript copy is available.
        for pending in queue where ["sending", "streaming"].contains(pending.state ?? "") {
            let sent = TimeFormat.date(pending.sentAt ?? pending.createdAt)
            let prefix = String((pending.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
            let nativeCopy = messages.contains { message in
                guard message.role == "user", !prefix.isEmpty,
                      (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix),
                      let native = TimeFormat.date(message.time), let sent else { return false }
                return native.timeIntervalSince(sent) >= -2 && native.timeIntervalSince(sent) < 120
            }
            if !nativeCopy {
                var message = pending
                message.role = "user"
                message.time = pending.sentAt ?? pending.createdAt
                visibleMessages.append(message)
            }
        }
        var rows: [Row] = []
        rows.append(contentsOf: visibleMessages.enumerated().map {
            Row(time: TimeFormat.date($0.element.time), priority: $0.element.role == "user" ? 0 : 2,
                sequence: $0.offset, item: .message($0.element))
        })
        let oldest = visibleMessages.compactMap { TimeFormat.date($0.time) }.min()
        rows.append(contentsOf: events.enumerated().compactMap { index, event in
            let time = TimeFormat.date(event.time)
            if let oldest, let time, time < oldest { return nil }
            return Row(time: time, priority: 1, sequence: index, item: .activity(ActivityGroup(id: event.id, events: [event])))
        })
        rows.sort {
            let a = $0.time ?? .distantPast, b = $1.time ?? .distantPast
            if a != b { return a < b }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.sequence < $1.sequence
        }

        var result: [ConversationItem] = []
        var group: ActivityGroup?
        for row in rows {
            switch row.item {
            case .message(let message):
                if let pending = group {
                    result.append(.activity(pending))
                    group = nil
                }
                result.append(.message(message))
            case .activity(let activity):
                if group == nil {
                    group = ActivityGroup(id: activity.id, events: [])
                }
                group?.events.append(contentsOf: activity.events)
            }
        }
        if let pending = group { result.append(.activity(pending)) }
        return result
    }

    static func displayTitle(for event: LiveEvent) -> String {
        if let range = event.title.range(of: " · ") {
            return String(event.title[range.upperBound...])
        }
        return event.title
    }
}
