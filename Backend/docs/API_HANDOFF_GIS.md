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
