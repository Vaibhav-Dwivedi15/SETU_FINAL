"""
SETU AI - Explainability Layer

Turns confidence_scorer.py's raw output (matched keywords, conflicting
categories, confidence numbers) into a short, human-readable sentence
explaining WHY the system classified a message the way it did. This
matters for a dispatcher-facing emergency tool: "Fire, urgency 5" is a
lot more trustworthy - and a lot easier to sanity-check under
pressure - when it comes with "matched: fire, aag" attached, instead
of being a black-box number.

This is a thin layer on top of confidence_scorer.py, not a separate
decision-making path - it never re-decides anything, it only narrates
the decision confidence_scorer.py already made. That's a deliberate
design choice: a rule-based system's explanation should be a direct
readout of the rules that fired, not a second model's guess at why the
first one did what it did.

Author : SETU Team
Version : 1.0
"""

from models.confidence_scorer import score_urgency, score_incident


def _explain_urgency(result: dict) -> str:
    if not result["matched_keywords"]:
        return f"No urgency keywords matched; defaulted to level {result['urgency']} (baseline, low confidence)."

    keywords = ", ".join(f"'{kw}'" for kw in result["matched_keywords"])
    sentence = f"Urgency {result['urgency']} because message matched: {keywords}."

    if result["conflicting_categories"]:
        sentence += (
            f" Also weakly matched urgency level(s) {result['conflicting_categories']}, "
            f"which reduced confidence to {result['confidence']}."
        )
    return sentence


def _explain_incident(result: dict) -> str:
    if not result["matched_keywords"]:
        return f"No incident-type keywords matched; classified as '{result['incident']}' (baseline, low confidence)."

    keywords = ", ".join(f"'{kw}'" for kw in result["matched_keywords"])
    sentence = f"Classified as '{result['incident']}' because message matched: {keywords}."

    if result["conflicting_categories"]:
        others = ", ".join(f"'{c}'" for c in result["conflicting_categories"])
        sentence += (
            f" Message also partially matched {others}, "
            f"which reduced confidence to {result['confidence']}."
        )
    return sentence


def explain(message: str) -> dict:
    """
    Returns a full explainability report for one message:
        {
          "message": str,
          "urgency": int,
          "urgency_confidence": float,
          "urgency_explanation": str,
          "incident": str,
          "incident_confidence": float,
          "incident_explanation": str,
        }
    """
    urgency_result = score_urgency(message)
    incident_result = score_incident(message)

    return {
        "message": message,
        "urgency": urgency_result["urgency"],
        "urgency_confidence": urgency_result["confidence"],
        "urgency_explanation": _explain_urgency(urgency_result),
        "incident": incident_result["incident"],
        "incident_confidence": incident_result["confidence"],
        "incident_explanation": _explain_incident(incident_result),
    }


if __name__ == "__main__":
    tests = [
        "Fire in my building",
        "aag lag gayi meri building mein madad karo",
        "Fire and flood both happening, help",
        "Good morning",
    ]
    for msg in tests:
        report = explain(msg)
        print(f"Message: {report['message']}")
        print(f"  {report['urgency_explanation']}")
        print(f"  {report['incident_explanation']}")
        print("-" * 60)
