# SETU — Complete Project Summary

> **Purpose of this document:** A thorough, AI-readable summary of the entire SETU project — what it is, how every sub-system works, how the pieces talk to each other, and what still needs doing. Written so a new AI (or human engineer) can onboard with zero prior context.

---

## 1. What SETU Is

**SETU** (सेतु, meaning "bridge" in Hindi) is a **disaster-response communication system** designed for situations where the internet and mobile networks are down — floods, earthquakes, mass-casualty events.

It has **three interlocking parts**:

| Component | Tech | Role |
|-----------|------|------|
| `setu_app` | Flutter (Dart) | Citizen & responder mobile app — sends SOS alerts via a device-to-device mesh |
| `setu_dashboard` | React + Vite | Control-room web dashboard — real-time monitoring for verified responders & operators |
| Backend (not in this repo) | Python / FastAPI (Ayush's repo) | Receives mesh packets from the internet-connected edge of the mesh, runs AI triage, exposes a REST API |

The core innovation: **incident alerts travel phone-to-phone over BLE (Bluetooth Low Energy) and Wi-Fi Direct**, without any internet connection, until they reach a device that has connectivity and can upload to the backend.

---

## 2. Repository Layout

```
SETU_FINAL-main/
├── setu_app/           # Flutter mobile app
│   ├── lib/
│   │   ├── features/       # Feature modules (SOS, relay, history, recovery, …)
│   │   ├── mesh/           # Core mesh networking layer (packets, signing, relay)
│   │   ├── security/       # Packet validation, replay protection, nonce cache
│   │   ├── services/       # BackendService, PowerModeController, BatteryService, …
│   │   ├── core/           # Design system, theme, language, shared widgets
│   │   └── screens/        # Top-level screens
│   ├── test/               # Dart unit tests (mesh, security, signing, packets)
│   └── pubspec.yaml
│
├── setu_dashboard/     # React web dashboard
│   ├── src/
│   │   ├── App.jsx             # Root component — routing, polling, global state
│   │   ├── components/         # UI components
│   │   │   ├── pages/          # Full-page views (Dashboard, Map, Incidents, Analytics, …)
│   │   │   └── ui/             # Primitive design-system atoms
│   │   ├── context/            # ThemeContext, LanguageContext
│   │   ├── data/               # Mock/fallback data (incidents, resources, teams)
│   │   ├── services/api.js     # Backend integration layer (polling, normalization)
│   │   └── utils/              # alertSound, exportCsv, i18n, timeAgo, useFocusTrap, …
│   ├── HANDOFF_TEAM_LEAD.md    # Decision memo for team lead (Vaibhav)
│   ├── HANDOFF_AYUSH_BACKEND.md # API contract for backend engineer (Ayush)
│   └── package.json
│
└── summarize.md        # This file
```

---

## 3. The Mesh Network — How Packets Flow

### 3.1 Packet Types

All mesh messages are subclasses of `MeshPacket` (Dart). Every packet carries:

| Field | Purpose |
|-------|---------|
| `packetId` | UUID — unique per transmission |
| `senderId` | Hex-encoded Ed25519 **public key** — also the device's identity |
| `timestamp` | ISO 8601 — used for replay protection (5-minute window) |
| `nonce` | Random UUID — prevents identical replays within the time window |
| `ttl` | Time-to-live; decremented on each relay hop |
| `hopCount` | Incremented on each relay hop; surfaced in the dashboard map popup |
| `signature` | Ed25519 signature over a canonical `signaturePayload` string |
| `type` | Enum: `emergency`, `ack`, `alert`, `termination` |

Concrete packet types:

- **`EmergencyPacket`** — the main SOS payload: `emergencyId`, `latitude`, `longitude`, `message`, `priority` (low/medium/high/critical).
- **`AckPacket`** — acknowledgment sent back through the mesh once an EmergencyPacket successfully reaches the backend. Contains `originalPacketId` + `emergencyId`.
- **`AlertPacket`** — broadcast alert from an operator (e.g., "Avoid Area X"). Relayed but not uploaded.
- **`TerminationPacket`** — sent by a **verified responder** to close an incident on the mesh. Ed25519-signed; `ResponderRegistry` checks sender's public key.

### 3.2 Cryptographic Identity — `SigningService`

File: [`setu_app/lib/mesh/services/signing_service.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/mesh/services/signing_service.dart)

- Each device generates an **Ed25519 keypair** on first launch.
- The **private key seed** is stored in Android Keystore-backed `FlutterSecureStorage`.
- The **public key hex** is the device's `senderId` — self-certifying: no certificate authority needed.
- Every outgoing packet is signed. Incoming packets are verified against the sender's public key embedded in the packet itself.
- Signature verification proves **integrity + origin** from that key. Whether that key belongs to an *authorized responder* is a separate registry check (see §3.4).

### 3.3 `MeshService` — The Core Relay Engine

File: [`setu_app/lib/mesh/services/mesh_service.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/mesh/services/mesh_service.dart)

Responsibilities on **incoming packets** (via `NearbyService`):

1. Deserialize JSON → `PacketFactory.fromJson()`
2. **Security validation** (`PacketValidator`): protocol version, TTL ≥ minimum, timestamp within 5 min window, nonce not seen before (nonce cache).
3. **Signature verification** (`SigningService.verify()`).
4. If `TerminationPacket`: check `ResponderRegistry`; mark `emergencyId` as closed.
5. If `EmergencyPacket` for a closed emergency: drop silently.
6. Accept, enqueue in `LocalQueueService`, emit on `incomingPackets` stream.
7. **Relay** (decrement TTL, increment hopCount, re-broadcast via `NearbyService`) — skipped if power saver mode or TTL exhausted.
8. **Upload** to backend (`BackendService.uploadPacket`) — skipped if no internet or power saver mode.
9. If upload succeeds: originate an `AckPacket` back through the mesh.

Responsibilities on **outgoing packets** (`originate()`):

1. If `EmergencyPacket`, track its `emergencyId` (for ack matching later).
2. Enqueue in `LocalQueueService`.
3. Serialize + hand to `NearbyService.originate()`.
4. Record in `RelayLogRepository`.
5. Attempt backend upload.

**Periodic timers:**
- Every 30 s: retry any pending (not yet uploaded) queue items.
- Every 5 min: sync `ResponderRegistry` from backend (`GET /responders/keys`).

### 3.4 Power-Aware Mesh Policy

File: [`setu_app/lib/mesh/services/mesh_policy.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/mesh/services/mesh_policy.dart)

`PowerModeController` watches battery level and mode. The active `MeshPolicy` controls:
- `scanInterval` / `discoveryInterval` (BLE/Wi-Fi scanning aggressiveness)
- `allowRelay` — whether this device forwards packets for others
- `allowUpload` — whether uploads are attempted

In battery saver mode: relay and upload are disabled to conserve power.

### 3.5 Replay Protection

Files: [`security/nonce_cache.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/security/nonce_cache.dart), [`security/timestamp_validator.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/security/timestamp_validator.dart), [`security/packet_validator.dart`](file:///C:/Work/Projects/SETU_FINAL-main/setu_app/lib/security/packet_validator.dart)

- **Timestamp gate**: reject packets older than 5 minutes or more than 30 s in the future.
- **Nonce cache**: store seen nonces in-memory (bounded); reject duplicates.
- **`PacketValidator`** combines both: throws `SecurityException` on failure; `MeshService` drops the packet.

---

## 4. Flutter App Features

### Feature Modules (`setu_app/lib/features/`)

| Module | What it does |
|--------|-------------|
| `sos` | SOS button flow: hold-to-confirm, countdown, sends `EmergencyPacket` via mesh. Supports voice SOS (microphone). Multiple alert modes. |
| `relay` | Relay log — persistent history of packets this device has sent/received/relayed/uploaded. UI: `RelayLogScreen`, `RelayStatusScreen`. |
| `history` | Local history of incidents this device has been part of. |
| `nearby` | Community alerts — shows nearby mesh alerts to the user. |
| `recovery` | Post-disaster recovery reporting — field damage reports, missing persons. Sends `RecoveryPacket` through mesh. |
| `preparedness` | Safety guides, readiness checks — educational content for disaster preparedness. |
| `lost_child` | Broadcast lost-child alerts through the mesh. |
| `settings` | App settings (language, theme, profile, power mode). |
| `stealth` | Stealth SOS mode — silent alert (no visible feedback). |
| `voice_sos` | Voice-triggered SOS. |
| `onboarding` | Permission gate screen — requests BLE, location, storage permissions. |
| `profile` | Complete profile screen — name, age, medical history, emergency contacts → `BackendService.registerProfile()`. |
| `sms` | SMS fallback for sending alerts when mesh is unavailable. |
| `language` | Language selection screen. |
| `location` | GPS location service + test screen. |
| `home` | App home screen with feature navigation grid. |

### Core Services

| Service | Purpose |
|---------|---------|
| `BackendService` | HTTP client: `POST /ingest` (packet upload), `GET /responders/keys`, `POST /register`. Base URL: `https://setu-backend-cy78.onrender.com`. |
| `NearbyService` | Abstraction over the BLE/Wi-Fi Direct native layer (Google Nearby Connections or equivalent). |
| `LocalQueueService` | SQLite-backed queue of packets awaiting upload. Survives app restarts. |
| `PowerModeController` | Monitors battery; emits `PowerMode` stream. |
| `VoiceSosService` | Records audio, transcribes locally or sends as attachment. |
| `VolumeSosService` | Hardware volume-button–triggered SOS. |
| `ProfileSyncService` | Syncs user profile to backend when connectivity returns. |
| `EmailOtpService` | OTP-based email verification for responder registration. |
| `ConnectivityMeshController` | Watches network state; triggers mesh/upload mode switches. |

### Key Dependencies (`pubspec.yaml`)

```yaml
cryptography: ^2.9.0          # Ed25519 signing/verification
flutter_secure_storage: ^10.3.1 # Android Keystore-backed key storage
geolocator: ^14.0.3           # GPS
http: ^1.6.0                  # Backend HTTP calls
sqflite: ^2.4.3               # Local packet queue (SQLite)
connectivity_plus: ^6.1.3     # Network state monitoring
battery_plus: ^7.1.1          # Battery level for power-aware relay
go_router: ^14.6.1            # Navigation
record: ^7.1.1                # Audio recording (voice SOS)
permission_handler: ^11.3.0   # Runtime permissions
```

---

## 5. The Dashboard (`setu_dashboard`)

### 5.1 Technology Stack

- **React 19** + **Vite 8**
- **Leaflet / React-Leaflet** — live incident map
- **Recharts** — analytics charts
- No Redux — state lives in `App.jsx` and is passed down as props.

### 5.2 Architecture — `App.jsx`

[`src/App.jsx`](file:///C:/Work/Projects/SETU_FINAL-main/setu_dashboard/src/App.jsx) is the single top-level stateful component. It owns:

- **Active page** routing (no React Router — `activePage` string state, pages rendered conditionally).
- **Incident state** — starts from mock data (`src/data/incidents.js`), replaced by live backend data when connected.
- **Backend polling** via `startIncidentPolling()` — polls `GET /incidents` every N seconds (default 5 s, user-configurable). Falls back to mock data automatically on error.
- **New incident detection** — compares `knownIdsRef` (Set of seen IDs) against each poll result. New incidents trigger:
  - Toast notification (if `notificationsEnabled`)
  - Persistent notification in `NotificationCenter`
  - Audio alert (`playAlertSound`) scaled to severity (if `soundEnabled`)
  - Blocking `CriticalAlertModal` for Critical-priority incidents (not suppressible by quiet mode)
- **Merge view** — `mergeByCluster()` deduplicates incidents by `clusterKey` from the backend's AI dedup output. No-op against live backend (already deduplicated server-side); useful against mock data.
- **Settings persistence** — JSON-serialized to `localStorage`.
- **Global keyboard shortcuts**: `Ctrl/Cmd+K` → Command Palette; `/` → focus search input.

### 5.3 Pages

| Page | Route key | What it shows |
|------|-----------|---------------|
| `DashboardHome` | `dashboard` | Split-pane: geospatial map (67%) + tactical feed (33%) with Live/Critical/AI Triage tabs. Expandable resource + analytics tray below. |
| `LiveMapPage` | `map` | Full-screen Leaflet map of all plotted incidents. Click to open detail drawer. |
| `IncidentsPage` | `incidents` | Table/list of all incidents with sort, filter, resolve. |
| `CategoriesPage` | `categories` | Incidents grouped by emergency category. |
| `AnalyticsPage` | `analytics` | Recharts-powered trend charts, breakdowns by type/priority/city. |
| `ResourcesPage` | `resources` | Emergency response asset status (ambulances, fire trucks, etc.). Sample data — not live. |
| `TeamsPage` | `teams` | List of registered responder teams from `GET /responders`. Falls back to sample data if backend unreachable. |
| `RecoveryPage` | `recovery` | After-disaster: field damage reports, missing persons registry. |
| `SettingsPage` | `settings` | Poll interval, notifications toggle, sound toggle. Backend connection status. |

### 5.4 Components

| Component | Purpose |
|-----------|---------|
| `Sidebar` | Navigation rail with live incident count badge, backend status pill |
| `MapView` | Leaflet map — color-coded markers by priority, popup shows type/priority/city/hop count |
| `IncidentList` | Virtualized incident cards with priority badge, time-ago, resolve button |
| `IncidentDetailDrawer` | Side drawer with full incident detail: AI vs sender priority, relay trace, community responses, government notifications, audit history |
| `AIPanel` | Live statistical summary of current incidents — explicitly NOT a predictive ML model |
| `CriticalAlertModal` | Blocking full-screen modal for Critical-priority arrivals |
| `NewAlertModal` | Form to manually create an incident (type, city, priority, message) |
| `CommandPalette` | Spotlight-style search (Ctrl+K): search incidents, navigate pages, open new alert |
| `NotificationCenter` | Bell icon with unread count; dropdown of all recent incident alerts; mark-all-read / clear |
| `ToastStack` | Bottom-right toast queue (auto-dismiss after 6 s) |
| `RelayTrace` | Visualizes the hop path of a mesh packet for a given incident |
| `AnalyticsChart` | Recharts bar/line charts |
| `StatsCards` | KPI summary cards |
| `LanguageSelector` | UI language switcher |
| `ThemeToggle` | Light/dark mode toggle |
| `DeliveryStatusPanel` | Shows government notification delivery status |
| `CommunityResponsePanel` | Shows community responders who responded to an incident via the app |
| `GovernmentNotificationPanel` | Shows government agency notifications triggered by this incident |
| `IncidentTimeline` | Timeline of audit log events for an incident |
| `ResourcePanel` | Response asset readiness mini-panel |

### 5.5 API Layer — `src/services/api.js`

File: [`src/services/api.js`](file:///C:/Work/Projects/SETU_FINAL-main/setu_dashboard/src/services/api.js)

All backend calls use:
- `VITE_BACKEND_URL` env var (default: `http://localhost:8000`)
- `VITE_API_KEY` env var → `X-API-Key` header

**Endpoints called:**

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/incidents` | Main polling endpoint. Returns `IncidentOut[]` |
| `GET` | `/responders` | Teams page. Returns `{id, public_key, name, organization}[]` |
| `GET` | `/incidents/{id}/responses` | Community responses for an incident |
| `GET` | `/incidents/{id}/history` | Audit log trail (CREATED/MERGED/CLOSED) |
| `GET` | `/incidents/{id}/government-notifications` | Gov agency notification log |
| `GET` | `/government/adapter-status` | Which gov adapter is active, whether it's mock |
| `POST` | `/incidents/{id}/resolve` | Mark incident resolved from dashboard (admin path) |

**Field normalization (`normalizeIncident`)** — critical to understand:

The backend `IncidentOut` schema differs from what the mock data uses:

| Backend field | Dashboard field | Notes |
|--------------|-----------------|-------|
| `id` | `id` | Direct |
| `incident_type` | `type` | Prettified for display |
| `ai_incident_type` | `aiIncidentType` | AI-classified type |
| `sender_priority` (string: low/medium/high/critical) | `senderPriority` | What the reporter declared |
| `ai_priority` (float: 1.0–5.0) | `aiPriority` | AI triage assessment |
| — | `priority` (display) | Prefers `aiPriority`, falls back to `senderPriority`, then "Medium" |
| `created_at` | `reportedAt` | Backend has no `timestamp` field |
| `latitude`, `longitude` | `lat`, `lng` | No `city` field — derived client-side via Haversine from known cities |
| `status` ("OPEN"/"CLOSED") | `status` ("active"/"closed") | Vocabulary normalization |
| `hop_count` | `hopCount` | Mesh relay hop count |
| `matched_cluster_id` | `clusterKey` | Falls back to `id` |

**City derivation:** Backend has no reverse-geocoding. The dashboard matches coordinates to 7 known Uttar Pradesh cities (Prayagraj, Lucknow, Varanasi, Kanpur, Agra, Delhi, Noida) within an 80 km radius using the Haversine formula. Incidents further than 80 km show coordinates.

### 5.6 Contexts

- **`ThemeContext`** — light/dark mode, persisted to `localStorage`.
- **`LanguageContext`** — UI language (Hindi/English and others), drives `src/utils/i18n.js`.

### 5.7 Utilities

| Utility | Purpose |
|---------|---------|
| `alertSound.js` | Web Audio API — generates a beep pitched by incident priority (Critical = high-frequency alarm, Low = gentle ping) |
| `exportCsv.js` | Downloads current incident list as CSV |
| `i18n.js` | Translation dictionary + `t()` function |
| `incidentCategories.js` | Maps incident type strings to category groupings |
| `timeAgo.js` | "2 min ago", "3h ago" human-readable relative time |
| `useFocusTrap.js` | Accessibility: traps keyboard focus inside modals |
| `useTick.js` | Ticking clock hook for live time-ago updates |

---

## 6. Backend API Contract (What this Repo Expects)

> The backend lives in Ayush's separate repository. This section documents what SETU expects from it.

### 6.1 Backend URL

`https://setu-backend-cy78.onrender.com` (Render free tier — sleeps after 15 min idle)

### 6.2 Authentication

- `X-API-Key` header for dashboard REST calls.
- No auth for `POST /ingest` from mobile (packet authenticity is established via Ed25519 signature).

### 6.3 `POST /ingest`

Receives mesh packets from mobile app when internet is available.

**Request body:**
```json
{ "packets": [ { ...packet fields... } ] }
```

Note: the `packets` array wrapper is required — bare packet objects were a source of 422 errors (fixed August 2026).

### 6.4 `GET /incidents` — `IncidentOut` schema

```json
{
  "id": 42,
  "incident_type": "MEDICAL",
  "ai_incident_type": "Medical Emergency",
  "ai_incident_confidence": 0.92,
  "ai_incident_explanation": "...",
  "sender_priority": "high",
  "ai_priority": 4.1,
  "ai_urgency": 0.88,
  "latitude": 25.4358,
  "longitude": 81.8463,
  "status": "OPEN",
  "created_at": "2026-09-29T10:00:00Z",
  "closed_at": null,
  "hop_count": 3,
  "relay_path": null,
  "matched_cluster_id": null
}
```

### 6.5 `POST /incidents/{id}/resolve` — **Not yet implemented on backend**

The dashboard sends this when an operator marks an incident resolved. The backend currently only closes incidents via a signed `TerminationPacket` through `/ingest`. A browser cannot send a signed packet (no device private key in browser).

**Recommended implementation:**
```python
@router.post("/incidents/{incident_id}/resolve")
def resolve_incident(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),
):
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")
    incident.status = "closed"
    db.commit()
    # audit_service.record_audit_event(..., action="resolve_incident_via_dashboard")
    return {"status": "closed", "incident_id": incident_id}
```

Until this exists, the resolve button updates the UI optimistically and fails silently.

### 6.6 CORS

Dashboard origin (`http://localhost:5173` for dev, deployed URL for prod) must be in `CORS_ALLOWED_ORIGINS_RAW` on the backend.

---

## 7. Data Flow — End to End

```
Citizen device (no internet)
    │
    │  EmergencyPacket (Ed25519 signed)
    │  BLE / Wi-Fi Direct
    ↓
Relay phone 1 (no internet)
    │  validates signature, decrements TTL, relays
    ↓
Relay phone 2 (HAS internet)
    │  validates, uploads to backend:
    │  POST /ingest { "packets": [EmergencyPacket.toJson()] }
    │  On success → originates AckPacket back through mesh
    ↓
Backend (FastAPI)
    │  Validates Ed25519 signature
    │  Runs AI triage (incident_type, priority 1.0-5.0)
    │  Deduplicates via cluster matching
    │  Stores as Incident row
    │  Triggers government notification adapter
    ↓
Dashboard (React)
    │  Polling GET /incidents every 5 s
    │  normalizeIncident() adapts fields
    │  New incidents → toast + notification + sound + CriticalAlertModal
    ↓
Operator clicks "Resolve"
    │  Optimistic UI update (immediate)
    │  POST /incidents/{id}/resolve (async, fails silently if endpoint missing)
    OR
Responder on mesh device sends TerminationPacket (Ed25519 signed)
    │  Relayed through mesh
    │  Backend receives via /ingest, closes Incident
    │  Dashboard polls and sees status: "CLOSED"
```

---

## 8. Security Model

| Threat | Defense |
|--------|---------|
| Forged SOS packet | Ed25519 signature verified against sender's public key (embedded in packet) |
| Replay attack (same packet re-sent) | Nonce cache + 5-minute timestamp window |
| Unauthorized incident closure | TerminationPacket sender checked against `ResponderRegistry` (synced from backend) |
| Unauthorized dashboard access | `X-API-Key` header (RESPONDER_API_KEY / ADMIN_API_KEY on backend) |
| Dashboard spoofing resolution | `POST /incidents/{id}/resolve` is API-key gated (different trust model than Ed25519, intentionally — no private key in browser) |
| Old protocol packets | Protocol version field checked in `PacketValidator` |
| Excessive TTL | TTL enforced; minimum TTL constant prevents infinite relay loops |

---

## 9. What Is and Isn't Live Data

| Surface | Live? | Notes |
|---------|-------|-------|
| Incident map / feed | ✅ Live (when backend connected) | Falls back to mock data if backend unreachable |
| Community responses | ✅ Live | `GET /incidents/{id}/responses` |
| Government notifications | ✅ Live | `GET /incidents/{id}/government-notifications` |
| Incident history / audit log | ✅ Live | `GET /incidents/{id}/history` |
| Responder Teams | ✅ Live | `GET /responders`; falls back to sample data |
| Resources page | ❌ Sample data | No fleet-tracking backend integration |
| AI Panel | ❌ Live statistics only | Computed from current incident list; NOT a predictive ML model |
| Recovery page | ❌ Local / demo | Not yet wired to backend recovery endpoints |

---

## 10. Known Gaps & Open Decisions

1. **`POST /incidents/{id}/resolve` is missing from backend.** See §6.5. Decision needed: add REST admin endpoint (recommended for demo) or make resolve dashboard-only UI (optimistic, no backend effect).

2. **`nearby_service.dart`** — `NearbyService` is an abstract interface. The concrete implementation using Google Nearby Connections (or another BLE stack) is not present in this repo — it's expected to be a native plugin or a separate package.

3. **Resources page** is static sample data. Not connected to any live resource-tracking system.

4. **Recovery page on dashboard** uses local state only. No backend endpoint for recovery reports is wired.

5. **`setu_app/setu_app/`** — there is a nested `setu_app/setu_app/` directory containing some duplicated files (`app_router.dart`, `power_mode_controller.dart`). Likely a git artifact; the canonical source is `setu_app/lib/`.

---

## 11. Running the Dashboard

```bash
cd setu_dashboard
cp .env.example .env
# Edit .env:
#   VITE_BACKEND_URL=https://setu-backend-cy78.onrender.com
#   VITE_API_KEY=<your responder API key>

npm install
npm run dev          # → http://localhost:5173
npm run build        # Production build → dist/
```

**Sidebar status pills:**
- 🟢 "Live (Backend Connected)" — polling succeeded
- 🔴 "Offline (Mock Data)" — backend unreachable; dashboard uses `src/data/incidents.js`

If stuck on "Offline", check in this order:
1. Backend reachable at `VITE_BACKEND_URL`?
2. CORS origin configured on backend?
3. `VITE_API_KEY` matches `RESPONDER_API_KEY` on server?
4. `GET /incidents` returns a 2xx with a JSON array?

---

## 12. Running the Flutter App

```bash
cd setu_app
flutter pub get
flutter run          # Connect an Android device or emulator
```

Key permissions required (Android): Bluetooth, Location, Nearby Devices (for BLE/Wi-Fi Direct mesh), Microphone (for voice SOS).

---

## 13. Team & Responsibilities

| Person | Role |
|--------|------|
| **Vaibhav** | Team Lead — architecture decisions, integration sign-off |
| **Ayush** | Backend Lead — FastAPI server, AI triage, `/ingest`, government adapter |
| **Vanshika** | Dashboard — React frontend (primary author of `setu_dashboard`) |

---

## 14. Test Coverage

### Flutter (`setu_app/test/`)

| Test file | What it covers |
|-----------|---------------|
| `packet_test.dart` | Packet serialization / deserialization roundtrip |
| `packet_validator_test.dart` | TTL, version, timestamp, nonce validation |
| `signing_service_test.dart` | Ed25519 sign + verify |
| `nonce_cache_test.dart` | Nonce deduplication |
| `timestamp_validator_test.dart` | Timestamp window checks |
| `replay_protection_service_test.dart` | Combined replay protection |
| `priority_relay_queue_test.dart` | Priority queue ordering |
| `adaptive_ttl_test.dart` | TTL adaptation logic |
| `mesh_metrics_test.dart` | Metrics counters |
| `mesh_harness_test.dart` | End-to-end mesh harness simulation |
| `mesh_simulation.dart` | Multi-node mesh simulation |
| `cache_and_relay_test.dart` | Queue + relay integration |
| `email_otp_service_test.dart` | OTP generation / verification |

### Dashboard (`setu_dashboard`)

12 tests covering: navigation, theme toggle, command palette, `/` shortcut, modal validation, detail drawer, notifications, CSV export, Teams fallback messaging, honest-stats checks. Run with `npm test` (if test runner is configured).

---

## 15. Design System

The dashboard has a custom design system:

- **`src/design-system.css`** — design tokens (CSS custom properties): colors, spacing, typography, shadows. Supports light/dark themes via `[data-theme="dark"]`.
- **`src/icons.js`** — Lucide icon registry organized into `NavIcons`, `CategoryIcons`, `ActionIcons`, `MiscIcons`. All iconography uses this registry (no emoji in product UI).
- **`src/components/ui/Primitives.jsx`** — atomic UI components: `Badge`, `NetworkStatusPill`, `Pill`.
- Component-level CSS: `sidebar-v2.css`, `critical-alert-v2.css`, `pipeline-v2.css`, `map-v2.css`, `categories-v2.css`, `recovery-v2.css`.
- Page transitions via CSS animation on `section.content` with `key={activePage}` — respects `prefers-reduced-motion`.

---

*Last updated: September 2026. Generated from full source inspection of `SETU_FINAL-main`.*
