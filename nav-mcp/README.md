# nav-mcp

MCP server that exposes Google Routes API for travel-time queries. Built so Claude Code can answer questions like "how long does it take to drive from A to B?".

## Tool

- **`drive_time`** — origin + destination (+ optional stops) → live-traffic duration, free-flow duration, distance, optional turn-by-turn.
  - `origin`, `destination` *(required)*: address, place name, or `lat,lng`.
  - `waypoints` *(optional)*: ordered list of intermediate stops (up to 25). Output adds a per-leg breakdown when present.
  - `optimize_waypoint_order` *(optional, default `false`)*: let Google reorder waypoints to minimize total travel time.
  - `include_steps` *(optional, default `false`)*: include turn-by-turn navigation instructions per leg.
  - `travel_mode` *(optional)*: `DRIVE` *(default)*, `BICYCLE`, `WALK`, `TWO_WHEELER`, `TRANSIT`.
  - `routing_preference` *(optional)*: `TRAFFIC_AWARE` *(default)*, `TRAFFIC_AWARE_OPTIMAL`, `TRAFFIC_UNAWARE`.
  - `departure_time` *(optional)*: ISO-8601 future timestamp; defaults to now.
  - `units` *(optional)*: `IMPERIAL` *(default)* or `METRIC`.

## Setup

### 1. Get a Google Maps API key

Google Maps Platform uses **API keys**, not OAuth scopes. The Routes API has no scope to authorize — what matters is which **API** is enabled on the key and which **API key restrictions** you set.

#### What you need

| Item | Value |
|---|---|
| Google API to enable | **Routes API** (`routes.googleapis.com`) |
| Credential type | **API key** (not OAuth, not service account) |
| OAuth scope | None — Routes API doesn't use OAuth scopes |
| Billing | Required — Google Maps Platform won't issue keys without a billing account, even for free-tier use |
| Free tier | $200/mo credit on the consumer plan; `computeRoutes` Basic is ~$5 / 1 000 calls, so personal use is effectively free |

#### Step-by-step

1. **Sign in** to [console.cloud.google.com](https://console.cloud.google.com) with your Google account.

2. **Create or pick a project.** Top bar → project picker → "New Project" → name it e.g. `nav-mcp`. Make sure it's the active project before continuing.

3. **Attach a billing account.** Left nav → **Billing**. If you don't have one, click "Link a billing account" → "Create billing account" and add a card. Google Maps Platform requires this even for free-tier usage; you won't be charged unless you exceed the $200/mo credit.

4. **Enable the Routes API.** Left nav → **APIs & Services → Library** → search "Routes API" → click the result titled **Routes API** (publisher: Google Enterprise API) → **Enable**.
   - Don't confuse it with the older "Directions API" or "Distance Matrix API". This server uses the new Routes API; if you only enable the older ones, calls will return `403 PERMISSION_DENIED`.
   - You can leave other Maps APIs disabled.

5. **Create the API key.** Left nav → **APIs & Services → Credentials** → **+ Create Credentials → API key**. Copy the generated key — this is what goes into `GOOGLE_MAPS_API_KEY`.

6. **Restrict the key** (strongly recommended — an unrestricted key leaked anywhere can rack up bills):
   - Click the key in the credentials list → **Edit API key**.
   - Under **API restrictions** → "Restrict key" → check **Routes API** only → Save.
   - Under **Application restrictions**, since this server runs locally over stdio:
     - Easiest: leave as **None** (fine for personal local use, since the key never leaves your machine).
     - Stricter: choose **IP addresses** and add your home/work IPs. *Don't* pick HTTP referrers or Android/iOS apps — those break server-side calls.

7. **Sanity check** with curl before plugging it into Claude:

   ```sh
   export GOOGLE_MAPS_API_KEY=YOUR_KEY
   curl -s -X POST https://routes.googleapis.com/directions/v2:computeRoutes \
     -H "Content-Type: application/json" \
     -H "X-Goog-Api-Key: $GOOGLE_MAPS_API_KEY" \
     -H "X-Goog-FieldMask: routes.duration,routes.distanceMeters" \
     -d '{
       "origin": {"address": "SFO"},
       "destination": {"address": "Palo Alto, CA"},
       "travelMode": "DRIVE",
       "routingPreference": "TRAFFIC_AWARE"
     }'
   ```

   Expected: a JSON body containing `routes[0].duration` (e.g. `"1834s"`) and `distanceMeters`. If you get `403 PERMISSION_DENIED` or `API_KEY_SERVICE_BLOCKED`, the key isn't allowed to call Routes API — re-check steps 4 and 6. `400 FAILED_PRECONDITION` usually means billing isn't linked.

### 2. Install + build

```sh
cd nav-mcp
npm install
npm run build
```

### 3. Register with Claude Code (replace the key)

```sh
claude mcp add nav \
  --scope user \
  --env GOOGLE_MAPS_API_KEY=YOUR_KEY_HERE \
  -- node /Users/wandermyz.bot/Projects/wandering-vibe/nav-mcp/dist/index.js
```

Or for project scope only, swap `--scope user` for `--scope project`.

### 4. Verify

```sh
claude mcp list
```

Then in a Claude Code session, ask: *"How long does it take to drive from SFO to Palo Alto right now?"*
