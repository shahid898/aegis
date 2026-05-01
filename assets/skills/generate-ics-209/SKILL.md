---
name: generate-ics-209
description: Generate a FEMA ICS-209 compliant incident report from
  photos, voice statements, and incident context. Apply START triage,
  grade damage with HAZUS, and cross-reference with mesh beacons in
  the incident log. Use when a responder captures a scene and asks
  for a report, says "file it", "make a report", or "send to FEMA".
---

# Generate ICS-209 Report

## When this skill fires

Triage Mode (responder) has captured one or more photos and/or one
or more voice statements at an incident scene and wants a structured
report queued for sync. This is the umbrella skill — it composes
output from the `grade-damage-hazus`, `intake-survivor-statement`,
and `match-mesh-beacon` skills.

## Instructions

When a responder captures a scene with photos and/or voice and asks
for a report:

1. **Damage.** Run `grade-damage-hazus` against every photo. Emit
   one `damageCard` per photo.
2. **Casualties.** Run `intake-survivor-statement` against every
   voice statement. Emit one `casualtyCard` per person mentioned.
3. **Beacon match.** Run `match-mesh-beacon` against every
   casualty. Emit a `beaconMatchCard` for any high-confidence match
   (>= 0.7).
4. **Resources.** Recommend the required SAR / medical / logistics
   resources as a single `resourceRequestCard`. Base the
   recommendation on the worst HAZUS level present, the highest
   triage priority, and the count of trapped survivors.
5. **Confirm.** Always end with a `confirmActionBar` so the
   responder can `Confirm & queue for sync` or `Edit report`.
6. **Trace.** Populate `thinking_trace` with your reasoning chain —
   which evidence drove which conclusion. The responder taps the
   thinking-trace drawer to verify before confirming.

Always emit valid JSON conforming to the `TriageReport` schema.
Never emit prose outside JSON.

## Triage priority rule

Set `incident_metadata.triage_priority` to the highest START colour
present across all `casualtyCard` components:

* Any `RED` → `RED`
* Else any `YELLOW` → `YELLOW`
* Else any `GREEN` → `GREEN`
* Else `BLACK` only → `BLACK`
* No casualties → `INFO`

## Output

A complete `TriageReport` JSON. The renderer streams the surface
into a verification layer — nothing auto-commits.
