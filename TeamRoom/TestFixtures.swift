#if DEBUG
import SwiftUI
import UIKit

enum TestFixtures {
    static var deliveries: [ChatMessage] {
        [ChatMessage(id: "fixture-failed", text: "Original request that failed delivery", agentId: "fixture", createdAt: "2026-09-29T20:00:00Z", state: "failed", error: "Session limit reached")]
    }
    static var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { context in
            for y in 0..<6 {
                for x in 0..<8 {
                    ((x + y) % 2 == 0 ? UIColor.systemTeal : UIColor.systemOrange).setFill()
                    context.fill(CGRect(x: x * 40, y: y * 40, width: 40, height: 40))
                }
            }
        }
    }

    @MainActor static func load(_ model: AppModel) {
        let stamp = "2026-09-29T21:00:00Z"
        var messages = (0..<50).map { index in
            ChatMessage(id: "message-\(index)", role: index % 2 == 0 ? "user" : "assistant",
                        text: "History \(index)\n\nA previous task with enough text to exercise a long, lazily rendered conversation.", time: stamp)
        }
        messages.append(ChatMessage(id: "latest-user", role: "user", text: "Check the current work and show a table.", time: "2026-09-29T21:01:00Z"))
        messages.append(ChatMessage(id: "latest-result", role: "assistant", phase: "final_answer",
            text: "Latest fixture result\n\n[Open fixture report](workspace/shared/fixture-report.md)\n\n| Teammate | Outcome |\n| :--- | ---: |\n| OpenCode | Finished |\n| Astra | Working |\n| Claude | Needs input |",
            time: "2026-09-29T21:01:02Z", images: [EventImage(id: "fixture-image", label: "Fixture artwork", status: "available", mime: "image/png")]))
        let events = [LiveEvent(id: "latest-command", kind: "tool", title: "Inspect current work", time: "2026-09-29T21:01:01Z", status: "completed", action: "command")]
        let finished = TaskStatus(kind: "completed", label: "Finished", detail: "Current work has been checked.", at: "2026-09-29T21:01:02Z", eventId: "fixture-finished")
        model.agents = [
            Agent(id: "fixture", label: "OpenCode", account: "Test fixture", provider: "opencode", state: "idle", statusSummary: finished, connection: AgentConnection(ready: true), messages: messages, events: events),
            Agent(id: "working", label: "Astra", provider: "codex", state: "working", execution: Execution(label: "Inspecting code"), connection: AgentConnection(ready: true))
        ]
        model.selectedId = "fixture"
        model.items = ConversationBuilder.items(messages: messages, events: events)
        model.lastSync = Date()
        model.socketNote = "live"
        model.phase = .ready
    }
}
#endif
