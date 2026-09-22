"""
SETU AI - Comprehensive Test Suite
Validates Incident Classification, Geolocation Deduplication, and Disaster Recovery Intelligence.
"""

import unittest
from models.incident_classifier import (
    detect_incident,
    FIRE,
    FLOOD,
    EARTHQUAKE,
    LANDSLIDE,
    CYCLONE,
    BUILDING_COLLAPSE,
    ROAD_BLOCKAGE,
    MEDICAL,
    MISSING_PERSON,
    RESOURCE_SHORTAGE,
    UNKNOWN,
)
from models.duplicate_detector import check_duplicate, reset_clusters
from models.disaster_intelligence import (
    extract_damage_info,
    extract_resource_info,
    extract_missing_person_info,
)
from models.pipeline import process_message


class TestIncidentClassifier(unittest.TestCase):
    def test_all_10_categories(self):
        cases = {
            "Massive fire breaking out in market area": FIRE,
            "Major medical emergency patient unconscious and bleeding": MEDICAL,
            "Flood water rising fast houses submerged": FLOOD,
            "Building collapse several people trapped under debris": BUILDING_COLLAPSE,
            "Strong earthquake tremors felt ground shaking": EARTHQUAKE,
            "Severe landslide blocked the entire hillside road": LANDSLIDE,
            "Cyclone approaching with high winds and storm": CYCLONE,
            "Main highway and road blocked by fallen trees": ROAD_BLOCKAGE,
            "Lost child missing since afternoon last seen near market": MISSING_PERSON,
            "Food shortage in relief camp urgent need food and drinking water": RESOURCE_SHORTAGE,
            "Just checking general status hello": UNKNOWN,
        }
        for message, expected in cases.items():
            with self.subTest(message=message):
                detected = detect_incident(message)
                self.assertEqual(detected, expected, f"Failed for '{message}': got '{detected}'")


class TestSafeDeduplication(unittest.TestCase):
    def setUp(self):
        reset_clusters()

    def test_different_locations_not_duplicate(self):
        res1 = check_duplicate(
            message="Building fire need help",
            emergency_id="e-001",
            incident_type=FIRE,
            latitude=25.4358,
            longitude=81.8463,
        )
        self.assertFalse(res1["is_duplicate"])

        res2 = check_duplicate(
            message="Building fire need help",
            emergency_id="e-002",
            incident_type=FIRE,
            latitude=28.6139,
            longitude=77.2090,
        )
        self.assertFalse(res2["is_duplicate"])
        self.assertEqual(res2["matched_cluster_id"], "e-002")

    def test_same_location_is_duplicate(self):
        res1 = check_duplicate(
            message="Gas cylinder fire near central school",
            emergency_id="e-101",
            incident_type=FIRE,
            latitude=25.4358,
            longitude=81.8463,
        )
        self.assertFalse(res1["is_duplicate"])

        res2 = check_duplicate(
            message="Gas cylinder fire near central school building",
            emergency_id="e-102",
            incident_type=FIRE,
            latitude=25.4360,
            longitude=81.8465,
        )
        self.assertTrue(res2["is_duplicate"])
        self.assertEqual(res2["matched_cluster_id"], "e-101")


class TestDisasterIntelligence(unittest.TestCase):
    def test_damage_extraction(self):
        msg = "The main bridge has collapsed and 4 people are trapped"
        damage = extract_damage_info(msg)
        self.assertTrue(damage.has_damage)
        self.assertEqual(damage.asset_type, "Bridge")
        self.assertEqual(damage.severity, "CATASTROPHIC")
        self.assertEqual(damage.estimated_affected, 4)

    def test_resource_extraction(self):
        msg = "Urgent need clean drinking water and food rations for 50 people"
        res = extract_resource_info(msg)
        self.assertTrue(res.needs_resources)
        self.assertIn("Water", res.categories)
        self.assertIn("Food", res.categories)
        self.assertEqual(res.urgency, "IMMEDIATE")

    def test_missing_person_extraction(self):
        msg = "Missing 8 years old boy named Rohan last seen near bus stand"
        missing = extract_missing_person_info(msg)
        self.assertTrue(missing.is_missing_report)
        self.assertEqual(missing.age, 8)
        self.assertEqual(missing.gender, "MALE")
        self.assertEqual(missing.name, "Rohan")


class TestEndToEndPipeline(unittest.TestCase):
    def setUp(self):
        reset_clusters()

    def test_pipeline_execution(self):
        result = process_message(
            message="Earthquake tremor destroyed hospital building with 6 people injured",
            relay_count=1,
            age_seconds=15,
            emergency_id="e-pipeline-1",
            latitude=25.4358,
            longitude=81.8463,
        )
        self.assertEqual(result["incident"], EARTHQUAKE)
        self.assertIn(result["priority"], ["CRITICAL", "HIGH", "MEDIUM", "LOW"])
        self.assertTrue(result["damage_assessment"]["has_damage"])
        self.assertEqual(result["damage_assessment"]["estimated_affected"], 6)


if __name__ == "__main__":
    unittest.main()
