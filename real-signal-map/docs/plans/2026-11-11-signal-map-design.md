# signal-map — design (draft)

An iOS app that maps whether mobile data actually reaches the internet. It ignores the signal bars. While you move, it probes a well-known endpoint over the **cellular radio**, records latency or failure together with GPS, and draws the results on an Apple Map.

Mocks: [`../mocks/mocks.png`](../mocks/mocks.png) (source: `../mocks/mocks.html`)

---

## 1. Measuring "real" signal

| Choice | Decision | Why |
|---|---|---|
| Probe | **HTTPS GET `https://www.gstatic.com/generate_204`**, read the first byte | iOS has no real ICMP ping, and ICMP can be blocked or prioritized differently from data anyway. An HTTP round trip goes through the same path real apps use: DNS, the carrier's NAT and proxies, and the CDN. A 204 reply is almost empty, so each probe costs about 1 KB. |
| Interface | `NWConnection` with `requiredInterfaceType = .cellular` | With CarPlay, a car hotspot, or a passing Wi‑Fi network, a normal request would measure Wi‑Fi. This keeps every probe on cellular. |
| What "latency" means | **Request RTT on a warm connection**, with connection-setup time recorded separately | A warm RTT shows the condition of the link. Connection setup (DNS, TCP, TLS) shows the cost of recovering after a dropout. The connection is kept alive and rebuilt automatically when it breaks. |
| Failure | No reply within a **timeout of 4 s** (configurable) → `status = timeout`. Error or no cellular path → `status = noPath` | These points matter most and are drawn in purple. |
| Cadence | Every **5 s or every 100 m, whichever comes first**. At most 1 probe in flight. Paused when stationary for more than 2 min | Keeps points evenly spaced on the highway and avoids flooding them in traffic. |
| Context per sample | radio tech (5G/LTE/3G via `CTTelephonyNetworkInfo`), GPS accuracy, speed, heading | Lets you check results like "dead spot = fell back to 3G". |

**Background:** a `CLLocationManager` session in the background location mode keeps the app alive while it is recording. You can lock the phone while driving. Optionally, recording can start and stop on its own using `CMMotionActivity` (automotive).

## 2. Data model and storage

**SQLite** (GRDB.swift), one append-only table. A row is a fixed set of numbers, so this stays compact and fast to query by range. SwiftData would be much slower at about 500k rows.

```sql
CREATE TABLE sample (
  id        INTEGER PRIMARY KEY,   -- monotonic, also the eviction cursor
  ts        INTEGER NOT NULL,      -- unix ms
  lat       REAL    NOT NULL,
  lon       REAL    NOT NULL,
  h_acc     REAL,                  -- metres; points > 100 m are dropped at ingest
  speed     REAL,                  -- m/s
  rtt_ms    INTEGER,               -- NULL when failed
  setup_ms  INTEGER,               -- set when the probe opened a new connection
  status    INTEGER NOT NULL,      -- 0 ok, 1 timeout, 2 error, 3 no cellular path
  radio     INTEGER,               -- enum: 5G-SA/5G-NSA/LTE/3G/2G/unknown
  session   INTEGER NOT NULL       -- one recording session; used to break polylines
);
CREATE INDEX sample_ts ON sample(ts);
```

* **Size:** about 45 B per row including the index, so **500k points ≈ 22 MB**. At 1 point per 5 s, that is about 700 hours of recording, or roughly 1 year of 2 h daily commutes.
* **Cap / eviction (ring buffer):** the default cap is 500,000 and can be set from 50k to 2M. After each batch insert, if `count > cap × 1.01`, the app runs `DELETE FROM sample WHERE id <= (SELECT max(id) FROM sample) - cap`. `id` is monotonic, so this is one range delete on the primary key: oldest first, with no scan. The 1% slack means it runs in batches instead of once per row.
* **Write path:** samples are buffered in memory and flushed in one transaction every 10 samples or 30 s, and whenever the app goes to the background. WAL mode is on.
* **Sessions table** (tiny): start/end/distance/count, used by the Live summary and the future "show trip" view.

## 3. Visualisation and time slicing

**Query:** `WHERE ts BETWEEN ? AND ? AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?`, run off the main thread. Two display modes depend on zoom:

| Zoom | Mode | How |
|---|---|---|
| Street level (< ~2 km across) | **Raw trace** | Each sample is a short segment colored by latency. Each pass is drawn slightly offset so repeated drives stay visible (mock 3). |
| Wider | **Aggregated grid** | `GROUP BY` a cell key (`floor(lat/size), floor(lon/size)`), with cell size based on zoom (50 m → 5 km). The app computes median, P90, worst, and fail % per cell. A cell is purple if its fail rate is over 25% (mock 2). |

* Rendering uses a custom `MKOverlay` and `MKOverlayRenderer` in `MKMapView`, wrapped for SwiftUI, and draws everything in one pass. SwiftUI `Map` with one `MapPolyline` per segment slows down after a few thousand.
* **Colors:** green < 150 ms · yellow < 400 ms · orange < 1 s · red ≥ 1 s · purple = no internet.
* **Time slice control (mock 2):** preset chips (Today / 24h / 7d / 30d / All / Custom). Below them is a **timeline histogram** of how many samples exist per 6 h across all stored data, with two handles to drag. Gaps where you didn't drive show up immediately, and you can stretch the range over days. A metric toggle switches between Median / P90 / Worst / Fail %.
* **Tap a spot (mock 3):** a callout shows cell stats, radio mix, last pass, and a strip of latency for each pass.

## 4. Screens

1. **Live:** map that follows you with the trace drawn, a status pill (recording, radio, elapsed), and a bottom card with the last probe, a 2‑min sparkline, session stats, and Start/Stop.
2. **History:** aggregated map, time slice sheet, metric toggle, legend.
3. **Spot detail:** callout on tap.
4. **Settings:** probe target, cadence, timeout, cellular only, max points with a usage bar, auto-start when driving, export CSV/GPX, delete all.

## 5. Tech

SwiftUI, iOS 17+. GRDB.swift (SPM) for storage. Network.framework for probes. CoreLocation (background location). CoreTelephony for the radio type. CoreMotion for auto-start (optional). It would be published through ios-dist like the other apps.

## 6. Open questions

See the chat. The answers will be folded back into this doc before implementation.

---

## 7. Decisions (2026-11-11, after review)

1. Purpose: evaluate online-meeting / video quality → warm-connection RTT is the primary metric; jitter (mean |ΔRTT| per pass) is shown in the spot detail.
2. Cellular only, always.
3. Recording auto-starts whenever the app is in the foreground; no start/stop button, no background recording (screen kept awake instead).
4. Cadence: every 5 s or every 10 m, whichever first (one probe in flight).
5. Cap: 500k points (adjustable).
6. No dual-SIM handling.
7. No export, no per-trip picker.
8. Name: **Real Signal Map** (directory `real-signal-map`).
