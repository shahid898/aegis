---
name: grade-damage-hazus
description: Grade damage photo on FEMA HAZUS scale (1=Slight, 2=Moderate,
  3=Extensive, 4=Complete). Sub-step of disaster-report-generator.
---

# Grade Damage with FEMA HAZUS

## When this skill fires

Triage Mode (responder) captures a JPEG of a building or scene and
needs an actionable damage label. May be invoked directly, or as a
sub-step of `disaster-report-generator` when a report is being composed.

## FEMA HAZUS damage scale

* **HAZUS_NONE (0)** — Building intact, no observable damage.
* **HAZUS_SLIGHT (1)** — Hairline cracks, fallen tiles, broken
  windows. Building is safe to enter.
* **HAZUS_MODERATE (2)** — Partial structural failure: visible
  diagonal wall cracks, partial roof collapse, void spaces. Entry
  is dangerous; specialist SAR with shoring required.
* **HAZUS_EXTENSIVE (3)** — Major structural failure: load-bearing
  walls collapsed, building leaning, multiple void spaces. Specialist
  US&R team with heavy equipment required.
* **HAZUS_COMPLETE (4)** — Total or near-total collapse. Pancaked
  floors. Survivor extraction is high-difficulty, void-space search
  with canine and acoustic equipment.

## Instructions

For each photo:

1. Identify the dominant building / structure / vehicle in frame.
2. Apply the HAZUS scale above. If multiple structures with different
   levels are visible, grade the worst one (this is what drives the
   resource request).
3. Note hazards visible in the photo — fire, smoke, water, fallen
   power lines, leaning structures.
4. Emit one `damageCard` per photo with `category`, `fema_scale`, a
   one-line description, and a reference to the photo.
5. If the level is `>= 2`, also emit a `resourceRequestCard`
   recommending the appropriate SAR equipment.

## Output

`a2ui_messages` containing one or more `damageCard` components and,
when level ≥ 2, a `resourceRequestCard`.
