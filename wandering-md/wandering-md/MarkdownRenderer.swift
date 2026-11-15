import Foundation

enum MarkdownRenderer {
    /// Pele (https://github.com/obsidianmd/pele) renders ```mermaid blocks to SVG.
    /// Loaded on demand, only when the document contains a mermaid block.
    static let mermaidScriptURL = "https://cdn.jsdelivr.net/npm/pele@1.13.0/dist/pele.global.js"

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
                /* Pele diagram colors, matched to github-markdown-css. */
                .markdown-body {
                    --pele-bg: #ffffff;
                    --pele-fg: #1f2328;
                    --pele-muted: #59636e;
                    --pele-line: #59636e;
                    --pele-surface: #f6f8fa;
                    --pele-surface-alt: #eff2f5;
                    --pele-border: #d1d9e0;
                    --pele-accent: #0969da;
                    --pele-critical: #cf222e;
                    --pele-error: #cf222e;
                    --pele-font: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
                    --pele-font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
                }
                @media (prefers-color-scheme: dark) {
                    .markdown-body {
                        --pele-bg: #0d1117;
                        --pele-fg: #f0f6fc;
                        --pele-muted: #9198a1;
                        --pele-line: #9198a1;
                        --pele-surface: #151b23;
                        --pele-surface-alt: #212830;
                        --pele-border: #3d444d;
                        --pele-accent: #4493f8;
                        --pele-critical: #f85149;
                        --pele-error: #f85149;
                    }
                }
                .markdown-body pre.mermaid {
                    visibility: hidden;
                }
                .markdown-body .mermaid-diagram {
                    display: block;
                    margin-bottom: 16px;
                    text-align: center;
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

                function renderMermaid(nodes) {
                    for (const node of nodes) {
                        const source = node.textContent;
                        const container = document.createElement('div');
                        container.className = 'mermaid-diagram';
                        node.replaceWith(container);
                        try {
                            const diagram = pele.mount(container, source);
                            if (!diagram.result) {
                                diagram.destroy();
                                const error = diagram.error;
                                showMermaidFallback(container, source, (error && error.message) || 'could not render diagram');
                            }
                        } catch (e) {
                            showMermaidFallback(container, source, (e && e.message) || String(e));
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
