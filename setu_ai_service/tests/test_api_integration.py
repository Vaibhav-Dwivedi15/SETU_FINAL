"""
SETU AI - API Route Integration Test Suite
Validates actual FastAPI application routing, HTTP status codes, and Pydantic contracts.
"""

import unittest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


class TestAPIIntegration(unittest.TestCase):
    def test_root_health_check(self):
        response = client.get("/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data.get("status"), "Running")
        self.assertEqual(data.get("project"), "SETU AI Service")

    def test_post_analyze_full_pipeline(self):
        payload = {
            "emergency_id": "api-test-01",
            "message": "Strong earthquake destroyed hospital building, 5 people trapped",
            "relay_count": 2,
            "age_seconds": 30,
            "location": {"latitude": 25.4358, "longitude": 81.8463},
        }
        response = client.post("/analyze", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["incident"], "Earthquake")
        self.assertIn(data["priority"], ["CRITICAL", "HIGH", "MEDIUM", "LOW"])
        self.assertTrue(data["damage_assessment"]["has_damage"])
        self.assertEqual(data["damage_assessment"]["asset_type"], "Hospital")

    def test_post_analyze_damage_standalone(self):
        payload = {"message": "The flyover bridge has collapsed completely"}
        response = client.post("/analyze/damage", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["has_damage"])
        self.assertEqual(data["asset_type"], "Bridge")
        self.assertEqual(data["severity"], "CATASTROPHIC")

    def test_post_analyze_resources_standalone(self):
        payload = {"message": "Urgent clean drinking water and food packets needed for shelter"}
        response = client.post("/analyze/resources", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["needs_resources"])
        self.assertIn("Water", data["categories"])
        self.assertIn("Food", data["categories"])

    def test_post_analyze_missing_person_standalone(self):
        payload = {"message": "Missing 10 years old girl named Priya separated during evacuation"}
        response = client.post("/analyze/missing-person", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["is_missing_report"])
        self.assertEqual(data["name"], "Priya")
        self.assertEqual(data["age"], 10)
        self.assertEqual(data["gender"], "FEMALE")

    def test_invalid_json_payload_fails_safely(self):
        # Missing required field 'emergency_id'
        invalid_payload = {"message": "Fire in market"}
        response = client.post("/analyze", json=invalid_payload)
        self.assertEqual(response.status_code, 422)  # FastAPI validation error

    def test_empty_message_handled_gracefully(self):
        payload = {
            "emergency_id": "api-empty-01",
            "message": "   ",
            "relay_count": 0,
            "age_seconds": 0,
        }
        response = client.post("/analyze", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["incident"], "Unknown")


if __name__ == "__main__":
    unittest.main()
