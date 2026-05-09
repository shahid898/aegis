---
name: compose-briefing
description: Pre-disaster briefing from GPS + region pack. Triggers on
  "what's the situation", "brief me", "what do I need to know".
---

# Compose Briefing

## When this skill fires

Survivor (Ask Mode) opens the app and asks for context, OR the
home screen renders before any specific question. The briefing
runs offline using only data in the active region pack plus the
last GPS fix.

## Instructions

When invoked, produce a briefing organised in this order:

1. **Hazards near you.** Check the region pack's active alerts
   layer. List any flooding, fire, earthquake aftershock, chemical,
   or severe weather alert within 25km. If none active, say "No
   active alerts in your area."
2. **Where to go.** From the region pack's shelter layer, name the
   closest two open shelters and their walking distance.
3. **What to bring.** Cross-reference the user's accessibility
   profile (mobility, vision, hearing, medical) with the
   region-specific go-bag template. Output a `goBagChecklist`
   surface containing the 6-10 highest-priority items.
4. **What you can do right now.** One concrete action the user
   can take in the next five minutes (charge phone, fill water
   bottles, locate flashlight).

Always emit a `shelterPreviewCard` for the closest shelter, and
the `goBagChecklist` surface. Add a `mapFragment` if the region
pack contains a street-level tile for the current GPS cell.

Keep the spoken response under 30 seconds. The cards carry the
detail; the voice carries the priorities.

## Output

Emits `AskResponse` JSON with `skill_invoked: "compose-briefing"`
and an `a2ui_messages` list containing at minimum a
`shelterPreviewCard` and a `goBagChecklist`.
