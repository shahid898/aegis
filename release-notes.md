## Aegis v0.1.0

Offline-first AI emergency assistant. Android only. Runs entirely on-device — Gemma 4 E2B IT for chat / ASR / vision / tool calls, Piper for TTS, sherpa-onnx for STT, CARTO Voyager tiles via FMTC for the offline map.

### Hardware requirements

- **Android 8+ (API 24+)**, **arm64-v8a** only (modern 64-bit ARM — every phone shipped from ~2017 onwards)
- ~4 GB free storage for the model + voice + map packs
- 6 GB+ RAM recommended; Gemma 4 vision encode requires a contiguous ~50 MB OpenCL buffer

Devices verified working:

| Device | GPU | Status |
|---|---|---|
| Pixel 6 / 7 / 8 | Mali-G710+ / Tensor | ✅ |
| OnePlus 11, Xiaomi 13, Samsung S22+ (Snapdragon) | Adreno 730+ | ✅ |
| Samsung Galaxy Note 10 / S10 (Exynos 9820/9825) | Mali-G76 | ⚠️ visible auto-restart on chat → triage flows (built-in `WedgeRecoveryStore` persists intake + replays after relaunch). See README for the full caveat. |

### Installing the APK

**1. Download** `app-arm64-v8a-release.apk` (226 MB) to the phone.

**2. Open** the file. Android asks to grant *"Install unknown apps"* to your browser/file manager → toggle ON for that app → tap **Install**.

**3. Play Protect** then shows *"App blocked to protect your device"* with only an **OK** button. This is normal for any sideloaded APK that Google has never seen before — not a malware indicator.

Two ways past it:

- **Pause Play Protect briefly (no cable):** Play Store → profile icon → Play Protect → gear icon → toggle off *"Scan apps with Play Protect"* → retry install → toggle back ON afterwards.
- **Use `adb install` (skips Play Protect):**
  ```
  adb install app-arm64-v8a-release.apk
  ```
  Requires USB debugging — Settings → About phone → tap *Build number* 7× → Settings → Developer options → USB debugging ON.

Aegis is fully open-source — clone the repo and run `fvm flutter build apk --release` if you want to verify the binary yourself.

### First launch

Onboarding downloads the model pack and seeds the offline place database for the region you pick. Budget **5-10 minutes** on Wi-Fi (faster on a fast connection, slower on flaky 4G). After that, the app runs entirely offline — only the one-time onboarding seeds need the network.

### What's in this release

- One-model architecture — Gemma 4 E2B IT handles multilingual chat, on-device ASR, vision (damage photos), and native function calling
- Two function-calling tools: `render_triage_report` (FEMA ICS-209 / OCHA SITREP / HAZUS) and `render_map_view` (offline nearby-places map)
- Cell-broadcast / WEA / SMS alert pipeline with full-screen siren + spoken briefing in the user's language
- Offline POI database (OSM via Overpass) + 25 km CARTO tile cache (FMTC)
- Skills-as-markdown registry so partner orgs can ship new capabilities without recompiling
- 140-language locale catalog, EN + HI shipped with ARB files today, scaffolded for the rest

### Known limitations

- 32-bit ARM (armeabi-v7a) APK omitted intentionally — Gemma 4 E2B needs 4 GB+ RAM, which armv7-era hardware does not have
- iOS port is in progress
- Cell-broadcast (WEA / CMAS / Presidential) reception requires platform-signature permission and only works on system-installed builds. SMS-borne alerts work fine on the sideloaded APK. See "Platform Caveats — Cell-Broadcast & WEA" in the README.
- Mali-G76 GPU (Samsung Exynos Note 10 / S10) wedges on chat → triage; the auto-restart fallback handles it but the relaunch is visible. See "Platform Caveats — Mali G76 GPU" in the README.

### Source verification

Every factual claim in the README and writeup is sourced in [`REFERENCES.md`](https://github.com/shahid898/aegis/blob/main/REFERENCES.md).
