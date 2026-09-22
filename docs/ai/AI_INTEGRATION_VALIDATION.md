# SETU AI — Integration & Validation Specification

Component: setu_ai_service  
Repository: SETU_FINAL  
Lead: Sudheer Maurya (AI/ML + Disaster Intelligence)  

## Operational Invariants & Hard Boundaries
1. Spatial Safety Radius: Fixed at 500 meters (MAX_DISTANCE_KM = 0.5). Incidents >500m apart are never merged.
2. Temporal Window: Active rolling cluster cache is 300 seconds (TIME_WINDOW_SECONDS = 300).
3. Priority Tiers:
   - CRITICAL: >= 4.5
   - HIGH: >= 3.5
   - MEDIUM: >= 2.5
   - LOW: < 2.5
4. Security Invariant: User-controlled message text can never override operational priority or force duplicate suppression.
5. Offline Reliability: Zero hard dependencies on external cloud APIs for emergency triage.
