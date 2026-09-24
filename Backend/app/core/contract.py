"""
Single source of truth for the time / size constants that the layers of
SETU must agree on (Block 2). Nothing here changes the mesh; it makes the
backend's side of the contract explicit and documents why the numbers differ.

WHY THREE DIFFERENT "WINDOWS" ARE CORRECT (they answer different questions):

PACKET_MAX_AGE_SECONDS (3600) -- "how old may a signed packet be when it
    reaches /ingest?"  The mesh's own 5-minute rule (MESH_CARRY_MAX_AGE_SECONDS,
    Dart SecurityConstants.maxPacketAge) is a *hop-to-hop replay/freshness* bound
    checked when a device RECEIVES a packet over Nearby. It is not applied to a
    device uploading its own (or already-accepted) queued packet, and the mesh
    design explicitly lets a device hold packets offline for hours and upload
    them when connectivity returns (LocalQueueService; docs/mesh/TTL.md
    "Persistence"). The backend therefore needs a longer bound than the mesh.
    Kept at the pre-existing 3600 s (unchanged behaviour): an SOS older than an
    hour is no longer actionable, and the signed timestamp cannot be forged, so
    this only bounds replay of captured packets.

PACKET_MAX_FUTURE_SKEW_SECONDS (30) -- mirrors Dart allowedClockSkew. A
    timestamp further in the future is rejected (it cannot be legitimate and
    would otherwise never age out of the replay window).

AI_DEDUP_WINDOW_SECONDS (300) -- how long the AI service keeps an incident
    "cluster" open for text/geo similarity matching (setu_ai_service
    config.TIME_WINDOW_SECONDS). It is about *report clustering*, measured in
    server receipt time, not packet age. Asserted equal to the AI config value
    by tests/test_contract_constants.py so the two cannot silently drift.

INCIDENT_DEDUP_WINDOW_SECONDS (900) -- backend DB fallback dedup window, used
    only when the AI service is unavailable (see deduplication_service).
"""

# --- Packet freshness -------------------------------------------------------
PACKET_MAX_AGE_SECONDS = 3600
PACKET_MAX_FUTURE_SKEW_SECONDS = 30
MESH_CARRY_MAX_AGE_SECONDS = 300  # documentation mirror of the Dart constant; not enforced here

# --- Packet shape -----------------------------------------------------------
# Mirrors Dart SecurityConstants.maxPacketSize (bytes of the serialized packet).
MAX_PACKET_BYTES = 4096
PACKET_TTL_MIN = 1  # Dart PacketValidator rejects ttl < 1 on receipt
PACKET_TTL_MAX = 5  # Dart MAX_TTL (unchanged)
INGEST_ACCEPTED_TYPES = ("emergency", "termination")

# --- Dedup ------------------------------------------------------------------
AI_DEDUP_WINDOW_SECONDS = 300
AI_DEDUP_RADIUS_METERS = 500  # mirror of AI GEO_DEDUP_RADIUS_METERS (asserted by tests)
INCIDENT_DEDUP_WINDOW_SECONDS = 900
INCIDENT_DEDUP_RADIUS_METERS = 150

# --- Signed requests (registration, voice, nearby alerts) --------------------
SIGNED_REQUEST_WINDOW_SECONDS = 300
