import AgentDEKit
import AppKit
import SwiftUI

/// One widget for the sidebar's widget spot.
public struct WidgetDefinition {
    /// Stable, for remembering which one is shown ("calendar", "linear.issues").
    public var id: String
    public var name: String
    public var view: () -> AnyView
    public init(id: String, name: String, view: @escaping () -> AnyView) {
        self.id = id
        self.name = name
        self.view = view
    }
}

/// An extension with widgets: the Widgets extension lists them in its menu.
public protocol WidgetProvider: AnyObject {
    var widgets: [WidgetDefinition] { get }
}

/// What the Widgets extension remembers.
struct WidgetSettings: Codable, Equatable {
    var show = true
    var selected: String?
    /// Set by dragging the widget's top edge; nil for its natural height.
    var height: Double?
}

/// Widgets as a native extension: the spot at the bottom of the sidebar, its menu, and the widgets that
/// need nothing else (Calendar, and pages and commands from JSON plugins). Other extensions add theirs by
/// conforming to `WidgetProvider`.
@Observable
public final class WidgetsExtension: AgentDEExtension, WidgetProvider {
    public let id = "widgets"
    public let name = "Widgets"
    @ObservationIgnored public private(set) var host: AgentDEHost?
    var settings = WidgetSettings() { didSet { if settings != oldValue, let host { host.saveSettings(settings, for: self) } } }
    @ObservationIgnored let calendarFeed = CalendarFeed()
    /// Widgets from JSON plugins (`<config>/plugins/*/plugin.json`), read at launch.
    @ObservationIgnored var pluginWidgets: [WidgetDefinition] = []

    public init() {}

    public func start(host: AgentDEHost) {
        self.host = host
        settings = host.settings(WidgetSettings.self, for: self, fallback: WidgetSettings())
        pluginWidgets = PluginWidgets.definitions(PluginManifest.loadAll(in: host.configDirectory.appendingPathComponent("plugins")))
    }

    public var widgets: [WidgetDefinition] {
        [WidgetDefinition(id: "calendar", name: "Calendar") { [calendarFeed] in AnyView(CalendarWidget().environment(calendarFeed)) }]
            + pluginWidgets
    }

    /// Every widget on offer, from every extension, in load order.
    var all: [WidgetDefinition] {
        (host?.extensions ?? []).compactMap { $0 as? WidgetProvider }.flatMap { $0 === self ? widgets : $0.widgets }
    }

    public func sidebarFooter() -> AnyView? {
        guard settings.show, !all.isEmpty else { return nil }
        return AnyView(SidebarWidget(widgets: self))
    }

    public func settingsView() -> AnyView? { AnyView(WidgetsSettingsView(widgets: self)) }
}

/// The widget spot at the bottom of the sidebar: a menu to pick what it shows over the widget itself. Its top
/// edge drags to make it taller or shorter; double-click the edge for its natural height again.
struct SidebarWidget: View {
    @Bindable var widgets: WidgetsExtension
    @Environment(\.theme) private var theme
    /// The height the widget has now, for starting a drag from its natural height.
    @State private var natural: CGFloat = 0
    @State private var dragStart: CGFloat?

    var body: some View {
        let all = widgets.all
        let current = all.first { $0.id == widgets.settings.selected } ?? all.first
        let height = widgets.settings.height.map { CGFloat($0) }
        VStack(alignment: .leading, spacing: 4) {
            resizeHandle(height: height)
            Menu {
                ForEach(all, id: \.id) { option in
                    Button((option.id == current?.id ? "✓ " : "    ") + option.name) { widgets.settings.selected = option.id }
                }
                Divider()
                Button("Hide the sidebar widget") { widgets.settings.show = false }
            } label: {
                HStack(spacing: 3) {
                    Text(current?.name ?? "").font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(theme.muted)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 6)
            .hint("Choose what this shows")
            Group { current?.view() }
                .environment(\.widgetHeight, height)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(GeometryReader { geo in Color.clear.onAppear { natural = geo.size.height }.onChange(of: geo.size.height) { natural = $1 } })
        }
    }

    /// A strip along the top: drag up for a taller widget, down for a shorter one.
    private func resizeHandle(height: CGFloat?) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? (height ?? natural)
                    dragStart = start
                    widgets.settings.height = Double(min(640, max(90, start - value.translation.height)))
                }
                .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { widgets.settings.height = nil }
            .hint("Drag to resize · double-click for the natural height")
            .padding(.bottom, -4)
    }
}

private struct WidgetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The height you gave the sidebar widget by dragging its edge; nil for its natural height.
    public var widgetHeight: CGFloat? {
        get { self[WidgetHeightKey.self] }
        set { self[WidgetHeightKey.self] = newValue }
    }
}

private struct WidgetListHeight: ViewModifier {
    let natural: CGFloat
    @Environment(\.widgetHeight) private var height

    func body(content: Content) -> some View {
        if height != nil {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            content.frame(maxHeight: natural).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// A widget's scrolling list: up to `natural` points tall by itself, or filling the height you dragged the
    /// widget to.
    public func widgetListHeight(_ natural: CGFloat) -> some View { modifier(WidgetListHeight(natural: natural)) }
}

/// The frame the text widgets (Usage, Calendar, Linear) share: plain, on the sidebar itself, like its rows.
public struct WidgetCard<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder let content: () -> Content
    public init(height: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.height = height
        self.content = content
    }
    @Environment(\.theme) private var theme

    @Environment(\.widgetHeight) private var widgetHeight

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: widgetHeight ?? height, maxHeight: widgetHeight ?? height, alignment: .topLeading)
    }
}

/// A widget's empty or setup state: a line of text and, optionally, a button.
public struct WidgetMessage: View {
    let text: String
    var button: String? = nil
    var action: () -> Void = {}
    public init(text: String, button: String? = nil, action: @escaping () -> Void = {}) {
        self.text = text
        self.button = button
        self.action = action
    }
    @Environment(\.theme) private var theme

    public var body: some View {
        VStack(spacing: 8) {
            Text(text).font(.system(size: 11.5)).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action).controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Settings → Extensions → Widgets.
struct WidgetsSettingsView: View {
    @Bindable var widgets: WidgetsExtension

    var body: some View {
        Form {
            Toggle("Show a widget at the bottom of the sidebar", isOn: $widgets.settings.show)
            Picker("Shows", selection: Binding(get: { widgets.settings.selected ?? widgets.all.first?.id ?? "" },
                                               set: { widgets.settings.selected = $0 })) {
                ForEach(widgets.all, id: \.id) { Text($0.name).tag($0.id) }
            }
            .disabled(!widgets.settings.show)
        }
        .formStyle(.grouped)
    }
}
