# od-notes

iOS app for browsing and editing Markdown notes stored in Enterprise OneDrive, using the iOS File Provider (no API keys or admin consent needed).

## Architecture

- **SwiftUI app** targeting iOS 16+
- Accesses OneDrive files through the iOS File Provider / Document Picker (piggybacks on the OneDrive iOS app)
- Persists folder access via security-scoped bookmarks in UserDefaults
- Renders Markdown via WKWebView using [marked.js](https://github.com/markedjs/marked) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) loaded from CDN
- Drill-down folder browser with per-level loading states for OneDrive latency tolerance
- Basic raw Markdown text editing with save-back

## Key Files

- `od-notes/ODNotesApp.swift` — App entry point, RootView with NavigationStack
- `od-notes/Models/FileItem.swift` — Enum model: `.folder` or `.note`
- `od-notes/Store/NotesStore.swift` — Folder access, directory enumeration, file load/save
- `od-notes/Store/BookmarkManager.swift` — Security-scoped bookmark persistence
- `od-notes/Views/FolderBrowserView.swift` — Recursive drill-down folder/file list
- `od-notes/Views/NoteDetailView.swift` — Markdown view + raw text editor toggle
- `od-notes/Views/FolderPickerButton.swift` — UIDocumentPickerViewController wrapper
- `od-notes/Views/MarkdownView.swift` — SwiftUI wrapper around WKWebView
- `od-notes/Rendering/MarkdownRenderer.swift` — HTML generation with GitHub styling
- `od-notes/Info.plist` — Document type and UTI declarations

## Development

Open `od-notes.xcodeproj` in Xcode. Build and run on iOS Simulator or device.

### Running Tests

```
xcodebuild test -project od-notes.xcodeproj -scheme od-notes -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or use Cmd+U in Xcode.

## Conventions

- Bundle identifiers should start with `com.wandermyz.`

## Bundle ID

`com.wandermyz.od-notes`
