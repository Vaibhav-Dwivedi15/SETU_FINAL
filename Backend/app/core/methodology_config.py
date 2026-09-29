# backend/app/core/methodology_config.py

# Methodology Version
METHODOLOGY_NAME = "SETU SIH26191 Risk Methodology"
METHODOLOGY_VERSION = "2.1.0"

# Risk Thresholds
RISK_CRITICAL_THRESHOLD = 15.0
RISK_HIGH_THRESHOLD = 8.0
RISK_MEDIUM_THRESHOLD = 4.0

# Hazard Severity Weights
HAZARD_WEIGHTS = {
    "critical": 10.0,
    "high": 7.0,
    "medium": 4.0,
    "low": 1.0
}

# Vulnerability Thresholds
VULN_EXTREME_THRESHOLD = 50.0

# Red Zone Thresholds
# A Red Zone is declared if Risk is Critical AND Vulnerability is Extreme
RED_ZONE_RISK_REQUIREMENT = "Critical"
RED_ZONE_VULN_REQUIREMENT = 50.0

# Relocation Priority Boundaries (base priority score thresholds)
PRIORITY_IMMEDIATE_THRESHOLD = 100.0
PRIORITY_SHORT_TERM_THRESHOLD = 50.0
PRIORITY_MEDIUM_TERM_THRESHOLD = 20.0

# Capacity & Constraints
CAPACITY_USABLE_AREA_RATIO = 0.6
CAPACITY_AREA_PER_PERSON_SQM = 4.0
CAPACITY_WATER_LITERS_PER_PERSON = 15.0
CAPACITY_PERSONS_PER_TOILET = 20
CAPACITY_PERSONS_PER_MEDICAL_BED = 50

# Relocation Distance Boundaries
MAX_RELOCATION_RADIUS_KM = 50.0

# Data Freshness
DATA_STALE_DAYS_DATASET = 365
DATA_STALE_DAYS_HAZARD = 180
