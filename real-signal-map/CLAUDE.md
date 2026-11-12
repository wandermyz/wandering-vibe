# real-signal-map

iOS app ("Real Signal Map") that maps whether mobile data *actually works*: while the app is in the foreground it probes an HTTPS endpoint over the cellular radio, records latency / failure with GPS, and draws it on an Apple Map. Target use: judging video-call quality along driving routes.

Design + mocks: [docs/plans/2026-11-11-signal-map-design.md](docs/plans/2026-11-11-signal-map-design.md), [docs/mocks/](docs/mocks/).

## Behaviour

- **Recording is automatic** while the app is active (`scenePhase == .active`), paused in background. No start/stop button; screen is kept awake while recording. No background location mode.
- **Probe:** raw HTTP/1.1 `GET` over `NWConnection` + TLS with `requiredInterfaceType = .cellular` (never Wi‑Fi), kept alive. `rtt_ms` = request → full response headers on the warm connection; `setup_ms` = DNS+TCP+TLS when it had to reconnect. Timeout (default 4 s) ⇒ `timeout`; no cellular path ⇒ `noPath`. A kept-alive connection that the server closed is retried once silently.
- **Cadence:** every N s or M m moved, whichever first (Settings; defaults 5 s / 50 m, read live by the Recorder); one probe in flight at a time; fixes with accuracy > 100 m are skipped.
- **Storage:** SQLite (`Application Support/samples.sqlite`, WAL) via the C API, one `sample` table indexed on `ts`. Ring buffer: default cap 500k; when count > cap·1.01 delete `id <= maxId - cap` (ids are contiguous because only prefixes are deleted). Writes batched every 10 samples / 30 s / on background, on a serial queue.
- **History:** time range presets + timeline histogram with drag handles; viewport query padded 25%. Map width ≤ 3 km ⇒ raw colored trace; wider ⇒ grid cells (25 m–50 km, ~45 across) colored by Median / P90 / Worst / Fail %. Cells with >25% failures are purple. Tap ⇒ stats card (median, P90, jitter, fail %, radio mix, per-pass strips).

## Key files

- `RealSignalMap/Probe/Prober.swift` — cellular NWConnection probe + minimal HTTP response parser
- `RealSignalMap/Recording/Recorder.swift` — foreground lifecycle, CLLocationManager, probe scheduling, session stats, batching
- `RealSignalMap/Storage/SampleStore.swift` — SQLite store, eviction, range/bbox queries, histogram
- `RealSignalMap/Map/Aggregation.swift` — `SpotStats`, grid bucketing, trace segments (pure, unit-tested)
- `RealSignalMap/Map/SignalMapView.swift` — MKMapView wrapper + single custom overlay renderer
- `RealSignalMap/Map/HistoryModel.swift` — History state, queries, tap detail
- `RealSignalMap/Views/*` — Live, History (+ TimelineSlider), SpotDetailCard, Settings
- `RealSignalMap/App/DemoData.swift` — DEBUG-only synthetic drives (`-seedDemo` launch arg)

## Development

The Xcode project is generated: edit `project.yml`, then `xcodegen generate`.

```bash
xcodebuild test -project RealSignalMap.xcodeproj -scheme RealSignalMap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Simulator has no cellular, so every probe is `noPath` there. For screenshots: launch with `-seedDemo` (seeds 10 days of drives into an empty DB) and `-initialTab 1|2`.

Publish to the phone via ios-dist project key `real-signal-map`.
