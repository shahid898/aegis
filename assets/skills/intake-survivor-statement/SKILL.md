---
name: intake-survivor-statement
description: Capture, transcribe, and translate a survivor's verbal
  statement into a triage-ready record. Apply START triage if the
  statement describes a casualty. Use when a responder records a
  survivor speaking, when a survivor self-reports trapped or injured
  family members, or as a sub-step of generate-ics-209.
---

# Intake Survivor Statement

## When this skill fires

Triage Mode: responder records a survivor (or a witness) describing
a person who is missing, trapped, or injured. May also fire from
Ask Mode if a survivor self-reports their own situation.

## Instructions

For each statement:

1. **Transcribe in source language.** Preserve the survivor's
   actual words.
2. **Translate to English** for the responder-facing field. Mark
   the source language explicitly (`language: "Tagalog"`).
3. **Extract entities.**
   * Demographics — sex, approximate age, distinguishing features,
     mobility aids.
   * Status — `ALIVE_SAFE`, `ALIVE_INJURED`, `ALIVE_TRAPPED`,
     `ALIVE_UNKNOWN`, `MISSING`, `DECEASED`.
   * Location — relative ("under the rubble at the corner store")
     or absolute (GPS, address).
4. **Apply START triage** if status indicates injury:
   * `RED` (immediate) — life-threatening, treatable on-site.
   * `YELLOW` (delayed) — serious but stable.
   * `GREEN` (walking wounded) — minor injuries.
   * `BLACK` (expectant / deceased).
5. Emit one `casualtyCard` per person mentioned, with demographics,
   status, language, translated statement, and triage colour.

## Output

`a2ui_messages` containing one or more `casualtyCard` components.
Cross-references with mesh beacons in incident context are handled
by the `match-mesh-beacon` skill, not here.
