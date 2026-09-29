# SETU AYUSH Backend - GIS & Data Infrastructure API Handoff

This document details the GIS and Data Infrastructure API endpoints implemented for the SIH26191 requirements.

## Base URL
`/api`

## Authentication
Currently, the GIS endpoints are accessible without authentication for the dashboard to read them easily, though production may put them behind the standard API key middleware. Ingestion is recommended to be protected.

---

## 1. Datasets

### 1.1 List Datasets
`GET /api/datasets`
Returns a paginated list of datasets.
* **Response**: `PaginatedResponse` (data: `List[DatasetOut]`)

### 1.2 Create Dataset
`POST /api/datasets`
Creates a new dataset (e.g. for official or historical ingestion).
* **Body**: `DatasetCreate`
* **Response**: `DatasetOut`

### 1.3 Add Habitation to Dataset
`POST /api/datasets/{id}/habitations`
* **Body**: `HabitationCreate`
* **Response**: `HabitationOut`

### 1.4 Add Hazard Layer to Dataset
`POST /api/datasets/{id}/hazard-layers`
* **Body**: `HazardLayerCreate`
* **Response**: `HazardLayerOut`

### 1.5 Add Relocation Site to Dataset
`POST /api/datasets/{id}/relocation-sites`
* **Body**: `RelocationSiteCreate` (capacities are calculated server-side based on area and occupancy)
* **Response**: `RelocationSiteOut`

### 1.6 Seed Demo Data
`POST /api/datasets/seed-demo`
Triggers the demo dataset seeder script to populate deterministic demo data.

---

## 2. Risk

### 2.1 List Habitations
`GET /api/risk/habitations`
Returns habitations, optionally filtered by district.
* **Query Params**: `page`, `page_size`, `district`
* **Response**: `PaginatedResponse` (data: `List[HabitationOut]`)

### 2.2 Get Habitation Detail
`GET /api/risk/habitations/{id}`
* **Response**: `HabitationDetailOut`

### 2.3 List Hazard Zones
`GET /api/risk/zones`
* **Query Params**: `page`, `page_size`, `hazard_type`
* **Response**: `PaginatedResponse` (data: `List[HazardLayerOut]`)

### 2.4 List Layers (Alias)
`GET /api/risk/layers`
Returns hazard layers (same as `/zones`).

### 2.5 Risk Summary
`GET /api/risk/summary`
Returns aggregate counts of habitations, risk breakdowns, and hazard layers.

---

## 3. Vulnerability

### 3.1 List Vulnerability Assessments
`GET /api/vulnerability/habitations`
* **Query Params**: `page`, `page_size`
* **Response**: `PaginatedResponse` (data: `List[VulnerabilityAssessmentOut]`)

### 3.2 Get Habitation Vulnerability Detail
`GET /api/vulnerability/habitations/{id}`
* **Response**: `VulnerabilityAssessmentOut`

### 3.3 Vulnerability Summary
`GET /api/vulnerability/summary`
Returns total assessments and total exposed population.

---

## 4. Relocation & Capacity

### 4.1 List Relocation Sites
`GET /api/relocation/sites`
* **Query Params**: `page`, `page_size`, `district`, `min_capacity`
* **Response**: `PaginatedResponse` (data: `List[RelocationSiteOut]`)

### 4.2 Get Site Detail
`GET /api/relocation/sites/{id}`
* **Response**: `RelocationSiteOut`

### 4.3 Get Site Capacity Calculations
`GET /api/relocation/sites/{id}/capacity`
Exposes the server-side calculations and assumptions for a site's capacity.
* **Response**: 
```json
{
  "usable_area_sqm": 10000.0,
  "estimated_capacity": 2000,
  "current_occupancy": 500,
  "remaining_capacity": 1500,
  "assumptions": {
    "usable_area_ratio": 0.8,
    "area_per_person_sqm": 4.0,
    "formula": "(usable_area_sqm * usable_area_ratio) / area_per_person_sqm"
  }
}
```

### 4.4 Get Recommendations for Habitation
`GET /api/relocation/recommendations/{habitation_id}`
Returns relocation recommendations ordered by priority score.
* **Query Params**: `page`, `page_size`
* **Response**: `PaginatedResponse` (data: `List[RelocationRecommendationOut]`)

### 4.5 List Top Priorities
`GET /api/relocation/priorities`
Returns the highest priority suitable relocation recommendations across the system.
* **Query Params**: `page`, `page_size`
* **Response**: `PaginatedResponse` (data: `List[RelocationRecommendationOut]`)

### 4.6 Relocation Summary
`GET /api/relocation/summary`
Returns aggregate statistics of sites, capacity, and generated recommendations.
