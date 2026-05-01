---
name: plan-evacuation-route
description: Plan an accessibility-aware evacuation route from the
  user's current GPS to the nearest safe shelter, accounting for
  blocked roads, the user's mobility profile, and any reported
  hazards in the incident log. Use when the user asks "how do I get
  out", "where do I go", "what's the safest route", or when an
  evacuation order is in effect.
---

# Plan Evacuation Route

## When this skill fires

Survivor (Ask Mode) is in an active hazard zone and needs to leave.
A responder (Triage Mode) might also invoke this on behalf of an
evacuee they are guiding.

## Instructions

When invoked, run the offline router shipped in the region pack:

1. **Source.** Current GPS, snapped to the road graph node.
2. **Sink.** Closest open shelter that matches the user's mobility
   profile (wheelchair-accessible, no stairs, etc.).
3. **Avoid.** Any road segment marked blocked or hazardous in the
   incident log within the last 6 hours.
4. **Mode.** Walking by default. Driving if the user said they have
   a vehicle, OR if the route is longer than 2 km. Wheelchair-
   compatible if the accessibility profile flags mobility.

Apply these rules to the spoken response:

* State the distance and the **first turn**. Don't dump the entire
  turn-by-turn — that goes in the surface.
* Name a single landmark on the route ("past the school on your
  left") to anchor the user's mental map.
* End with a safety bullet — what to bring, what to avoid, when to
  turn back.

## Output

Emits a `mapFragment` with the route polyline, plus a step-list
column. If the route crosses any reported hazard, add a banner
warning above the map. If no walkable route exists, downgrade to
"shelter in place" guidance and explain why.
