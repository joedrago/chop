import Foundation

/// Process-wide pool of tool instances. Tools are stateful (e.g. drag tracking)
/// but per-document state belongs on the Document. v1 keeps it simple — one
/// instance per ToolId, shared across documents.
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [ToolId: any Tool] = [:]

    private init() {
        register(PanTool())
        register(ZoomTool())
        register(SelectRectTool())
    }

    func register(_ tool: any Tool) {
        tools[tool.id] = tool
    }

    func tool(for id: ToolId) -> any Tool {
        tools[id] ?? PanTool()
    }
}
