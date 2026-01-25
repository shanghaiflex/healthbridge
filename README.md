# Health Bridge (iOS 16+)

Private SwiftUI app to sync Apple Health data to a LAN-only server over Wi-Fi.

## Quick start (real iPhone)
1. Open `HealthBridge.xcodeproj` in Xcode 15+.
2. Set your Development Team in **Signing & Capabilities**.
3. Ensure **HealthKit** capability is enabled and **Background Modes** includes `Background fetch`.
4. Build & run on a physical iPhone (HealthKit data is limited in the simulator).
5. In the app Settings, set `Server URL` and `API Key` (default is `http://192.168.1.149:8080`).
6. Tap **Sync now**.

## Capabilities / Entitlements
- HealthKit
- HealthKit background delivery (`com.apple.developer.healthkit.background-delivery`)

## Info.plist keys
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` (reserved for v2 discovery)
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking`

## Server endpoints
- `POST /v1/ingest/health/workouts`
- `POST /v1/ingest/health/sleep`
- `POST /v1/ingest/health/metrics`
- `GET  /healthz`

## Example JSON payloads
### Workouts
```json
{
  "items": [
    {
      "id": "E2C4C4E9-6C64-4A6C-A01E-5C9502AE87F0",
      "workoutType": "running",
      "start": "2024-01-20T07:15:00Z",
      "end": "2024-01-20T07:45:00Z",
      "durationMinutes": 30,
      "distanceMeters": 4200,
      "calories": 320,
      "averageHeartRate": 142
    }
  ],
  "deleted": [
    {
      "id": "1D3F0CB2-9D88-4B49-92B0-5C2B62A1F7EF",
      "sampleType": "workout"
    }
  ]
}
```

### Sleep
```json
{
  "items": [
    {
      "id": "F1AE2AA2-90F3-44A1-8AFA-4EC5B0ED4A90",
      "start": "2024-01-19T21:30:00Z",
      "end": "2024-01-20T05:30:00Z",
      "totalMinutes": 480,
      "breakdown": {
        "remMinutes": 90,
        "deepMinutes": 80,
        "coreMinutes": 270,
        "awakeMinutes": 40
      }
    }
  ],
  "deleted": [
    {
      "id": "2AD3E7C6-8F47-4B5D-9D4F-9EF7F0E9C580",
      "sampleType": "sleep"
    }
  ]
}
```

### Metrics
```json
{
  "items": [
    {
      "id": "7A4BB6F7-83F4-41B2-9F39-F5FE0ED6C6F2",
      "kind": "hrv_sdnn",
      "start": "2024-01-20T06:30:00Z",
      "end": "2024-01-20T06:35:00Z",
      "value": 52,
      "unit": "ms"
    },
    {
      "id": "0C4F25B7-0E16-4B7A-A8F5-23B1A1F4D412",
      "kind": "resting_heart_rate",
      "start": "2024-01-20T06:00:00Z",
      "end": "2024-01-20T06:05:00Z",
      "value": 58,
      "unit": "count/min"
    }
  ],
  "deleted": [
    {
      "id": "2D9F2CC9-ED7C-4451-9E52-0A713CE3D22D",
      "sampleType": "resting_heart_rate"
    }
  ]
}
```

## Notes
- The queue stores JSON batches on disk and retries with exponential backoff.
- Each payload includes the HealthKit UUID (`id`) for server-side de-duplication.
- Enable **Dev mode** in Settings to reveal **Import sample JSON** for the offline pipeline test.
