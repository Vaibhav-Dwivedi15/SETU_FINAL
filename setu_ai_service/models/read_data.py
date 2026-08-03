from incident_classifier import detect_incident
from baseline_rules import classify_message
import pandas as pd

data = pd.read_csv("../data/synthetic_messages.csv")

print(data)

print("\n---- AI Predictions ----")

correct = 0
total = len(data)

for _, row in data.iterrows():
    message = row["message"]
    urgency = row["urgency"]

    predicted = classify_message(message)
    incident = detect_incident(message)

    if predicted == urgency:
        correct += 1

    print(f"Message    : {message}")
    print(f"Incident   : {incident}")
    print(f"Actual     : {urgency}")
    print(f"Predicted  : {predicted}")
    print("-" * 40)

accuracy = (correct / total) * 100

print("\n========================")
print(f"Accuracy: {accuracy:.2f}%")
print("========================")