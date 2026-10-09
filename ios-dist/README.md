# ios-dist

A tiny self-hosted "App Store" for your own iOS apps. Builds are exported as ad hoc IPAs, served
from a Mac over [Tailscale Serve](https://tailscale.com/kb/1312/serve) (real HTTPS, tailnet-only),
and installed or updated from Safari on the device via `itms-services://` OTA links.

## Requirements

- macOS with Xcode, Node ≥ 22, Tailscale (MagicDNS + HTTPS certificates enabled for the tailnet)
- A paid Apple Developer Program team, with the target devices registered (ad hoc profiles must list their UDIDs)

## Setup

```sh
npm install
npm run build
node dist/cli.js init          # creates ~/.ios-dist/config.json (mode 600) from config.example.json
$EDITOR ~/.ios-dist/config.json # teamId, projects, launchdLabel, tailscaleHttpsPort
node dist/cli.js daemon install # LaunchAgent: starts now and at login
node dist/cli.js tailscale enable
```

Open `https://<mac>.<tailnet>.ts.net[:port]/` in Safari on the device.

Personal settings (team ID, project paths, labels) live only in the config file, which is outside
the repo; point `IOS_DIST_CONFIG` elsewhere if needed. All data — IPAs, icons, logs, build work dirs —
lives next to the config (`~/.ios-dist/` by default).

## Commands

| Command | |
|---|---|
| `publish <project> [--notes ..] [--method ..] [--unsigned]` | `xcodebuild archive` + `-exportArchive`, then ingest. The build number is set to `YYYYMMDD.HHmmss` so every publish is an in-place update on device. `--unsigned` skips signing to test the pipeline (the result will not install). |
| `ingest <file.ipa> [--notes ..] [--icon png] [--force]` | Add an IPA built elsewhere. |
| `list` | Show published apps and builds. |
| `daemon install\|uninstall\|start\|stop\|restart\|status\|logs [-f]` | Manage the LaunchAgent. |
| `tailscale enable\|disable\|status` | `tailscale serve --bg --https=<port>` → the local server. |
| `serve` | Run the server in the foreground. |
| `config` | Print the resolved config. |

## Config (`~/.ios-dist/config.json`)

See [config.example.json](config.example.json). Notable keys:

- `teamId` — passed as `DEVELOPMENT_TEAM` and to the export options.
- `exportMethod` — `release-testing` (ad hoc; default), `debugging` (development), `enterprise`.
- `ascApiKey` — `{ keyPath, keyId, issuerId }` App Store Connect API key for unattended signing.
- `keepBuilds` — builds retained per app (older ones are pruned on publish).
- `allowedLogins` — restrict to these Tailscale logins (`Tailscale-User-Login` header).
- `publicBaseUrl` — override the URL used in manifests (normally derived from the `Host` header).
- `tailscaleHttpsPort` — HTTPS port on the tailnet (use e.g. 8443 if 443 is taken).

## HTTP endpoints

| Path | |
|---|---|
| `/` | App list (Install / Update / Reinstall, remembered per device in `localStorage`) |
| `/apps/<bundleId>` | App page with build history (older builds installable = rollback) |
| `/apps/<bundleId>/builds/<build>/manifest.plist` | OTA manifest |
| `/apps/<bundleId>/builds/<build>/app.ipa` | IPA (supports `Range`) |
| `/api/apps`, `/api/apps/<bundleId>`, `/api/apps/<bundleId>/latest` | JSON for in-app update checks |
| `/healthz` | Health check |

## Development

```sh
npm run check   # typecheck + eslint + vitest
npm run dev     # tsx src/cli.ts serve
```
