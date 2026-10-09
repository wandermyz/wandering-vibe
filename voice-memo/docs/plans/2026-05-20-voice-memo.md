# voice-memo plan (2026-05-20)

## Goal

iOS voice recorder that records locally and uploads to Google Drive on demand, keyed by month folders. Replaces iOS Voice Memos when the user needs real created-date preservation.

## Decisions

### Initial pass (superseded — see below)
- Service account JSON pasted into Settings, JWT signed locally, uploaded automatically when recording stops.

### Current design (2026-05-27 revision)
- **Auth:** OAuth 2.0 + PKCE via `ASWebAuthenticationSession`. Scope `drive.file` (per-app file visibility, no Google verification needed). Token lives in memory only and is wiped on restart. Each Upload tap triggers a fresh sign-in (`prompt=select_account`).
- **Configuration:** user pastes an iOS OAuth client ID (from their Google Cloud project) + a Drive folder ID into Settings.
- **Recording model:** every recording persists locally as `<uuid>.m4a` + `<uuid>.json` sidecar. The sidecar holds the canonical filename, createdAt, duration, location, and (after upload) `uploadedAt` + `driveFileID`.
- **Upload (manual):** triggered from Library tab. Sign-in → for each pending recording, ensure the `YYYYMM` folder exists, list filenames in it, upload only the names not already present. After success, mark the sidecar uploaded.
- **Filename:** `yyyy-MM-dd HHmm <location>.m4a` (timestamp-first sort).
- **Folder layout:** `<rootFolderId>/YYYYMM/<file>.m4a`.
- **Background recording:** `UIBackgroundModes=["audio"]` + `AVAudioSession.playAndRecord` activated for the duration of the take.
- **Library UI:** lists local recordings grouped by month; per-row icon shows uploaded (✓ icloud) vs pending. No audio playback.

## Architecture

```
voice-memo/
  VoiceMemoApp.swift          TabView root; injects SettingsStore, LocalRecordingsStore, OAuthSession
  Audio/
    AudioRecorder.swift       AVAudioRecorder + session, metering
  Drive/
    OAuthHelpers.swift        PKCE verifier/challenge, reversed-client-ID, base64url
    OAuthConfig.swift         client ID + folder ID
    OAuthSession.swift        ASWebAuthenticationSession + token exchange; in-memory only
    DriveClient.swift         ensureFolder, upload(multipart), filenames(in:)
  Location/
    LocationProvider.swift    one-shot CL fix + reverse geocode
  Settings/
    KeychainStore.swift       (unused after OAuth move; kept for future)
    SettingsStore.swift       client ID + folder ID (UserDefaults)
  Models/
    LocalRecording.swift      model + sidecar-backed store
  Views/
    RecordView.swift          mic UI; on stop, writes sidecar
    RecordingsListView.swift  local list + Upload button + diff logic
    SettingsView.swift        paste client ID + folder ID
    WaveformView.swift        static waveform from sample array
  Info.plist                  background audio + mic/location strings
```

## Key technical bits

- **OAuth PKCE:** verifier is 64 random URL-safe chars; challenge = base64url(SHA256(verifier)). `access_type=online` skips refresh token issuance; `prompt=select_account` forces account chooser.
- **Redirect URI:** `<reversedClientID>:/oauthredirect` where reversed = `com.googleusercontent.apps.<id-prefix>`. ASWebAuthenticationSession intercepts via `callbackURLScheme`, so no Info.plist URL-scheme registration needed.
- **Drive diff:** for each month folder, list filenames in that subfolder once, then skip any local recording whose filename is already there. Folders are auto-created via `ensureFolder` (q for matching folder; create if absent).
- **Upload:** `POST /upload/drive/v3/files?uploadType=multipart` with `createdTime` in metadata and `appProperties.durationSec` for quick listing later.

## Out of scope

- Apple Watch companion.
- Background upload (NSURLSessionConfiguration.background).
- Editing / trimming.
- Audio playback (per requirements).
- Persistent OAuth refresh tokens (explicitly excluded per current design).
