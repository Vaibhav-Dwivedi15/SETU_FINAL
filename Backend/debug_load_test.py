"""
Load test: 50 concurrent emergency packets POSTed to /ingest.

Run with: python debug_load_test.py
Server must already be running (uvicorn app.main:app --reload).
"""

import time
import uuid
import random
import statistics
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

BASE_URL = "http://127.0.0.1:8000"
TOTAL_PACKETS = 50

HOTSPOTS = [
    {"lat": 28.6139, "lon": 77.2090, "message": "fire spreading in the building"},
    {"lat": 19.0760, "lon": 72.8777, "message": "flooding fast, water rising"},
    {"lat": 12.9716, "lon": 77.5946, "message": "person trapped under rubble"},
]


def build_packet(index: int) -> dict:
    hotspot = random.choice(HOTSPOTS)
    run_id = uuid.uuid4().hex[:8]

    return {
        "packet_id": f"loadtest-{run_id}-{index}",
        "sender_id": f"loadtest-device-{run_id}-{index}",
        "type": "emergency",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "nonce": f"loadtest-nonce-{run_id}-{index}",
        "ttl": 5,
        "hop_count": random.randint(0, 3),
        "protocol_version": 1,
        "signature": f"loadtest-sig-{run_id}-{index}",
        "emergency_id": f"loadtest-e-{run_id}-{index}",
        "latitude": hotspot["lat"] + random.uniform(-0.0005, 0.0005),
        "longitude": hotspot["lon"] + random.uniform(-0.0005, 0.0005),
        "message": hotspot["message"],
        "priority": random.choice(["low", "medium", "high", "critical"]),
    }


def send_packet(packet: dict):
    start = time.perf_counter()
    try:
        response = requests.post(
            f"{BASE_URL}/ingest",
            json={"packets": [packet]},
            timeout=15,
        )
        elapsed = time.perf_counter() - start
        return {
            "packet_id": packet["packet_id"],
            "status_code": response.status_code,
            "elapsed": elapsed,
            "body": response.json() if response.status_code == 200 else response.text,
        }
    except requests.RequestException as exc:
        elapsed = time.perf_counter() - start
        return {
            "packet_id": packet["packet_id"],
            "status_code": None,
            "elapsed": elapsed,
            "body": str(exc),
        }


def main():
    packets = [build_packet(i) for i in range(TOTAL_PACKETS)]

    print(f"Firing {TOTAL_PACKETS} concurrent requests to {BASE_URL}/ingest ...")
    overall_start = time.perf_counter()

    results = []
    with ThreadPoolExecutor(max_workers=TOTAL_PACKETS) as executor:
        futures = [executor.submit(send_packet, p) for p in packets]
        for future in as_completed(futures):
            results.append(future.result())

    overall_elapsed = time.perf_counter() - overall_start

    successes = [r for r in results if r["status_code"] == 200]
    failures = [r for r in results if r["status_code"] != 200]
    latencies = [r["elapsed"] for r in results]

    print(f"\n--- Summary ---")
    print(f"Total wall-clock time: {overall_elapsed:.2f}s")
    print(f"Successes: {len(successes)}/{TOTAL_PACKETS}")
    print(f"Failures:  {len(failures)}/{TOTAL_PACKETS}")
    if latencies:
        print(f"Latency (s) -- min: {min(latencies):.3f}  max: {max(latencies):.3f}  "
              f"avg: {statistics.mean(latencies):.3f}  median: {statistics.median(latencies):.3f}")

    if failures:
        print("\n--- Failures (first 5) ---")
        for f in failures[:5]:
            print(f["packet_id"], f["status_code"], f["body"])

    accepted_count = sum(len(r["body"].get("accepted", [])) for r in successes)
    rejected_count = sum(len(r["body"].get("rejected", [])) for r in successes)

    incident_ids = set()
    for r in successes:
        for accepted in r["body"].get("accepted", []):
            if "incident_id" in accepted:
                incident_ids.add(accepted["incident_id"])

    print(f"\n--- Dedup sanity check ---")
    print(f"Packets accepted: {accepted_count}, rejected: {rejected_count}")
    print(f"Distinct incident_ids: {len(incident_ids)} (expected ~{len(HOTSPOTS)})")


if __name__ == "__main__":
    main()