import SwiftUI

struct ContentView: View {
    let markdownContent: String?
    let fileName: String?

    var body: some View {
        if let content = markdownContent {
            NavigationStack {
                MarkdownView(markdown: content)
                    .navigationTitle(fileName ?? "Markdown")
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Open a Markdown file using the Share button")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
