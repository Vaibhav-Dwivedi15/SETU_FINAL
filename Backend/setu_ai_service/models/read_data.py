"""
SETU AI - Model Evaluation Report

v2: Was previously a simple accuracy-only check against urgency labels.
Now evaluates BOTH urgency and incident classification (the dataset now
carries incident-type ground truth too, which it didn't before), reports
proper per-class precision/recall/F1 via sklearn.classification_report
(matching the original role brief's step 4), and - critically - splits
the dataset into two honest categories:

  - "core": genuine emergency and non-emergency messages the system is
    actually meant to handle correctly.
  - "hard_negative": messages that DELIBERATELY contain keyword
    collisions with no real emergency behind them (e.g. "fire safety
    drill", "phone battery is critical"). These are NOT expected to
    pass reliably - a pure keyword-matching system cannot distinguish
    literal danger from metaphorical/past-tense/hypothetical mentions
    without real language understanding. Reporting these separately
    (instead of quietly excluding them, which would inflate the headline
    number) is the honest way to present this system's real limitation.

Run from the project root (Windows):
    python -m models.read_data
"""

from pathlib import Path

import pandas as pd
from sklearn.metrics import classification_report

from models.baseline_rules import classify_message
from models.incident_classifier import detect_incident
from models.confidence_scorer import score_urgency, score_incident

DATA_PATH = Path(__file__).resolve().parents[1] / "data" / "synthetic_messages.csv"

data = pd.read_csv(DATA_PATH)
core = data[data["category"] == "core"].reset_index(drop=True)
hard_negatives = data[data["category"] == "hard_negative"].reset_index(drop=True)

print(f"Loaded {len(data)} messages: {len(core)} core, {len(hard_negatives)} hard-negative\n")

# ==========================================================================
# CORE SET - this is the number that actually represents system quality.
# ==========================================================================
core_true_urgency, core_pred_urgency = [], []
core_true_incident, core_pred_incident = [], []
confidences_correct, confidences_incorrect = [], []

for _, row in core.iterrows():
    msg = row["message"]
    pred_u = classify_message(msg)
    pred_i = detect_incident(msg)

    core_true_urgency.append(row["urgency"])
    core_pred_urgency.append(pred_u)
    core_true_incident.append(row["incident"])
    core_pred_incident.append(pred_i)

    u_conf = score_urgency(msg)["confidence"]
    i_conf = score_incident(msg)["confidence"]
    avg_conf = (u_conf + i_conf) / 2
    if pred_u == row["urgency"] and pred_i == row["incident"]:
        confidences_correct.append(avg_conf)
    else:
        confidences_incorrect.append(avg_conf)
        print(f"  [CORE MISS] \"{msg}\"")
        print(f"      urgency:  true={row['urgency']} pred={pred_u}")
        print(f"      incident: true={row['incident']} pred={pred_i}")

urgency_acc = sum(t == p for t, p in zip(core_true_urgency, core_pred_urgency)) / len(core)
incident_acc = sum(t == p for t, p in zip(core_true_incident, core_pred_incident)) / len(core)

print("\n" + "=" * 70)
print("CORE SET RESULTS (genuine emergency/non-emergency messages)")
print("=" * 70)
print(f"Urgency accuracy:  {urgency_acc * 100:.1f}%")
print(f"Incident accuracy: {incident_acc * 100:.1f}%")

print("\n--- Urgency classification_report ---")
print(classification_report(core_true_urgency, core_pred_urgency, zero_division=0))

print("--- Incident classification_report ---")
print(classification_report(core_true_incident, core_pred_incident, zero_division=0))

if confidences_correct:
    print(f"Avg confidence on CORRECT predictions:   {sum(confidences_correct)/len(confidences_correct):.2f}")
if confidences_incorrect:
    print(f"Avg confidence on INCORRECT predictions: {sum(confidences_incorrect)/len(confidences_incorrect):.2f}")
    print("(Lower confidence on misses is a good sign - it means the confidence")
    print(" score is actually diagnostic, not just decorative.)")

# ==========================================================================
# HARD NEGATIVE SET - documented as a known limitation, not hidden.
# ==========================================================================
print("\n" + "=" * 70)
print("HARD NEGATIVE SET (deliberate keyword-collision traps)")
print("=" * 70)
print("These messages contain danger keywords with NO real emergency behind")
print("them. A pure keyword-matching system is expected to false-trigger on")
print("most of these - that's reported here honestly, not excluded from the")
print("dataset. This is a genuine limitation, not a bug: fixing it requires")
print("actual language understanding (e.g. the Gemini fallback path), not")
print("more keywords.\n")

false_triggers = 0
for _, row in hard_negatives.iterrows():
    msg = row["message"]
    pred_u = classify_message(msg)
    pred_i = detect_incident(msg)
    triggered = pred_u >= 4 or pred_i != "Unknown"
    if triggered:
        false_triggers += 1
    status = "FALSE-TRIGGERED" if triggered else "correctly ignored"
    print(f"  [{status}] \"{msg}\" -> urgency={pred_u}, incident={pred_i}")

print(f"\nFalse-trigger rate: {false_triggers}/{len(hard_negatives)} "
      f"= {100 * false_triggers / len(hard_negatives):.1f}%")
