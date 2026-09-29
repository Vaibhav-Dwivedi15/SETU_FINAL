# SIH26191 FINAL ENGINEERING & DECISION-SUPPORT PIPELINE

## 1. Overview
This document explains the complete SETU decision-support pipeline, elevating it from an analytical foundation to an engineering-grade system.

## 2. Architecture & Data Flow
```
[Dataset Ingestion] --> [Data Quality Assessment] --> [Multi-Hazard Exposure] 
                                                               |
                                                               v
[Disaster History] --> [Vulnerability Scoring] ----> [Risk Assessment]
                                                               |
                                                               v
                                                  [Red Zone Classification]
                                                               |
                                                               v
                                                 [Relocation Priority]
                                                               |
                                                               v
[Relocation Sites / Capacity Constraints] ---------> [Allocation Engine]
                                                               |
                                                               v
[What-If Scenarios / Field Observations] ----------> [Recalculation / Updated Decision]
                                                               |
                                                               v
                                                   [Authority Decision Lifecycle]
```

## 3. Service Responsibilities
* `gis_service.py`: Spatial querying, bounding box, and GeoJSON intersections.
* `data_quality_service.py`: Detects missing, stale, or conflicting inputs. Assigns confidence (VALID, STALE, INCOMPLETE, LOW_CONFIDENCE).
* `risk_service.py`: Fuses multi-hazard exposure, historical data, and vulnerability multipliers into a unified risk score.
* `vulnerability_service.py`: Calculates habitation vulnerability based on population, infrastructure, and healthcare access.
* `red_zone_service.py`: Classifies habitations into semantic zones (e.g., MODEL_ASSESSED_RED_ZONE) based on deterministic thresholds.
* `relocation_service.py`: Evaluates candidate sites against safe zones, distance constraints, and facility availability.
* `capacity_service.py`: Computes maximum people a site can support based on usable area, water, and sanitation metrics.
* `allocation_service.py`: Deterministically assigns priority habitations to constrained sites with clear reasons for partial/failed allocations.
* `what_if_service.py`: Forks immutable datasets for scenario simulation (e.g., disabling sites) to compute allocation diffs.
* `recalculation_service.py`: Orchestrates the sequential deterministic recalculation of all derived assessments.
* `field_ops_service.py`: Ingests emergency mesh field observations and records authority decisions, triggering recalculations.

## 4. Methodology & Versioning
Methodology is centralized in `app/core/methodology_config.py` (e.g., "SETU SIH26191 Risk Methodology v2.1.0"). All analytical results stamp the version to ensure reproducibility.
* **Risk Thresholds**: Critical >= 15.0, High >= 8.0, Medium >= 4.0.
* **Red Zone Semantics**: To be classified as `MODEL_ASSESSED_RED_ZONE`, a habitation must have Critical risk AND Extreme vulnerability (>=50.0). This is a SETU analytical classification, NOT an official government declaration.

## 5. Scoring Explanation
* **Risk Score**: `Sum(hazard_weights) + Sum(history_weights * 0.5) * Vulnerability Multiplier`.
* **Vulnerability Score**: Aggregation of population size, dependents, lack of healthcare/roads, and bad infrastructure (0-100 scale).

## 6. Capacity Formula
Site capacity is the minimum of multiple infrastructural bottlenecks (if provided) or area assumptions:
* Area: `(Usable Area * 0.6) / 4.0 sq.m per person`
* Medical, Water, Sanitation bottlenecks restrict capacity further if defined.

## 7. Relocation & Allocation Logic
* **Relocation Logic**: Candidate sites must not overlap with critical hazard zones, must be within `MAX_RELOCATION_RADIUS_KM` (50km), and must have non-zero remaining capacity.
* **Allocation Logic**: Constraint-based deterministic engine. It orders habitations by highest priority score descending (and habitation ID ascending for deterministic tie-breaking). It fills highest-priority site recommendations first, generating `FEASIBLE`, `PARTIAL`, or `FAILED` allocation statuses with traceable reasons.

## 8. Data Quality Interpretation
Data quality impacts confidence but does not secretly distort the deterministic risk score unless explicitly defined by the methodology. The API returns the analytical result + confidence label + reasons (e.g., "Hazard layer data is older than 180 days (stale)").

## 9. AI Boundary
The engine is strictly **deterministic**.
AI is restricted to summarizing and generating situation-report narratives based *only* on the deterministic structural metrics. The AI surfaces insights but cannot invent hazard data, compute risk scores, or override priority logic.

## 10. Scenario Logic & Field Observations
* **What-If Scenario**: Creates a temporary clone of the base dataset, applies user modifications (e.g., disable site, add hazard), triggers full recalculation, and compares the new allocation against the baseline.
* **Field Observation**: Field inputs (e.g., road blocked) map to backend concepts (like site inaccessibility), triggering recalculation of site eligibility and relocation priorities.

## 11. Authority Decision Lifecycle
Recommendations are strictly advisory. The `AuthorityDecision` model tracks the transition of recommendations to official statuses: `PROPOSED`, `ACCEPTED`, `MODIFIED`, `REJECTED`, or `EXECUTED` along with the actor and rationale.

## 12. Demo Dataset Explanation
A cohesive Prayagraj synthetic scenario. It seeds 25 habitations and multiple relocation sites with contrasting hazard layers to demonstrate End-to-End decision support (some habitations become red zones, some fail allocation, etc.). It is explicitly labeled as DEMO data.

## 13. Known Limitations
* PostGIS is not yet introduced to maintain a simplified local database constraint for the SIH demo. Bounding box filters + exact point-in-polygon checks are used instead.
* True offline Android mesh syncing is represented via simulated `/api/field/observations` endpoints in this API iteration.
