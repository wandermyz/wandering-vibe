# ios-dist — Self-hosted iOS App Distribution over Tailscale

**Date:** 2026-10-08
**Status:** Implemented (Phases 1–3; signing pending a paid team on this Mac). Phase 4 partially via localStorage update labels.

## Goal

A private "mini App Store" running on the Mac mini (`<mac-mini>.<tailnet>.ts.net`), reachable only over Tailscale. From Safari on an iPhone/iPad I can see my apps (`wandering-md`, `od-notes`, `voice-memo`, future ones), install them, and update them to the latest build with one tap.

## Assumptions

- Paid Apple Developer Program membership.
- Device UDIDs are registered in the developer portal, so ad hoc profiles include them.
- The iOS device runs the Tailscale app with MagicDNS on.
- Only my own devices use this. No public access.

## How OTA install works (the constraints)

iOS installs apps from the web with a link like this:

```
itms-services://?action=download-manifest&url=https://<host>/apps/<bundleId>/manifest.plist
```

Hard requirements:

1. **The manifest and the IPA must be served over HTTPS with a certificate the device trusts.** Self-signed certificates don't work without extra profile setup. **Tailscale Serve** fixes this: it gets a Let's Encrypt certificate for `*.ts.net` and terminates TLS. Nothing is exposed outside the tailnet. Do **not** use Funnel.
2. **The IPA must be signed for the device.** Export it with method `release-testing` (ad hoc; called `ad-hoc` before Xcode 15). Ad hoc builds don't need Developer Mode on the device. Development-signed builds do, so we avoid them.
3. **Updates** happen when you install the same bundle ID with a higher `CFBundleVersion`. iOS replaces the app in place and keeps its data. Right now every project has `CURRENT_PROJECT_VERSION = 1`, so the publish step must bump the build number automatically.
4. Safari can't see which apps or versions are installed. To show "update available" accurately, the apps themselves have to report it (see Phase 4).

## Architecture

```
 ┌──────────── Mac mini ────────────────────────────────────────────┐
 │                                                                  │
 │  publish.sh <project>                                            │
 │    xcodebuild archive → exportArchive (release-testing)          │
 │    → extract Info.plist + icon → ~/.ios-dist/apps/...            │
 │                                                                  │
 │  ios-dist server (Node/TS, 127.0.0.1:8740, LaunchAgent)          │
 │    GET /                         app list (HTML)                 │
 │    GET /apps/:bundleId           app page + build history        │
 │    GET /apps/:id/:build/manifest.plist   (generated)             │
 │    GET /apps/:id/:build/app.ipa          (static)                │
 │    GET /api/apps                 JSON catalog                    │
 │    GET /api/apps/:id/latest      JSON, used by in-app checker    │
 │                                                                  │
 │  tailscale serve --bg --https=443 http://127.0.0.1:8740          │
 └──────────────────────────────────────────────────────────────────┘
            ▲  HTTPS (valid *.ts.net cert), tailnet only
            │
      iPhone (Safari + Tailscale)
```

### Repo layout (`ios-dist/`, committed)

```
ios-dist/
  CLAUDE.md
  package.json, tsconfig.json     # same style as nav-mcp
  src/server.ts                   # http server, no framework (node:http)
  src/catalog.ts                  # reads ~/.ios-dist/apps, builds the index
  src/manifest.ts                 # renders manifest.plist
  src/views.ts                    # HTML templates (mobile-first, no JS needed)
  scripts/publish.sh              # build + export + ingest one project
  scripts/ingest.ts               # ingest an existing .ipa (any source)
  config/projects.json            # project → xcodeproj, scheme mapping
  config/ExportOptions.plist      # method=release-testing, teamID, automatic signing
  launchd/com.wandermyz.ios-dist.plist
  docs/plans/...
```

### Data (NOT in git): `~/.ios-dist/`

```
~/.ios-dist/
  apps/<bundleId>/
    app.json                      # name, bundleId, icon path
    icon.png                      # 512px, from the asset catalog
    builds/<buildNumber>/
      app.ipa
      meta.json                   # version, build, size, sha256, date, git commit, notes
  logs/                           # server + publish logs (outside workspace/)
  derived/                        # xcodebuild archives / DerivedData
```

The server keeps no database. The directory tree is the catalog, and the server rescans it on each request (it's cheap at this scale). Retention: keep the last N builds per app (default 5) so I can roll back. Rolling back works by installing an older build, which iOS allows for ad hoc installs.

## Phases

### Phase 0: Prerequisites (manual, ~15 min)

- [ ] Tailscale admin console: turn on **MagicDNS** and **HTTPS Certificates**.
- [ ] On the Mac mini: `tailscale cert <mac-mini>.<tailnet>.ts.net` once to check that certificate issuance works.
- [ ] Check that Xcode (26.3) is signed into the Apple ID for your team, so `-allowProvisioningUpdates` can create and refresh ad hoc profiles headlessly. Note: Xcode 26 / `xcodebuild` may require an App Store Connect API key (`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`) for unattended signing. Create one with the Developer role and store it in `~/.ios-dist/secrets/`, never in the repo.
- [ ] Confirm the device UDID(s) are in Certificates, Identifiers & Profiles → Devices.

### Phase 1: Manual proof of concept (validate the risky part first)

1. Archive and export `wandering-md` by hand:
   ```sh
   xcodebuild -project wandering-md/wandering-md.xcodeproj -scheme wandering-md \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath ~/.ios-dist/derived/wmd.xcarchive \
     CURRENT_PROJECT_VERSION=$(date +%Y%m%d%H%M) archive -allowProvisioningUpdates
   xcodebuild -exportArchive -archivePath ~/.ios-dist/derived/wmd.xcarchive \
     -exportOptionsPlist ios-dist/config/ExportOptions.plist \
     -exportPath ~/.ios-dist/derived/wmd-export -allowProvisioningUpdates
   ```
2. Write a manifest.plist by hand. Serve the folder with `python3 -m http.server` behind `tailscale serve`.
3. Open an HTML page with the `itms-services://` link in Safari on the iPhone. Confirm it installs, and that a second, higher build updates in place with data kept.

**Exit criterion:** an install and an in-place update both work over Tailscale. If this fails, everything else is moot.

### Phase 2: Publish pipeline (`scripts/publish.sh`)

`publish.sh <project> [--notes "..."]`:

1. Look up the project in `config/projects.json` (xcodeproj path and scheme).
2. Build number = `date +%Y%m%d%H%M`, passed as `CURRENT_PROJECT_VERSION=` so the project files aren't changed. Keep `MARKETING_VERSION` from the project.
3. Archive, then `-exportArchive` with `release-testing` (ExportOptions: `method=release-testing`, `signingStyle=automatic`, `teamID=<from local config>`, `compileBitcode=false`, `thinning=<none>`).
4. Ingest the IPA (`scripts/ingest.ts`):
   - unzip `Payload/*.app/Info.plist` → `plutil -convert json` → bundle ID, `CFBundleShortVersionString`, `CFBundleVersion`, display name
   - pull the app icon out of the `.app`: take the largest `AppIcon*.png`, and if it's CgBI-crushed, re-render it with `sips`, or else export the icon from the source `.xcassets`
   - compute size and sha256, record `git rev-parse HEAD` of the project, write `meta.json`
   - check the embedded profile with `security cms -D -i embedded.mobileprovision`: warn if it expires within 30 days, and list `ProvisionedDevices`
   - prune builds older than the retention limit
5. Optional: send a Pushover / yuki-conductor message: "wandering-md 1.0 (202610081530) published".

Extension note: `od-notes` has a File Provider extension, and possibly app groups. Automatic signing with `-allowProvisioningUpdates` creates ad hoc profiles for each target. Check that the extension is signed inside the exported IPA.

### Phase 3: Web server

- Node + TypeScript using `node:http` only, with no framework (matches `nav-mcp`). Bind to `127.0.0.1` only, because Tailscale Serve is the only way in.
- **`/` (app list):** one card per app with icon, name, latest version (build), date, size, and an **Install / Update** button that points to `itms-services://...`. Server-rendered HTML that works in Safari with no JS.
- **`/apps/:bundleId`:** build history with release notes and git commits, plus an install button for each build (rollback).
- **`manifest.plist`:** generated per build, using the absolute `https://<mac-mini>.<tailnet>.ts.net/...` URLs for `software-package`, `display-image` (57px) and `full-size-image` (512px). The `url` param in `itms-services` must be URL-encoded.
- Content types: `application/octet-stream` for `.ipa`, `text/xml` for `.plist`. Support `Range` and `Content-Length` for large IPAs.
- **`/api/apps` and `/api/apps/:id/latest`:** JSON (`{bundleId, version, build, installUrl, notes}`).
- Add an `apple-touch-icon` + web app manifest so the page can be pinned to the home screen as "My Apps".
- Auth: rely on tailnet ACLs. Optionally check the `Tailscale-User-Login` header that `tailscale serve` injects, and allow only my login.

Deployment:
- `launchd/com.wandermyz.ios-dist.plist` → `~/Library/LaunchAgents/`, with `KeepAlive` on, logs in `~/.ios-dist/logs/`, and the same pattern as `com.wandermyz.litellm`.
- `tailscale serve --bg --https=443 http://127.0.0.1:8740`. This persists across reboots. If another service later needs 443, use a path mount instead (`--set-path /apps`).

### Phase 4: "Update available" (optional, but it's what makes updates actually work)

Safari can't detect installed versions, so add a tiny shared Swift package, `IOSDistUpdater`, to each app:
- On launch or foreground, `GET https://<mac-mini>.../api/apps/<bundleId>/latest` with a short timeout. If the tailnet isn't reachable, fail silently.
- If `build > Bundle.main CFBundleVersion`, show a small banner, "Update available (1.0 • 202610091200)", that opens the `itms-services://` URL via `UIApplication.shared.open`.
- Compile it in only for non-App Store configurations, or control it with an Info.plist flag, so it never ships to the store.

Fallback without app changes: the web list shows "published N hours ago". The page could also remember installs in `localStorage` per device (approximate) and highlight builds newer than the last one installed from that device.

### Phase 5: Nice-to-haves

- `publish.sh --all` and a yuki-conductor cron for nightly builds of projects with new commits.
- Upload endpoint (`POST /api/upload`, tailnet-only and token-protected) so IPAs built elsewhere (e.g. the MBP) can be published.
- Warnings about profile and certificate expiry shown on the web page and sent through Pushover. Ad hoc profiles last 1 year, and installed apps stop launching when they expire.
- QR code on each app page for adding a new device.

## Gotchas / risks

| Risk | Mitigation |
|---|---|
| Installed app won't open after the profile expires | Expiry check during ingest plus monthly reminder; rebuild and republish before expiry |
| A new device isn't in the profile, so install fails quietly ("Unable to install") | Register the UDID, then republish. `-allowProvisioningUpdates` regenerates the profile |
| Update doesn't take | The build number must go up. The timestamp-based `CURRENT_PROJECT_VERSION` override guarantees it |
| Headless signing fails from launchd/cron (keychain locked) | Run publish from a logged-in session, or use an App Store Connect API key plus an unlocked keychain. Test in Phase 2 |
| Tailscale certificate renewal | `tailscale serve` renews automatically |
| Large IPAs over a slow tailnet path | Range support; fine on LAN/DERP for personal apps |
| Personal data leaks into git | All artifacts, keys and logs live in `~/.ios-dist/`. The repo only holds code and config without secrets |

## Effort estimate

- Phase 0–1: about 1 hour (mostly validation)
- Phase 2: about 2–3 hours
- Phase 3: about 3 hours
- Phase 4: about 2 hours, plus wiring into each app
