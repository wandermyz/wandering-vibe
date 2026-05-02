---
name: web
description: Use Playwright-CLI to perform web browsing tasks such as searching, navigating websites, filling forms, extracting information, and taking screenshots.
argument-hint: "[what to do on the web]"
allowed-tools: Bash(playwright-cli:*)
---

# Web Browsing with playwright-cli

Use `playwright-cli` to complete the requested web task. **Always open the browser in headed mode with Chrome:**

```bash
playwright-cli open --headed --browser=chrome <url>
```

## Workflow

1. Open browser in headed mode: `playwright-cli open --headed --browser=chrome <url>`
2. Accept any cookie/consent dialogs if present
3. Interact with the page using snapshot refs (click, fill, select, etc.)
4. Take snapshots to observe page state after interactions
5. Extract and report the requested information
6. Close the browser when done: `playwright-cli close`

## Key rules

- **Always use `--headed --browser=chrome`** when opening the browser
- Use `playwright-cli snapshot` to get current page state and element refs
- Prefer `fill` over `type` for form inputs
- After navigation or clicks, check the snapshot before proceeding
- For dropdowns/autocomplete, fill the field then snapshot to see suggestions, then click the right option
- **Screenshots must be saved to `~/.yuki-conductor/workspace/attachments/`** with a date-prefixed filename:
  ```bash
  playwright-cli screenshot --filename=~/.yuki-conductor/workspace/attachments/YYYY-MM-DD-<descriptive-name>.png
  ```
- After saving a screenshot, always output **only the filename** (not the full path) wrapped in actual `<attachment>` tags as a standalone line in your response. The output must look exactly like this (not in a code block, not in backticks):

<attachment>2026-03-12-flight-results.png</attachment>

- If the final page has a stable URL, include it as a markdown link in your response, e.g.: [View on united.com](https://www.united.com/...)

## Task

ARGUMENTS: {{ARGUMENTS}}
