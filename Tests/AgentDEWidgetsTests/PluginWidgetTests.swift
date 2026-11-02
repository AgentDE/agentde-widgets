import Foundation
import Testing
@testable import AgentDE
@testable import AgentDEWidgets

@Suite("Plugin widgets")
struct PluginWidgetTests {
    @Test func pagesAndCommandsBecomeWidgetsButNotPagesOutsideTheirFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agentde-plugin-widgets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let plugins = [
            ("ok", #"{"name": "OK", "widgets": [{"id": "p", "name": "Page", "page": "w.html"}, {"id": "c", "name": "Cmd", "command": "date"}, {"id": "n", "name": "Neither"}]}"#),
            ("escape", #"{"name": "E", "widgets": [{"id": "x", "name": "X", "page": "../../secret.html"}]}"#),
        ]
        for (name, json) in plugins {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: dir.appendingPathComponent("\(name)/plugin.json"))
        }
        let loaded = PluginManifest.loadAll(in: dir)
        #expect(loaded.map(\.manifest.name) == ["E", "OK"])
        #expect(PluginWidgets.definitions(loaded).map(\.id) == ["plugin.p", "plugin.c"])
    }
}
