# SETU GIS & Data Infrastructure API Contract

This document provides the API contracts for the new GIS, Risk, Vulnerability, and Relocation engines for the SETU Dashboard.

## 1. Datasets & Demo Seeding

### POST `/api/datasets/seed-demo`
Generates a deterministic synthetic demo dataset of habitations, hazards, relocation sites, and pre-calculates their risks and capacity.
**Returns:**
```json
{
  "status": "success",
  "message": "Demo data seeded successfully.",
  "logs": "..."
}
```

### GET `/api/datasets`
Lists all datasets.

---

## 2. Risk & Hazards

### GET `/api/risk/habitations`
**Query Parameters:** `page`, `page_size`, `district`
**Returns:**
```json
{
  "data": [
    {
      "id": 1,
      "name": "Demo Village 1",
      "district": "Prayagraj",
      "state": "Uttar Pradesh",
      "population": 500,
      "latitude": 25.3358,
      "longitude": 81.8263,
      "dataset_id": 1,
      "created_at": "2026-09-30T00:00:00Z",
      "updated_at": "2026-09-30T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 20,
    "total": 25,
    "total_pages": 2
  }
}
```

### GET `/api/risk/habitations/{id}`
Returns details for a specific habitation.

### GET `/api/risk/zones` (and `/api/risk/layers`)
**Query Parameters:** `page`, `page_size`, `hazard_type`
**Returns:**
```json
{
  "data": [
    {
      "id": 1,
      "hazard_type": "flood",
      "severity": "critical",
      "geometry": { "type": "Polygon", "coordinates": [...] },
      "min_lat": 25.3,
      "max_lat": 25.4,
      "min_lon": 81.7,
      "max_lon": 81.8,
      "dataset_id": 1,
      "created_at": "2026-09-30T00:00:00Z"
    }
  ],
  "pagination": { "page": 1, "page_size": 20, "total": 2, "total_pages": 1 }
}
```

### GET `/api/risk/summary`
**Returns:**
```json
{
  "total_habitations": 25,
  "risk_breakdown": {
    "critical": 5,
    "high": 8,
    "medium": 2,
    "low": 10
  },
  "total_hazard_layers": 2
}
```

---

## 3. Vulnerability

### GET `/api/vulnerability/habitations`
Returns a list of vulnerability assessments (same pagination structure).

### GET `/api/vulnerability/summary`
**Returns:**
```json
{
  "total_assessments": 25,
  "total_population_exposed": 56250
}
```

---

## 4. Relocation & Capacity

### GET `/api/relocation/sites`
**Query Parameters:** `page`, `page_size`, `district`, `min_capacity`
**Returns:**
```json
{
  "data": [
    {
      "id": 1,
      "name": "Safe Zone 1",
      "latitude": 25.3858,
      "longitude": 81.7963,
      "usable_area_sqm": 10000.0,
      "infrastructure": { "road_access": true, "water": true, "electricity": true },
      "services": { "hospital": true, "school": true },
      "current_occupancy": 0,
      "estimated_capacity": 2000,
      "remaining_capacity": 2000,
      "dataset_id": 1
    }
  ],
  "pagination": { "page": 1, "page_size": 20, "total": 8, "total_pages": 1 }
}
```

### GET `/api/relocation/recommendations/{habitation_id}`
Returns sites recommended for the given habitation, prioritized by suitability, distance, and capacity.
**Returns:**
```json
{
  "data": [
    {
      "id": 1,
      "habitation_id": 5,
      "site_id": 2,
      "distance_km": 12.5,
      "remaining_capacity": 3000,
      "suitable": true,
      "reasons": [
        "Within configured relocation radius (12.5km)",
        "Sufficient remaining capacity",
        "Outside matching high-risk hazard zones"
      ],
      "priority_score": 22.5
    }
  ],
  "pagination": { "page": 1, "page_size": 20, "total": 5, "total_pages": 1 }
}
```

### GET `/api/relocation/priorities`
Lists top recommended relocation actions across the dataset.

### GET `/api/relocation/summary`
**Returns:**
```json
{
  "total_relocation_sites": 8,
  "total_capacity": 22000,
  "occupied_capacity": 2800,
  "remaining_capacity": 19200,
  "recommendations_generated": 200
}
```

## 5. What-If Scenarios

### POST `/api/scenarios/evaluate/{base_dataset_id}`
Creates a temporary clone of the base dataset, applies modifications, and calculates the resulting relocation allocation difference.
**Request Body:**
```json
{
  "disabled_site_ids": [1],
  "added_hazards": []
}
```
**Returns:**
```json
{
  "scenario_dataset_id": 2,
  "impacted_habitations_count": 1,
  "impacted_habitations": [
    {
      "habitation_id": 5,
      "baseline_site_id": 1,
      "scenario_site_id": 2,
      "baseline_status": "FEASIBLE",
      "scenario_status": "PARTIAL",
      "reasoning": [
        "Partially allocated 100 people to Safe Zone 2 (Site reached maximum capacity)."
      ]
    }
  ],
  "recommended_actions": [
    "Review 1 allocation changes."
  ]
}
```

## 6. Red Zones

### GET `/api/red-zones`
Returns the model-assessed Red Zone classifications for habitations.

### GET `/api/red-zones/summary`
Returns the aggregated breakdown of Red Zones.

## 7. Field Observations & Decisions

### POST `/api/field/observations/{dataset_id}`
Simulates receiving a field observation (e.g. from the offline mesh) and triggers a deterministic recalculation of site capacities or habitation metadata.
**Request Body Example:**
```json
{
  "target_type": "SITE",
  "target_id": 1,
  "observation_type": "SITE_INACCESSIBLE",
  "details": {"reason": "Road blocked by landslide"},
  "source": "Field App"
}
```

### POST `/api/field/decisions/{dataset_id}`
Records an official authority decision against a relocation recommendation.
**Request Body Example:**
```json
{
  "habitation_id": 5,
  "recommended_site_id": 2,
  "status": "ACCEPTED",
  "actor": "District Magistrate",
  "rationale": "Proceeding with alternative site due to landslide"
}
```

## 8. AI Narrative

### GET `/api/ai/narrative/{habitation_id}`
Returns an AI-assisted text narrative explaining the deterministically calculated risk, vulnerability, and relocation recommendations.
**Returns:**
```json
{
  "methodology": "AI-ASSISTED",
  "narrative": "Based on the deterministic SETU models, Demo Village 1 has a Critical risk score of 22.0. This is driven primarily by exposure to critical flooding (10.0) and amplified by historical disasters (2.0)...",
  "confidence": "HIGH"
}
```
