# wandering-md

Minimal iOS app for viewing Markdown files with GitHub-style rendering.

## Architecture

- **SwiftUI app** targeting iOS 16+
- Renders Markdown via WKWebView using [marked.js](https://github.com/markedjs/marked) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) loaded from CDN
- Registers as a handler for `.md` files via `CFBundleDocumentTypes` and `UTImportedTypeDeclarations` in Info.plist, making it appear in the system Share sheet
- No persistent storage: files are read on open and never saved

## Key Files

- `wandering-md/WanderingMdApp.swift` — App entry point, handles `onOpenURL` for incoming files
- `wandering-md/ContentView.swift` — Main view, shows markdown or placeholder
- `wandering-md/MarkdownRenderer.swift` — Generates HTML page with GitHub styling (testable, pure logic)
- `wandering-md/MarkdownView.swift` — SwiftUI wrapper around WKWebView
- `wandering-md/Info.plist` — Document type and UTI declarations

## Development

Open `wandering-md.xcodeproj` in Xcode. Build and run on iOS Simulator or device.

### Running Tests

```
xcodebuild test -project wandering-md.xcodeproj -scheme wandering-md -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or use Cmd+U in Xcode.

## Conventions

- Bundle identifiers should start with `com.wandermyz.`

## Bundle ID

`com.wandermyz.wandering-md`
