# SIH26191 Backend Status & Roadmap (Slices 1 & 2)

## Implemented and Tested (Slices 1, 2, & 3)

### SLICE 1: History, Hazard Intensity, Multi-Hazard, Risk Upgrade
- **Disaster History API**: `DisasterHistory` model added. Tracks event intensity, date, affected population, etc. GET `/api/history` and `/api/history/summary` exposed with derived indicators (frequency, recency, repeated exposure).
- **Hazard Intensity**: Exposed explicitly during risk aggregation based on dataset input (`critical` vs `low`).
- **Multi-Hazard Breakdown**: The risk service calculates explicit exposure per hazard, instead of opaque sums.
- **Risk Engine Upgrade**: `calculate_habitation_risk` now multiplies aggregated multi-hazard risks with historical context and vulnerability multipliers.

### SLICE 2: Vulnerability, Red Zone, Dynamic Recalculation
- **Vulnerability Deepening**: Expanded Habitation schema with dependent populations, infrastructure scores, and healthcare accessibility. `calculate_vulnerability` computes multi-dimensional scores on 0-100 scale.
- **Red Zone Engine**: Explicit evaluation into `GREEN`, `WATCH`, `HIGH_RISK`, `MODEL_ASSESSED_RED_ZONE` based on critical risk combined with extreme vulnerability (vulnerability > 50).
- **Dynamic Recalculation**: Replaced manual chaining with `trigger_full_recalculation(db, dataset_id)` orchestrating a deterministic dependency graph: Vulnerability -> Risk -> Red Zones -> Relocation.

### SLICE 3: Site Suitability, Carrying Capacity Math, Relocation Priorities
- **Site Suitability**: Relocation logic deeply evaluates candidate sites not just for distance and physical capacity, but for missing infrastructure (no road access), hazard exposure of the destination site, electricity, water capacity, and services (schools, hospitals). Outputs exact rejection reasons like `INSUFFICIENT_DISTANCE`, `INSUFFICIENT_CAPACITY`, or `HAZARD_EXPOSURE`.
- **Carrying Capacity**: Transformed `calculate_capacity` into a constrained resource calculator factoring physical bounds, water constraints (liters/day/person), sanitation (toilets), and healthcare limits to find the absolute `bottleneck` resource that strictly caps the `effective_capacity`.
- **Relocation Priority**: Prioritizes source habitations into explicit `IMMEDIATE`, `SHORT_TERM`, `MEDIUM_TERM`, and `MONITOR` categorizations based on aggregated risk multipliers, vulnerability metrics, and extreme Red Zone presence.

### SLICE 4: Relocation Allocation & What-If Scenarios
- **Relocation Allocation Engine**: Built `allocation_service.py` to move beyond mere site recommendations into deterministic population assignment. Iterates through prioritized habitations and tracks a running tally of available capacity at relocation sites. Outputs `FEASIBLE`, `PARTIAL`, or `FAILED` allocation statuses with exact reasons based on remaining capacity.
- **What-If Scenario Evaluation**: Added `what_if_service.py` (`POST /api/scenarios/evaluate/{id}`). It creates a full immutable in-memory clone of a dataset (`is_scenario=True`), applies user-provided modifications (e.g. disabling a relocation site or injecting a synthetic hazard), reruns the entire orchestrated dependency chain, and outputs a strict diff highlighting which habitation allocations broke or shifted (`impacted_habitations`).

### SLICE 5: Data Quality Engine & Auditability
- **Data Quality Architecture**: Implemented `data_quality_service.py` to evaluate habitation completeness and dataset staleness. It strictly grades input quality across `VALID`, `STALE`, `INCOMPLETE`, and `LOW_CONFIDENCE`.
- **Quality Propagation**: The engine propagates these scores. If population is missing or hazard layers are older than 6 months, the underlying `RiskAssessment`, `VulnerabilityAssessment`, and `RedZoneAssessment` are explicitly tagged with `data_quality="STALE"` (or worse) alongside precise `data_quality_reasons`. This ensures analytical outputs never hide the unreliability of their inputs.

### SLICE 6: AI/ML Integration (AI-Assisted Analytics)
- **Generative Narrative Engine**: Built `ai_service.py` (`GET /api/ai/narrative/{id}`) to translate raw backend numbers into human-readable situation reports.
- **Strict Methodology Distinctions**: The engine explicitly separates AI text generation from the deterministic math. The API outputs clearly return `"methodology": "AI-ASSISTED"` alongside `"underlying_data": "DETERMINISTIC"` with a strict warning not to use the AI for raw metric generation, strictly fulfilling the requirement to preserve the deterministic decision engine.

## Status
All phases (Slices 1 through 6) of the Next-Level Engineering Phase for SIH26191 are fully implemented and tested.
