import AgentDEKit
import SwiftUI
import WebKit

/// JSON plugins' widgets (`PluginManifest.Widget`): an HTML page from the plugin's folder, or a command's output.
enum PluginWidgets {
    static func definitions(_ plugins: [PluginManifest.Loaded]) -> [WidgetDefinition] {
        plugins.flatMap { plugin in
            (plugin.manifest.widgets ?? []).compactMap { widget -> WidgetDefinition? in
                let every = widget.every.map { max(5, $0) }
                if let page = widget.page {
                    // Only pages inside the plugin's own folder: no absolute paths or `..`, nor a symlink out of it.
                    guard !page.hasPrefix("/"), !page.split(separator: "/").contains("..") else { return nil }
                    let url = plugin.folder.appendingPathComponent(page)
                    if FileManager.default.fileExists(atPath: url.path) {
                        guard url.resolvingSymlinksInPath().path.hasPrefix(plugin.folder.resolvingSymlinksInPath().path + "/") else { return nil }
                    }
                    return WidgetDefinition(id: "plugin.\(widget.id)", name: widget.name) {
                        AnyView(WidgetCard(height: 160) { PageWidget(url: url, folder: plugin.folder, every: every) })
                    }
                }
                if let command = widget.command {
                    return WidgetDefinition(id: "plugin.\(widget.id)", name: widget.name) {
                        AnyView(CommandWidget(command: command, folder: plugin.folder, every: every))
                    }
                }
                return nil
            }
        }
    }
}

/// A plugin's HTML page, reloaded every `every` seconds when set.
private struct PageWidget: NSViewRepresentable {
    let url: URL
    let folder: URL
    let every: Double?

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        view.loadFileURL(url, allowingReadAccessTo: folder)
        if let every {
            context.coordinator.timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak view] _ in view?.reload() }
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.timer?.invalidate() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var timer: Timer? }
}

/// A plugin command's output: run with `zsh -lc` in the plugin's folder when shown, then every `every`
/// seconds when set. At most 4 KB of output, and a run that takes over 10 seconds is stopped.
private struct CommandWidget: View {
    let command: String
    let folder: URL
    let every: Double?
    @State private var output = ""
    @Environment(\.theme) private var theme

    var body: some View {
        WidgetCard {
            ScrollView {
                Text(output.isEmpty ? "…" : output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            .widgetListHeight(140)
        }
        .task(id: command) {
            repeat {
                output = await Self.run(command, in: folder)
                guard let every else { break }
                try? await Task.sleep(for: .seconds(every))
            } while !Task.isCancelled
        }
    }

    static func run(_ command: String, in folder: URL) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.currentDirectoryURL = folder
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() } catch {
                    continuation.resume(returning: "Couldn't run it: \(error.localizedDescription)")
                    return
                }
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                continuation.resume(returning: String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
