import Foundation

enum MarkdownRenderer {
    /// Generates a full HTML page that renders the given markdown content
    /// with GitHub-flavored styling using marked.js and github-markdown-css.
    static func renderHTML(markdown: String) -> String {
        let escaped = escapeForJSTemplateLiteral(markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown.min.css">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.1/marked.min.js"></script>
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: #ffffff;
                }
                @media (prefers-color-scheme: dark) {
                    body { background-color: #0d1117; }
                }
                .markdown-body {
                    box-sizing: border-box;
                    min-width: 200px;
                    max-width: 980px;
                    margin: 0 auto;
                    padding: 24px;
                }
                @media (max-width: 767px) {
                    .markdown-body { padding: 16px; }
                }
            </style>
        </head>
        <body>
            <article class="markdown-body" id="content"></article>
            <script>
                const markdown = `\(escaped)`;
                document.getElementById('content').innerHTML = marked.parse(markdown);
            </script>
        </body>
        </html>
        """
    }

    /// Escapes a string for safe embedding inside a JavaScript template literal.
    static func escapeForJSTemplateLiteral(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
