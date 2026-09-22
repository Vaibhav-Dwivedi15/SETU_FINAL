"""
SETU AI - Responder Intelligence Generator
Produces structured, actionable incident summaries for first responders.
"""

from typing import Dict, Any, List


def generate_responder_brief(
    emergency_id: str,
    incident: str,
    priority: str,
    damage_info: Dict[str, Any],
    resource_info: Dict[str, Any],
    missing_info: Dict[str, Any],
    location_str: str = "Unknown Location",
) -> Dict[str, Any]:

    action_items: List[str] = []

    # Derive action items
    if priority in ["CRITICAL", "HIGH"]:
        action_items.append("Immediate search and rescue dispatch required")

    if damage_info.get("has_damage"):
        asset = damage_info.get("asset_type") or "Infrastructure"
        severity = damage_info.get("severity")
        affected = damage_info.get("estimated_affected")
        if affected:
            action_items.append(f"Deploy rescue team for ~{affected} people affected at {asset}")
        else:
            action_items.append(f"Assess structural safety of {severity.lower()} damaged {asset}")

    if resource_info.get("needs_resources"):
        cats = ", ".join(resource_info.get("categories", []))
        action_items.append(f"Mobilize emergency supplies: {cats} (Urgency: {resource_info.get('urgency')})")

    if missing_info.get("is_missing_report"):
        person = missing_info.get("name") or "individual"
        age = f", age {missing_info.get('age')}" if missing_info.get("age") else ""
        action_items.append(f"Broadcast missing person alert for {person}{age}")

    if not action_items:
        action_items.append("Monitor situation; conduct routine field assessment")

    # Construct one-line summary
    summary = f"[{priority}] {incident} reported near {location_str}."
    if damage_info.get("has_damage"):
        summary += f" {damage_info.get('severity')} damage to {damage_info.get('asset_type') or 'facilities'}."

    return {
        "summary": summary,
        "action_items": action_items,
    }
