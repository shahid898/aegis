---
name: match-mesh-beacon
description: Cross-reference a survivor statement, photo, or incident
  description against mesh beacons in the local incident log. Returns
  a confidence score so a responder can confirm whether two reports
  describe the same person or location. Use as a sub-step of
  generate-ics-209 or when the user asks "is there a beacon for
  this person".
---

# Match Mesh Beacon

## When this skill fires

A casualty has been described in a statement, OR a survivor's
location has been photographed, AND there are recent mesh beacons
in the incident log (last N entries from Isar). Beacons travel via
the offline mesh network and may already describe the same person
from a different angle.

## Instructions

For each candidate match:

1. Compute similarity across these axes (each 0.0 to 1.0):
   * **Name / nickname overlap** — exact (1.0), nickname (0.8),
     soundex (0.5), none (0.0).
   * **Demographics overlap** — sex (binary), age bucket
     (±5 → 1.0, ±15 → 0.5).
   * **Distinguishing feature overlap** — wheelchair, prosthetic,
     specific clothing, language spoken.
   * **Spatial proximity** — beacon GPS within 100m → 1.0, within
     500m → 0.5, within 2km → 0.2.
   * **Temporal proximity** — beacon within 30 min → 1.0, 2 h → 0.7,
     6 h → 0.4, older → 0.1.
2. Aggregate: weighted average with weights
   `{name: 0.35, demographics: 0.20, features: 0.20, spatial: 0.15,
   temporal: 0.10}`.
3. Threshold: emit a `beaconMatchCard` only if confidence ≥ 0.70.
   Below that, surface nothing — false matches are worse than
   missed matches in a triage context.
4. Include the matched beacon's content verbatim in the card so the
   responder can verify the match before acting on it.

## Output

Zero or more `beaconMatchCard` components. Each card carries a
`matched_id`, a `confidence` score, and the original beacon text.
