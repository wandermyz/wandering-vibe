# ios-dist

Self-hosted iOS OTA distribution over Tailscale. TypeScript, Node built-ins only at runtime (no deps),
vitest + eslint for dev. See [README.md](README.md) for usage and [docs/plans](docs/plans/) for the design.

## Rules

- **This repo is public.** Never commit team IDs, hostnames, tailnet names, Apple IDs, or project paths.
  Those belong in `~/.ios-dist/config.json` (gitignored by living outside the repo).
- Data (IPAs, icons, logs, work dirs) lives in the config's directory (`~/.ios-dist/`), never in the repo.
- Run `npm run check` before finishing a change; `npm run build` + `node dist/cli.js daemon restart` to deploy.

## Layout

- `src/cli.ts` — command dispatch
- `src/server.ts` — `node:http` server, routing, Range support, base URL resolution
- `src/views.ts` — server-rendered HTML (mobile-first, light/dark)
- `src/catalog.ts` — on-disk catalog `apps/<bundleId>/builds/<build>/{app.ipa,meta.json}`; id validation = path-traversal guard
- `src/ingest.ts`, `src/ipa.ts` — IPA inspection via `unzip`/`plutil`/`security cms`, icon extraction
- `src/publish.ts` — `xcodebuild archive`/`-exportArchive`
- `src/launchd.ts`, `src/tailscale.ts` — LaunchAgent and `tailscale serve` management

## Gotchas

- iOS only updates in place when `CFBundleVersion` increases; publish overrides it with `YYYYMMDD.HHmmss`.
- Compiled icons in IPAs are CgBI PNGs; they're reverted with `xcrun pngcrush -revert-iphone-optimizations`.
  `publish` prefers the 1024px source from `AppIcon.appiconset`.
- `launchctl stop`/kill won't stop a KeepAlive agent; `daemon stop` uses `bootout`.
