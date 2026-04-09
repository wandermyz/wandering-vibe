import XCTest
@testable import od_notes

final class MarkdownRendererTests: XCTestCase {

    // MARK: - HTML Structure

    func testRenderHTMLContainsMarkdownBody() {
        let html = MarkdownRenderer.renderHTML(markdown: "# Hello")
        XCTAssertTrue(html.contains("markdown-body"))
    }

    func testRenderHTMLContainsMarkedJS() {
        let html = MarkdownRenderer.renderHTML(markdown: "test")
        XCTAssertTrue(html.contains("marked.min.js"))
        XCTAssertTrue(html.contains("marked.parse"))
    }

    func testRenderHTMLContainsGitHubCSS() {
        let html = MarkdownRenderer.renderHTML(markdown: "test")
        XCTAssertTrue(html.contains("github-markdown"))
    }

    func testRenderHTMLContainsViewportMeta() {
        let html = MarkdownRenderer.renderHTML(markdown: "test")
        XCTAssertTrue(html.contains("viewport"))
        XCTAssertTrue(html.contains("width=device-width"))
    }

    func testRenderHTMLIsValidHTMLDocument() {
        let html = MarkdownRenderer.renderHTML(markdown: "Hello")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<html>"))
        XCTAssertTrue(html.contains("</html>"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("</body>"))
    }

    // MARK: - Content Embedding

    func testRenderHTMLEmbedsMarkdownContent() {
        let html = MarkdownRenderer.renderHTML(markdown: "# Hello World")
        XCTAssertTrue(html.contains("# Hello World"))
    }

    func testRenderHTMLEmptyMarkdown() {
        let html = MarkdownRenderer.renderHTML(markdown: "")
        XCTAssertTrue(html.contains("markdown-body"))
        XCTAssertTrue(html.contains("marked.parse"))
    }

    // MARK: - JS Template Literal Escaping

    func testEscapeBackticks() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("Use `code` here")
        XCTAssertEqual(result, "Use \\`code\\` here")
    }

    func testEscapeBackslashes() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("path\\to\\file")
        XCTAssertEqual(result, "path\\\\to\\\\file")
    }

    func testEscapeDollarSigns() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("Cost is $100")
        XCTAssertEqual(result, "Cost is \\$100")
    }

    func testEscapeAllSpecialCharacters() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("$`\\")
        XCTAssertEqual(result, "\\$\\`\\\\")
    }

    func testEscapePreservesNewlines() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("line1\nline2")
        XCTAssertEqual(result, "line1\nline2")
    }

    func testNoEscapingNeeded() {
        let result = MarkdownRenderer.escapeForJSTemplateLiteral("Hello World")
        XCTAssertEqual(result, "Hello World")
    }

    // MARK: - Dark Mode Support

    func testRenderHTMLSupportsDarkMode() {
        let html = MarkdownRenderer.renderHTML(markdown: "test")
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    // MARK: - Integration

    func testRenderHTMLEscapesContentInOutput() {
        let html = MarkdownRenderer.renderHTML(markdown: "Use `code` and $var")
        XCTAssertTrue(html.contains("Use \\`code\\` and \\$var"))
    }
}
