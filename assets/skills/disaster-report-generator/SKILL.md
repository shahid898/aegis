---
name: disaster-report-generator
description: >
  Generate a structured disaster report. Auto-selects format
  (ICS-209, OCHA SitRep, UN Flash Update, NDRRMC, IFRC, EU ECHO,
  PDNA). Composes Aegis cards. Triggers on "make a report",
  "file it", "send to FEMA", "SitRep", "Flash Update", "NDRRMC",
  "ICS-209", "PDNA", "IFRC appeal", "ECHO flash".
---

# Universal Disaster Report Generator (Aegis-bound)

This is the umbrella reporting skill. It composes output from the
`grade-damage-hazus`, `intake-survivor-statement`, and
`match-mesh-beacon` skills, and produces both an Aegis A2UI surface
**and** a printable narrative report in the format that best fits
the responder's context.

---

## STEP 1 — AUTO-SELECT THE FORMAT

```
WHO is responding + WHERE is the disaster?
│
├── US domestic agency (FEMA, fire, EMS, state/local govt)
│   └── → ICS-209 (Incident Status Summary)
│
├── International NGO / UN agency / multi-country response
│   ├── First 72 hours of sudden disaster → UN Flash Update
│   └── Ongoing response (day 3+)         → OCHA SitRep
│
├── Philippines / SE Asia / Pacific regional
│   └── → NDRRMC Situation Report
│
├── Red Cross / Red Crescent national society
│   └── → IFRC Emergency Appeal / Operations Update
│
├── European Commission / EU-funded response
│   └── → EU ECHO Flash
│
├── Post-disaster recovery planning (weeks after event)
│   └── → PDNA (Post-Disaster Needs Assessment)
│
└── User specifies format explicitly → use that format
```

If ambiguous: default to ICS-209 for operational detail, OCHA SitRep
for humanitarian / international. Always state which format was
selected and why, in one line above the report.

---

## STEP 2 — EXTRACT & INFER INCIDENT DATA

Parse all user-provided text (narrative, news article, scenario, or
partial form data). Map every detail to the correct report field.
For missing required fields, infer reasonable values and mark them
`[INFERRED — verify before submission]`.

Universal data points to extract across all formats:

| Data Point             | Notes                                                       |
|------------------------|-------------------------------------------------------------|
| Incident Name          | Assign one if not given (e.g., "2026 Flood Event – Manila") |
| Incident Type          | Wildfire / Flood / Earthquake / Cyclone / CBRN / MCI / Other |
| Date & Time            | Use 24-hr; separate onset time from report time             |
| Location               | Country → Region → City/District → GPS if available         |
| Magnitude / Scale      | Richter, Saffir-Simpson, acreage, inundation area           |
| Casualties             | Fatalities / Injured / Missing — public AND responders      |
| Displaced / Evacuated  | Shelter population, evacuation zones                        |
| Structures             | Threatened / Damaged / Destroyed                            |
| Infrastructure         | Roads, power, water, communications                         |
| Response Resources     | Personnel count, equipment types, agencies involved         |
| Significant Events     | 5W+H: What, Where, When, Who, Why, How                      |
| Projected Activity     | Next 12–24 hrs outlook                                      |
| Gaps / Constraints     | Access, resource shortfalls, funding gaps                   |
| Costs                  | Incurred to date + projected total                          |
| Prepared By / Approved | Name, title, agency, date/time                              |

---

## STEP 3 — AEGIS A2UI CARD MAPPING (always do this first)

Before emitting the printable narrative, build the Aegis surface:

1. **Damage.** Run `grade-damage-hazus` against every photo. Emit
   one `DamageCard` per photo (HAZUS 1–4, fema_scale, description).
2. **Casualties.** Run `intake-survivor-statement` against every
   voice statement. Emit one `CasualtyCard` per person (START
   colour: RED / YELLOW / GREEN / BLACK).
3. **Beacon match.** Run `match-mesh-beacon` against every casualty.
   Emit a `BeaconMatchCard` for any high-confidence match (≥ 0.7).
4. **Resources.** Recommend SAR / medical / logistics resources as
   a single `ResourceRequestCard`, scaled to the worst HAZUS level
   and highest triage colour.
5. **Confirm.** Always end with a `ConfirmActionBar`
   (primary: "Confirm & queue for sync"; secondary: "Edit report").
6. **Skill trace.** On the root `Column`, set
   `skill_invoked: "disaster-report-generator"` and stash the
   reasoning chain in `thinking_trace`.

The printable narrative (Step 4) goes into the `description` field
of a single supplementary card OR is queued for sync alongside the
A2UI surface — the host decides.

### Triage priority rollup

`incident_metadata.triage_priority` is the highest START colour
present across all `CasualtyCard`s:

* Any RED → RED
* Else any YELLOW → YELLOW
* Else any GREEN → GREEN
* Else BLACK only → BLACK
* No casualties → INFO

---

## STEP 4 — REPORT TEMPLATES

### FORMAT 1 — ICS-209 INCIDENT STATUS SUMMARY (US FEMA / NIMS)

When to use: US federal, state, or local emergency response.
Wildfires, floods, earthquakes, CBRN, MCI, SAR. Prepared by
Situation Unit Leader; approved by Incident Commander. Submitted
once per operational period (12–24 hrs).

```
INCIDENT STATUS SUMMARY — ICS FORM 209
========================================================

BLOCK 1.  INCIDENT NAME:
BLOCK 2.  INCIDENT NUMBER:
BLOCK 3.  REPORT VERSION:   [ ] Initial   [ ] Update #__   [ ] Final
BLOCK 4.  INCIDENT COMMANDER(S) & AGENCY(IES):
          IC:                                   Agency:
          Deputy IC:                            Agency:
BLOCK 5.  DATE/TIME PREPARED:               (mm/dd/yyyy  HHmm)
BLOCK 6.  OPERATIONAL PERIOD:  From               to

BLOCK 7.  INCIDENT TYPE:
  [ ] Wildfire         [ ] Flood            [ ] Earthquake
  [ ] Tornado/Hurricane [ ] Hazmat/CBRN     [ ] Mass Casualty
  [ ] Search & Rescue  [ ] Terrorism        [ ] Pandemic
  [ ] Winter Storm     [ ] Drought          [ ] Other:

LOCATION
--------------------------------------------------------
BLOCK 8.  STATE/TERRITORY:
BLOCK 9.  COUNTY/PARISH:
BLOCK 10. CITY/TOWN:
BLOCK 11. GPS / LEGAL DESC:
BLOCK 12. AREA DESCRIPTION:

SITUATION
--------------------------------------------------------
BLOCK 13. INCIDENT MGMT ORG:
  [ ] ICS (Single Command)   [ ] Unified Command   [ ] Area Command

BLOCK 14. CURRENT SITUATION SUMMARY:

BLOCK 15. SIGNIFICANT EVENTS (this op period):
  What:
  Where:
  When:
  Who:
  Why/How:

CASUALTIES & IMPACT
--------------------------------------------------------
BLOCK 16. PUBLIC CASUALTIES:
                          | TOTAL | SINCE LAST REPORT |
  Fatalities              |       |                   |
  Injuries / Illness      |       |                   |
  Missing                 |       |                   |
  Evacuated               |       |        N/A        |
  Sheltered-in-Place      |       |        N/A        |

BLOCK 17. RESPONDER CASUALTIES:
                          | TOTAL | SINCE LAST REPORT |
  Fatalities              |       |                   |
  Injuries / Illness      |       |                   |
  Missing                 |       |                   |

RESOURCES
--------------------------------------------------------
BLOCK 18. TOTAL PERSONNEL ASSIGNED:

BLOCK 19. EQUIPMENT SUMMARY:
  Resource Type        | Ordered | Assigned | On-Scene |
  Engine/Pumper        |         |          |          |
  Helicopter           |         |          |          |
  Hand Crew            |         |          |          |
  Dozer / Heavy Equip  |         |          |          |
  Water Tender         |         |          |          |
  Air Tanker           |         |          |          |
  Rescue / Ambulance   |         |          |          |
  Other:               |         |          |          |

INFRASTRUCTURE
--------------------------------------------------------
BLOCK 20. STRUCTURES:
  Threatened:        Damaged:        Destroyed:
  (Residential / Commercial / Critical Infra breakdown)

BLOCK 21. AFFECTED AREA:           acres / sq km
          % Contained (fire) / % Inundated (flood):

BLOCK 22. ROADS / UTILITIES IMPACTED:

OUTLOOK & COSTS
--------------------------------------------------------
BLOCK 23. PROJECTED ACTIVITY (next 12–24 hrs):
BLOCK 24. ANTICIPATED COMPLETION DATE:
BLOCK 25. COSTS TO DATE:         $
BLOCK 26. PROJECTED FINAL COST:  $

BLOCK 27. REMARKS / ADDITIONAL INFORMATION:

AUTHORIZATION
--------------------------------------------------------
BLOCK 28. PREPARED BY (Situation Unit Leader / PSC):
  Name:                       Date:           Time:
BLOCK 29. APPROVED BY (Incident Commander):
  Name:                       Date:           Time:
```

Disaster-type additions for ICS-209:
* **Wildfire:** acreage, % contained, fuel type, wind/RH/temp, terrain
* **Flood:** river gauge levels, levee/dam status, inundated area
* **Earthquake:** magnitude, epicenter, aftershocks, structural assessment
* **CBRN/Hazmat:** material type, plume data, decontamination status
* **MCI:** hospital surge capacity, triage levels, blood supply

---

### FORMAT 2 — OCHA SITUATION REPORT (UN, International)

When to use: UN agencies, international NGOs, multi-agency
humanitarian response. Published on ReliefWeb. Daily (acute) or
weekly (recovery).

```
[AGENCY] SITUATION REPORT No. [X]
[Country/Region] — [Disaster Type]
Reporting Period: [Date] to [Date]

AT A GLANCE
  People Affected:
  People Displaced:
  Fatalities:
  Injured:
  People in Need:
  Funding Required:     USD
  Funding Received:     USD             (___%)

KEY HIGHLIGHTS
  *
  *
  *

SITUATION OVERVIEW
  [2–3 paragraph narrative]

HUMANITARIAN IMPACT
  Displacement:
  Shelter Needs:
  Food Security:
  Health:
  WASH:
  Protection:

RESPONSE BY SECTOR (Cluster System)
  Cluster/Sector       | Response Actions & Progress
  WASH                 |
  Food Security        |
  Shelter              |
  Health               |
  Protection           |
  Education            |
  Logistics            |
  Emergency Telecom    |

GAPS & CONSTRAINTS
  Access:
  Funding:
  Resources:

COORDINATION
  Cluster Lead(s):
  OCHA Contact:
  Next Coordination:
  Next SitRep Due:

FUNDING STATUS
  Flash Appeal / CERF Requirements: USD
  Received to Date:                 USD
  Funding Gap:                      USD

PREPARED BY:                  | DATE:
```

---

### FORMAT 3 — UN FLASH UPDATE (Rapid Onset, First 72 hrs)

When to use: immediately after a sudden-onset disaster. Speed over
completeness. Use when full data is not yet available.

```
FLASH UPDATE No. [X] — [Country]: [Disaster Type]
As of [Date / Time] [Timezone]

SUMMARY
  [3–5 sentence rapid overview]

IMPACT (Best Available Estimates — Unverified)
  Fatalities:           (Confirmed) /  (Estimated)
  Injured:
  Missing:
  Displaced:
  Affected Population:
  Area Affected:

IMMEDIATE RESPONSE
  Government:
  UN/OCHA:
  IFRC:
  Other Partners:

PRIORITY NEEDS
  1.
  2.
  3.

ACCESS & CONSTRAINTS

NEXT STEPS

NOTE: Data is preliminary and subject to revision.
Next Flash Update:                         Contact:
```

---

### FORMAT 4 — NDRRMC SITUATION REPORT (Philippines / SE Asia / Pacific)

When to use: Philippines and SE Asia / Pacific disasters — typhoons,
floods, earthquakes, volcanic eruptions. Updated every 8 hours during
active disaster phase.

```
NDRRMC UPDATE — SITUATION REPORT No. [X]
Re: [Disaster Type + Name/Code]
As of [Time] [Date]

INCIDENT DETAILS
  Incident Name:
  Incident No.:
  Operational Period:
  Report No.:    [ ] Initial   [ ] Update   [ ] Final
  Prepared By (PSC):
  Approved By (IC):

SITUATION OVERVIEW
  Policy Guidance (from Responsible Official):
  Incident Objectives (per ICS-202):

SIGNIFICANT EVENTS (this op period)
  What:
  Where:
  When:
  Who:
  Why/How:

CLUSTER ASSESSMENT STATUS
  Cluster          | Checked-In | Released | Balance
  WASH             |            |          |
  Food & Nutrition |            |          |
  Shelter & NFI    |            |          |
  Health           |            |          |
  Protection       |            |          |
  Education        |            |          |
  Camp Mgmt (CCCM) |            |          |

PUBLIC STATUS SUMMARY
                       | TOTAL | SINCE LAST REPORT |
  Dead                 |       |                   |
  Injured              |       |                   |
  Missing              |       |                   |
  Displaced/Evacuated  |       |                   |
  Inside Evac Centers  |       |                   |
  Outside Evac Centers |       |                   |

RESPONDER STATUS SUMMARY
  Dead:       Injured:       Missing:

AREAS AFFECTED
  Regions:
  Provinces:
  Cities/Municipalities:
  Barangays:

INFRASTRUCTURE DAMAGE
  Roads Impassable:
  Bridges Damaged:
  Power Outages:           areas /        households
  Water Supply Cut:        areas
  Structures Damaged:        Destroyed:

RESOURCE COMMITMENT
  Personnel Deployed:
  Vehicles/Boats:
  Relief Goods (est.):  PHP            / USD

COST OF DAMAGE ESTIMATE
  Infrastructure: PHP
  Agriculture:    PHP
  Total:          PHP            (USD            )

REMARKS

NEXT SITREP:        hrs / Date:
```

---

### FORMAT 5 — IFRC EMERGENCY OPERATIONS UPDATE (Red Cross / Red Crescent)

When to use: Red Cross / Red Crescent national society operations.
Updated weekly or per operational milestone. Published on the IFRC
Go platform.

```
EMERGENCY APPEAL / OPERATIONS UPDATE
[National Society] — [Country]: [Disaster]
Appeal No.: [XXXX-XX]   GLIDE No.: [XX-XXXX-XXX]
Period: [Date] to [Date]

SITUATION OVERVIEW
  [Narrative paragraph]

APPEAL COVERAGE (as of [Date])
  Appeal Target:        CHF / USD
  Contributions Received: CHF / USD
  Balance Remaining:    CHF / USD
  Coverage:             ___%

RED CROSS RESPONSE
  Health & Care:
  Shelter:
  WASH:
  Livelihoods:
  Disaster Risk Reduction:
  National Society Dev:

TARGET POPULATION
  Total Targeted:
  Reached to Date:

KEY ACHIEVEMENTS (this period)
  *
  *

CHALLENGES

NEXT STEPS

CONTACT:                | DATE:
```

---

### FORMAT 6 — EU ECHO FLASH (European Commission)

When to use: disasters affecting EU member states, EU overseas
territories, or EU-funded humanitarian responses globally. Issued
within 24 hours of onset.

```
EU ECHO FLASH — [Disaster Type] in [Country/Region]
Flash No.: [X]   Date: [dd/mm/yyyy]   Time: [HH:MM UTC]

OVERVIEW
  Event:
  Date of Onset:
  Country:
  Affected Area:
  Alert Level:      [ ] WATCH   [ ] WARNING   [ ] EMERGENCY

IMPACT
  Fatalities:        Injured:        Missing:
  Displaced:         Affected Population:
  Structures Damaged/Destroyed:
  Critical Infrastructure:

EU RESPONSE ACTIVATION
  ERCC Activation:   [ ] Yes   [ ] No
  Copernicus EMS:    [ ] Activated — Map Product:
  EU Civil Protection Mechanism: [ ] Activated
  UCPM Offers Received:

SITUATION NARRATIVE

NEEDS IDENTIFIED

EU FUNDING / HUMANITARIAN SUPPORT
  ECHO Funding Mobilized: EUR
  Partners Contracted:

NEXT UPDATE:           CONTACT:
```

---

## STEP 5 — OUTPUT RULES (apply to ALL formats)

1. Auto-populate every field from user input — do not leave required
   blocks blank.
2. Mark inferred or estimated values:
   `[INFERRED — verify before submission]`.
3. Use 24-hour time for all timestamps in ICS-209 and NDRRMC.
4. Use `dd/mm/yyyy` for OCHA, NDRRMC, IFRC, EU ECHO; `mm/dd/yyyy`
   for ICS-209.
5. Casualties must show both cumulative total AND "since last
   report" delta.
6. Significant Events must always cover 5W+1H (What, Where, When,
   Who, Why, How).
7. For Update reports: carry forward all prior data; only ask for
   changed fields.
8. If user provides a news article or scenario text, parse it
   directly — do not re-ask for data already present.
9. If a field is truly unknown and cannot be inferred, write
   `[UNKNOWN — to be confirmed]`.
10. Always emit valid JSON conforming to the Aegis A2UI surface
    schema first; the printable narrative is supplementary.

---

## STEP 6 — GLOBAL FORMAT COMPARISON REFERENCE

| FORMAT          | ORIGIN          | PHASE          | BEST FOR                  |
|-----------------|-----------------|----------------|---------------------------|
| ICS-209         | US FEMA / NIMS  | Operational    | US all-hazards response   |
| OCHA SitRep     | UN OCHA         | Day 3+         | International humanitarian|
| UN Flash Update | UN / OCHA       | First 72 hrs   | Rapid-onset disaster      |
| NDRRMC SitRep   | Philippines     | Every 8 hrs    | SE Asia / Pacific typhoons|
| IFRC Ops Update | Red Cross / IFRC| Weekly         | RC/RC relief operations   |
| EU ECHO Flash   | EU Commission   | First 24 hrs   | EU-linked disaster        |
| PDNA            | World Bank / UN | Post-disaster  | Recovery planning         |

To generate any format: "Generate an [FORMAT NAME] for [incident]".

---

## STEP 7 — REQUIRED FIELD QUICK REFERENCE

| Block/Field        | ICS-209 | OCHA SitRep | Flash Update | NDRRMC |
|--------------------|---------|-------------|--------------|--------|
| Incident Name      |   YES   |     YES     |     YES      |   YES  |
| Date/Time          |   YES   |     YES     |     YES      |   YES  |
| Report Version     |   YES   |     YES     |     YES      |   YES  |
| Incident Commander |   YES   | (lead agcy) | (lead agcy)  |   YES  |
| Situation Summary  |   YES   |     YES     |     YES      |   YES  |
| Casualties         |   YES   |     YES     |     YES      |   YES  |
| Resources          |   YES   | (by cluster)|   (brief)    |   YES  |
| Funding            | (costs) |     YES     | (if avail)   | (cost) |
| Prepared By / Auth |   YES   |     YES     |     YES      |   YES  |
| Gaps / Constraints |   opt   |     YES     |     YES      |   opt  |

---

## SAMPLE — FULLY POPULATED ICS-209 (Wildfire)

```
INCIDENT STATUS SUMMARY — ICS FORM 209
=========================================

BLOCK 1. INCIDENT NAME:     Redrock Canyon Fire
BLOCK 2. INCIDENT NUMBER:   CA-CNF-002459-2026
BLOCK 3. REPORT VERSION:    [X] Update #3
BLOCK 4. IC & AGENCY:       James R. Ortega — USFS
                            Deputy: Maria Chen — CAL FIRE
BLOCK 5. DATE/TIME:         05/10/2026  0600
BLOCK 6. OP PERIOD:         05/09/2026 1800 — 05/10/2026 0600
BLOCK 7. INCIDENT TYPE:     [X] Wildfire
BLOCK 8–12. LOCATION:       San Bernardino County, CA
                            34.3617°N, 117.6981°W — Angeles Natl Forest
BLOCK 14. SITUATION:        4,820 acres, 22% contained. Red Flag
                            Warning conditions (winds 35–50 mph, RH 8%,
                            92°F). 3 communities under mandatory evac.
BLOCK 15. SIG. EVENTS:      What: Eastern flank spotted across Line Alpha
                            Where: Section 16, 0.4 mi east of dozer line
                            When: 05/09/2026 2130 hrs
                            Who: Division E crews + air attack helicopter
                            How: 45 mph gust drove spot across line;
                                 retardant drop at 2145 controlled it.
BLOCK 16. PUBLIC:           Fatal: 0 | Injured: 3 | Evacuated: 4,700
BLOCK 17. RESPONDERS:       Fatal: 0 | Injured: 1 (minor burn, released)
BLOCK 18. PERSONNEL:        847 total assigned
BLOCK 20. STRUCTURES:       Threatened: 680 | Destroyed: 12 | Damaged: 4
BLOCK 21. AREA:             4,820 acres | 22% contained
BLOCK 23. OUTLOOK:          Red Flag continues through 1800. Winds 30–45
                            mph expected 1400 hrs. NE corner primary threat.
BLOCK 25. COST TO DATE:     $4,200,000
BLOCK 26. PROJECTED COST:   $18,500,000
BLOCK 28. PREPARED BY:      Sarah K. Yamamoto (SITL) — 05/10/2026 0600
BLOCK 29. APPROVED BY:      James R. Ortega (IC)    — 05/10/2026 0615
```
