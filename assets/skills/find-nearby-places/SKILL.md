---
name: find-nearby-places
description: >
  Finds disaster-critical nearby places on flutter_map using the offline POI
  database seeded at onboarding + the user's onboarding GPS / live GPS.
  Triggers on: "nearest shelter", "find hospital", "where can I get water",
  "nearest pharmacy/clinic/food/fuel/ATM/police/fire station", "charge my
  phone", "find a safe place", "show me shelters on the map", "where do I go
  for help", "I need [food/water/medical/fuel/cash/shelter]", "what's open
  near me", or any request to locate a critical facility during a disaster.
  Use whenever someone needs spatial awareness of critical resources.
---

# Find Nearby Places

**Stack:** flutter_map · sqflite POI cache · onboarding GPS
**No live API. Emits `mapViewRequest` JSON consumed by the Flutter layer.**

---

## 1 — Resolve category

| User says | Category | Radius |
|---|---|---|
| shelter / safe place / evacuation center | `shelter` | 5 km |
| hospital / ER | `hospital` | 10 km |
| clinic / doctor | `clinic` | 5 km |
| pharmacy / medicine | `pharmacy` | 3 km |
| water / drinking water | `water_point` | 2 km |
| food / food bank | `food_distribution` | 3 km |
| fuel / gas / petrol | `fuel_station` | 5 km |
| ATM / bank | `atm` | 2 km |
| police | `police` | 5 km |
| fire station | `fire_station` | 5 km |

**Vague request** ("find places", "where can I go", "show everything"):
→ search `shelter` + `hospital` + `water_point` simultaneously.

**Multiple categories** ("hospital or clinic"): search both, merge.

---

## 2 — Resolve location

Priority order:
1. live GPS fix if age < 30 min
2. onboarding region location (always present after onboarding)
3. ask user — only if both missing

---

## 3 — Query & filter

Query the local `places` SQLite table:

```
categories: requestedCategories
center:     userLocation { lat, lng }
radiusKm:   from category table
maxResults: 10 per category
```

**Sort:** `open` first → then `distanceKm` ascending.

**Status rules:**
- `compromised` → exclude silently
- `closed` → exclude unless zero open results
- `full` → include, rank last, label "⚠ May be at capacity"
- `unknown` → include, label "Status unverified"

**Zero results** → expand radius ×1.5 once. If still zero → noResultsBanner.

---

## 4 — Spoken response (≤25s TTS)

Lead with closest open result:
- `"Westside Shelter is 400 metres away — about 5 minutes on foot."`
- `"I found 3 open hospitals. The closest is St. Mary's, 1.2 km away."`
- `"No open shelters within 2 km. Showing the nearest at 4.1 km."`

Map + list carry detail. Do not read card content aloud.

---

## 5 — Output contract

```json
{
  "skill_invoked": "find-nearby-places",
  "spokenResponse": "...",
  "categories": ["shelter"],
  "radiusKm": 5.0
}
```

The Flutter layer parses this, runs `PlacesRepository.findNearby(...)`,
and pushes the map page. Do not invent place data — the on-device DB is
authoritative.

---

## 6 — Edge cases

| Condition | Action |
|---|---|
| Zero results after ×1.5 retry | banner: "Try a wider area" |
| Place layer empty (onboarding skipped) | banner: "Re-run onboarding to download places" |
| User already at place (dist < 0.05 km) | "You appear to be at [name] already." |
| GPS accuracy > 500 m | uncertainty circle on map + spoken note |
