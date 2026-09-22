"""
SETU AI - Performance & Latency Benchmark Runner
Establishes execution latency baseline across a realistic batch of emergency packets.
"""

import time
from models.pipeline import process_message

TEST_SCENARIOS = [
    ("Strong earthquake destroyed hospital building, 6 people trapped", 25.4358, 81.8463),
    ("Severe flood water rising fast in residential area need drinking water", 25.4360, 81.8465),
    ("Gas cylinder fire in market near electrical transformer", 25.4350, 81.8450),
    ("Missing 8 years old boy named Rohan last seen near bus stand", 25.4340, 81.8440),
    ("Main highway and bridge blocked by fallen trees", 25.4330, 81.8430),
]


def run_benchmark(iterations: int = 100):
    latencies = []
    failures = 0

    print(f"Running SETU AI pipeline benchmark ({iterations} packets)...")
    start_total = time.perf_counter()

    for i in range(iterations):
        msg, lat, lon = TEST_SCENARIOS[i % len(TEST_SCENARIOS)]
        t0 = time.perf_counter()
        try:
            res = process_message(
                message=msg,
                relay_count=1,
                age_seconds=10,
                emergency_id=f"bench-{i}",
                latitude=lat,
                longitude=lon,
            )
            latencies.append((time.perf_counter() - t0) * 1000)  # ms
        except Exception:
            failures += 1

    total_time = time.perf_counter() - start_total
    avg_latency = sum(latencies) / len(latencies) if latencies else 0
    max_latency = max(latencies) if latencies else 0
    throughput = len(latencies) / total_time if total_time > 0 else 0

    print("\n--- Benchmark Results ---")
    print(f"Total Processed: {len(latencies)} packets")
    print(f"Average Latency: {avg_latency:.3f} ms")
    print(f"Maximum Latency: {max_latency:.3f} ms")
    print(f"Throughput     : {throughput:.1f} packets/sec")
    print(f"Failures       : {failures}")


if __name__ == "__main__":
    run_benchmark(100)
