# agentde-widgets

An AgentDE extension: a widget spot at the bottom of the sidebar, a menu to pick what it shows, and the widgets that need nothing else.

| Adds | What |
|---|---|
| Sidebar widget | One widget at a time under the sidebar's groups. The menu above it picks which, or hides it. Drag its top edge to make it taller or shorter; double-click the edge for its natural height |
| Calendar widget | What's left of today and tomorrow, from macOS Calendar, so every account added there shows (System Settings → Internet Accounts). Asks for calendar access the first time. Click an event to join its video call (Meet, Zoom, Teams, Webex, Whereby, from its link, location or notes), or to open Calendar |
| JSON plugin widgets | Widgets from `~/.config/agentde/plugins/*/plugin.json`: an HTML page from the plugin's folder, or a shell command's output, optionally refreshed every N seconds |
| `WidgetProvider` | The protocol other extensions conform to for adding widgets (Usage in `agentde-workstreams`, Linear in `agentde-linear`) |

## Include it

Clone this repo beside `agentde/`; it's in AgentDE's default `extensions.json`:

```json
{ "package": "../agentde-widgets", "product": "AgentDEWidgets", "create": "WidgetsExtension()" }
```

## Settings

Settings → Extensions → Widgets:

| Setting | Default |
|---|---|
| Show a widget at the bottom of the sidebar | On |
| Shows | The first widget offered |

## Adding a widget

From another extension: depend on `AgentDEWidgets`, conform to `WidgetProvider`, and return `WidgetDefinition`s. Without building anything: a JSON plugin. Both are in AgentDE's [docs/EXTENDING.md](../agentde/docs/EXTENDING.md#widgets).

## License

MIT; see [LICENSE](LICENSE).
