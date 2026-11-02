import AgentDEKit
import AppKit
import EventKit
import Observation
import SwiftUI

/// Today's remaining events and tomorrow's, from macOS Calendar (EventKit): every account added there,
/// Google Calendar included, with no sign-in of its own. Asks for calendar access the first time it's shown.
@Observable
final class CalendarFeed {
    enum Access { case unknown, granted, denied }
    private(set) var access: Access
    private(set) var events: [EKEvent] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: Any?

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    /// From now to the end of tomorrow; reloads when Calendar's data changes.
    func reload(now: Date = Date()) {
        guard access == .granted else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reload()
            }
        }
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = store.events(matching: predicate).filter { $0.status != .canceled }.sorted { $0.startDate < $1.startDate }
    }
}

struct CalendarWidget: View {
    @Environment(CalendarFeed.self) private var feed
    @Environment(\.theme) private var theme
    @State private var now = Date()

    var body: some View {
        WidgetCard {
            switch feed.access {
            case .unknown:
                WidgetMessage(text: "Shows your next events from macOS Calendar, Google accounts included.",
                              button: "Allow Calendar Access") { feed.requestAccess() }
            case .denied:
                WidgetMessage(text: "\(AppBrand.name) can't read your calendars. Allow it in System Settings › Privacy & Security › Calendars.",
                              button: "Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            case .granted:
                if feed.events.isEmpty {
                    WidgetMessage(text: "Nothing more on your calendar today or tomorrow.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(sections(feed.events).enumerated()), id: \.offset) { _, section in
                                Text(section.title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.muted)
                                    .padding(.top, 4).padding(.horizontal, 4)
                                ForEach(section.events, id: \.calendarItemIdentifier) { event in EventRow(event: event, now: now) }
                            }
                        }
                        .padding(6)
                    }
                    .widgetListHeight(190)
                }
            }
        }
        .onAppear { feed.reload() }
        .task {
            // The list moves on as events end; once a minute is plenty.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
                feed.reload(now: now)
            }
        }
    }

    private func sections(_ events: [EKEvent]) -> [(title: String, events: [EKEvent])] {
        let calendar = Calendar.current
        let today = events.filter { calendar.isDateInToday($0.startDate) || $0.startDate < now }
        let tomorrow = events.filter { !today.contains($0) }
        return [("Today", today), ("Tomorrow", tomorrow)].filter { !$0.1.isEmpty }
    }
}

private struct EventRow: View {
    let event: EKEvent
    let now: Date
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let happening = event.startDate <= now && event.endDate > now
        Button { open() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(Color(nsColor: event.calendar?.color ?? .systemBlue)).frame(width: 6, height: 6)
                Text(time).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(happening ? theme.text : theme.muted)
                    .frame(width: 44, alignment: .leading)
                Text(event.title ?? "Untitled").font(.system(size: 11.5, weight: happening ? .semibold : .regular))
                    .foregroundStyle(happening ? theme.text : theme.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if meetingURL != nil { Image(systemName: "video").font(.system(size: 9)).foregroundStyle(theme.muted) }
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? theme.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(meetingURL.map { "Join: \($0.host ?? $0.absoluteString)" } ?? "Open in Calendar")
    }

    private var time: String {
        if event.isAllDay { return "All day" }
        return event.startDate.formatted(date: .omitted, time: .shortened)
    }

    /// A video call link from the event's URL, location or notes (Meet, Zoom, Teams…).
    private var meetingURL: URL? {
        if let url = event.url, url.scheme?.hasPrefix("http") == true { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://[^\s<>"]*(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|webex\.com|whereby\.com)[^\s<>"]*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }

    /// Joins the call when there is one, otherwise shows the day in Calendar.
    private func open() {
        if let meetingURL { NSWorkspace.shared.open(meetingURL); return }
        if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
