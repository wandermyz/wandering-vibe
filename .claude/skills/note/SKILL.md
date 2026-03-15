---
name: note
description: Read and write Obsidian notes in the project vault. Use this skill whenever the user mentions saving to notes, checking notes, reading notes, writing notes, daily notes, or anything related to their personal Obsidian notebook. Also trigger when the user says "save this to my notes", "add a note", "check my notes", "what's in my notes", "note this down", or similar phrases about personal note-taking.
---

# Obsidian Notes Skill

Read and write notes in the project's Obsidian vaults.

## Vault Location

- **Base path**: `obsidian/` under the project root (i.e., `{{PROJECT_DIR}}/obsidian`)
- The `obsidian/` folder contains **multiple vault subfolders** (e.g., `obsidian/wandermyz-liz/`). Each subfolder is an independent Obsidian vault.
- The vault is git-ignored — never commit vault contents.

## Discovering Vaults

List the immediate subdirectories of `obsidian/` to discover available vaults. Each subdirectory name is the vault name.

If the user doesn't specify which vault, default to the first available vault. If there are multiple vaults, ask the user which one to use when ambiguous.

## Folder Structure (per vault)

Within each vault, only two folders are in scope:

| Folder | Purpose |
|--------|---------|
| `<vault>/Daily/` | Daily notes, named by date (e.g., `2026-03-13.md`) |
| `<vault>/Notes/` | Default location for all other notes |

**Ignore all other folders** within the vault (e.g., `OpenClaw`, `yuki-workspace`, attachments). Do not read from or write to them.

## Writing Notes

When the user asks to save, create, or update a note:

1. **Determine the vault and target folder:**
   - Pick the appropriate vault (ask if ambiguous)
   - If the note is a daily journal/log entry → `<vault>/Daily/` with filename `YYYY-MM-DD.md`
   - Otherwise → `<vault>/Notes/` with a descriptive filename

2. **Use the `obsidian-markdown` skill** to write the note content. This ensures proper Obsidian Flavored Markdown with wikilinks, callouts, properties, and other Obsidian-specific syntax.

3. **Use wikilinks** (`[[Note Name]]`) to link between notes within the vault.

## Reading Notes

When the user asks to check, read, or search their notes:

1. Search only within `<vault>/Daily/` and `<vault>/Notes/` folders across all vaults (or a specific vault if the user specifies).
2. Use Glob and Grep to find relevant files and content.
3. Read the matching files and present the information.

## Citing Sources

When responding with content retrieved from notes, **always cite sources** using Obsidian URI links so the user can click to open the note directly.

The vault name in the URI is the **subfolder name** (not "obsidian"):

```
[Note Title](obsidian://open?vault=<vault-name>&file=<folder>/<filename>)
```

For example, if the vault subfolder is `wandermyz-liz`:
- `[2026-03-13](obsidian://open?vault=wandermyz-liz&file=Daily%2F2026-03-13)`
- `[TODO](obsidian://open?vault=wandermyz-liz&file=Notes%2FTODO)`

Rules for citations:
- The vault name is the subfolder name under `obsidian/`, **not** "obsidian" itself
- URL-encode the file path (e.g., spaces become `%20`, slashes become `%2F`)
- Omit the `.md` extension in the file parameter
- If information comes from multiple notes, cite **all** sources
- Place citations inline near the relevant information, not just at the end
