import SwiftUI
import UIKit

struct ContentView: View {
    @Binding var markdownContent: String?
    @Binding var fileName: String?

    var body: some View {
        if let content = markdownContent {
            NavigationStack {
                MarkdownView(markdown: content)
                    .navigationTitle(fileName ?? "Markdown")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                markdownContent = nil
                                fileName = nil
                                // Suspend the app to return to the app that shared the file.
                                // iOS has no public API to navigate back to the previous app,
                                // but suspending achieves the same effect.
                                UIControl().sendAction(
                                    #selector(URLSessionTask.suspend),
                                    to: UIApplication.shared,
                                    for: nil
                                )
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Markdown File Open")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Use the Share button from Files, Safari,\nor other apps to open a .md file here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
