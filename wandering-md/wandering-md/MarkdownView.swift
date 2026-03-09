import SwiftUI
import WebKit

struct MarkdownView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = MarkdownRenderer.renderHTML(markdown: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }
}
