# voice-memo

iOS voice recorder that records locally and uploads to Google Drive on demand, organized into monthly subfolders. Solves the problem that iOS Voice Memos exports strip the original recording date.

## Architecture

- **SwiftUI app** targeting iOS 16+
- **Auth:** Google OAuth 2.0 with PKCE via `ASWebAuthenticationSession`. Scope is `drive.file` (only files this app creates). The access token lives in memory only — never persisted — and is wiped on app restart. Each tap of the Upload button starts a fresh sign-in.
- **Storage model:** recordings persist locally as `<uuid>.m4a` plus a `<uuid>.json` sidecar (date / duration / location / uploaded flag) in `Documents/recordings/`. The local store is the source of truth; Drive is the backup target.
- **Upload:** manual, triggered from the Library tab. The app lists the contents of each `YYYYMM` subfolder under the configured root, diffs by filename against pending local recordings, and uploads the missing ones. After each successful upload, the sidecar is marked `uploadedAt`.
- **Background recording:** `UIBackgroundModes=audio` plus `AVAudioSession.playAndRecord` keeps recording alive when the app suspends.
- **Filename:** `yyyy-MM-dd HHmm <location>.m4a`. Drive `createdTime` is set to the actual recording start instant.
- **No audio playback** in the library — list-only with date, duration, location.

## Key Files

- `voice-memo/VoiceMemoApp.swift` — App entry, injects shared stores
- `voice-memo/Audio/AudioRecorder.swift` — AVAudioRecorder + session config
- `voice-memo/Drive/OAuthHelpers.swift` — PKCE helpers + reversed-client-ID derivation
- `voice-memo/Drive/OAuthConfig.swift` — client ID + folder ID model
- `voice-memo/Drive/OAuthSession.swift` — ASWebAuthenticationSession flow, in-memory token
- `voice-memo/Drive/DriveClient.swift` — folder ensure, multipart upload, filename listing
- `voice-memo/Models/LocalRecording.swift` — local model + sidecar-backed store
- `voice-memo/Location/LocationProvider.swift` — one-shot fix + reverse geocode
- `voice-memo/Settings/SettingsStore.swift` — client ID + folder ID (UserDefaults)
- `voice-memo/Views/RecordView.swift` — record button, timer, waveform, saves on stop
- `voice-memo/Views/RecordingsListView.swift` — local list + Upload button + diff/upload flow
- `voice-memo/Views/SettingsView.swift` — paste client ID + folder ID
- `voice-memo/Info.plist` — `UIBackgroundModes=audio`, mic + location strings

## Development

Open `voice-memo.xcodeproj` in Xcode. Build and run on device (background audio + location require a real device for full validation; simulator works for UI iteration).

### Setup before first run

1. Create a Google Cloud project, enable the Drive API.
2. **Configure OAuth consent screen** (External, testing mode is fine for personal use). Add your Google account as a test user. The `drive.file` scope is non-sensitive and does not require Google verification.
3. **Create credentials:** APIs & Services → Credentials → Create OAuth client ID → **iOS** application type. Use the app's bundle ID `com.wandermyz.voice-memo`. No client secret is issued (PKCE is used instead).
4. In Google Drive, create the destination folder (e.g. "Voice Memos"). Copy its ID from the URL.
5. Launch the app → Settings → paste the iOS client ID and the folder ID.

Each time you tap **Upload** in the Library tab, the OAuth sheet appears so you can pick the Google account that owns the folder.

## Conventions

- Bundle identifiers should start with `com.wandermyz.`

## Bundle ID

`com.wandermyz.voice-memo`
