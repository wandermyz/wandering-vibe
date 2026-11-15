import Foundation

enum MarkdownRenderer {
    /// Mermaid build loaded on demand when the document contains ```mermaid blocks.
    static let mermaidScriptURL = "https://cdn.jsdelivr.net/npm/mermaid@11.17.0/dist/mermaid.min.js"

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
                .markdown-body pre.mermaid {
                    background: transparent;
                    padding: 0;
                    text-align: center;
                    overflow-x: auto;
                }
                .markdown-body pre.mermaid:not([data-processed]) {
                    visibility: hidden;
                }
                .markdown-body pre.mermaid svg {
                    max-width: 100%;
                    height: auto;
                }
                .mermaid-error {
                    color: #cf222e;
                    font-size: 85%;
                    margin-bottom: 4px;
                }
                @media (prefers-color-scheme: dark) {
                    .mermaid-error { color: #f85149; }
                }
            </style>
        </head>
        <body>
            <article class="markdown-body" id="content"></article>
            <script>
                const markdown = `\(escaped)`;
                const mermaidScriptURL = "\(mermaidScriptURL)";

                function escapeHTML(text) {
                    return text
                        .replace(/&/g, '&amp;')
                        .replace(/</g, '&lt;')
                        .replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;');
                }

                // Turn ```mermaid fences into <pre class="mermaid"> placeholders.
                marked.use({
                    renderer: {
                        code(code, infostring) {
                            const lang = (infostring || '').trim().split(/\\s+/)[0].toLowerCase();
                            if (lang === 'mermaid') {
                                return '<pre class="mermaid">' + escapeHTML(code) + '</pre>';
                            }
                            return false;
                        }
                    }
                });

                document.getElementById('content').innerHTML = marked.parse(markdown);

                // Show the diagram source as a regular code block when Mermaid can't render it.
                function showMermaidFallback(node, source, message) {
                    const wrapper = document.createElement('div');
                    if (message) {
                        const error = document.createElement('div');
                        error.className = 'mermaid-error';
                        error.textContent = 'Mermaid: ' + message;
                        wrapper.appendChild(error);
                    }
                    const pre = document.createElement('pre');
                    const codeEl = document.createElement('code');
                    codeEl.textContent = source;
                    pre.appendChild(codeEl);
                    wrapper.appendChild(pre);
                    node.replaceWith(wrapper);
                }

                async function renderMermaid(nodes) {
                    const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    mermaid.initialize({
                        startOnLoad: false,
                        theme: dark ? 'dark' : 'default',
                        securityLevel: 'strict'
                    });
                    for (const node of nodes) {
                        const source = node.textContent;
                        try {
                            await mermaid.run({ nodes: [node] });
                        } catch (e) {
                            showMermaidFallback(node, source, (e && e.message) || String(e));
                        }
                    }
                }

                const mermaidNodes = Array.from(document.querySelectorAll('pre.mermaid'));
                if (mermaidNodes.length > 0) {
                    const script = document.createElement('script');
                    script.src = mermaidScriptURL;
                    script.onload = () => renderMermaid(mermaidNodes);
                    script.onerror = () => mermaidNodes.forEach(node =>
                        showMermaidFallback(node, node.textContent, 'could not load renderer (offline?)'));
                    document.head.appendChild(script);
                }
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
