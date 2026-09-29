# SIH26191 Backend Decision-Support Engineering Report

## Executive Summary
This document outlines the final end-to-end architecture for the SETU SIH26191 decision-support engine. The backend serves as a high-reliability, deterministic graph that computes disaster risk, evaluates candidate relocation sites based on constrained resources, and orchestrates allocations.

## Architecture & Data Flow
1. **Dataset / Ingestion**: Core geometries, population densities, and infrastructure are ingested via `/api/datasets`. 
2. **Data Quality Engine**: `data_quality_service.py` validates inputs. Stale hazard data (>180 days) or incomplete demographics generate `STALE` or `INCOMPLETE` metadata flags injected into all subsequent metrics.
3. **Multi-Hazard Exposure**: Ray-casting geospatial intersection against multiple overlapping hazards. Severity weights are applied multiplicatively based on historical exposure (`DisasterHistory`).
4. **Vulnerability Score**: A weighted calculation (0-100) factoring in demographics, dependencies, and infrastructure.
5. **Red Zone Assessment**: A strict combinatory matrix (`red_zone_service.py`). Critical Risk + Extreme Vulnerability = `MODEL_ASSESSED_RED_ZONE`. 
6. **Relocation Priority**: Algorithmic classification grouping habitations into `IMMEDIATE`, `SHORT_TERM`, `MEDIUM_TERM`, and `MONITOR` tiers.
7. **Safe Site Screening**: Evaluates sites for intrinsic hazard exposure and distances. Rejects sites explicitly (`suitable=False`) with detailed string reasons (`INSUFFICIENT_DISTANCE`, `HAZARD_EXPOSURE`) for legal/audit traceability.
8. **Site Capacity**: Evaluates bottleneck equations: `min(physical_area, water_lpd, sanitation, healthcare)`. 
9. **Allocation Engine**: Deterministic siphoning. High-priority habitations consume site capacity sequentially, yielding `FEASIBLE`, `PARTIAL`, or `FAILED` strategies.
10. **What-If Scenario Evaluation**: Deep dataset cloning enabling rapid modification (e.g. disabling a site via `SITE_INACCESSIBLE`) and generating diffs without polluting production data.
11. **Authority Decisions**: Formal records separating model recommendations from final governmental execution.

## Methodology & Versioning
All model thresholds and constraints are centralized in `backend/app/core/methodology_config.py`.
- **Methodology Version**: Currently `2.1.0`.
- **Transparency**: Every API assessment explicitly returns the `methodology_name` and `methodology_version` used during evaluation. 

## AI Boundary 
The backend strictly isolates generative AI from the deterministic decision matrix.
- `GET /api/ai/narrative/{id}` produces textual situation summaries.
- No AI is permitted to execute mathematical hazard combinations or alter Red Zone classifications.
- Outputs are statically badged as `AI-ASSISTED`.

## Security & Reliability
- 100% of endpoints pass robust `pytest` suites.
- End-to-end testing verified via `test_end_to_end_sih26191_pipeline`. 
- SQLite in-memory mocking guarantees deterministic, idempotent validation without environment state leak.
- Implemented global request bounding and safe string comparison algorithms.
