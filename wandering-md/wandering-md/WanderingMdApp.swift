import SwiftUI

@main
struct WanderingMdApp: App {
    @State private var markdownContent: String?
    @State private var fileName: String?

    var body: some Scene {
        WindowGroup {
            ContentView(markdownContent: $markdownContent, fileName: $fileName)
                .onOpenURL { url in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    markdownContent = try? String(contentsOf: url, encoding: .utf8)
                    fileName = url.lastPathComponent
                }
        }
    }
}
