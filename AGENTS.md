<claude-mem-context>
# Memory Context

# [aegis/aegis] recent context, 2026-05-03 10:40pm GMT+5:30

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (23,793t read) | 1,588,422t work | 99% savings

### Apr 28, 2026
S10 Fix remaining Dart lint errors in Aegis voice pipeline after Whisper→Gemma audio refactor (Apr 28 at 11:35 PM)
S9 Replace Whisper ONNX STT backend with Gemma 4 native audio capabilities in Aegis Flutter project (Apr 28 at 11:35 PM)
S11 Debug and fix silent audio drop in Gemma transcription pipeline — flutter_gemma 0.13.6 one-session-per-model constraint (Apr 28 at 11:40 PM)
### Apr 29, 2026
S12 Fix MarkPendingInputTokenAsProcessed (Status Code 5) LiteRT-LM JNI error in aegis Flutter audio transcription pipeline (Apr 29 at 12:19 PM)
S13 Fix MarkPendingInputTokenAsProcessed JNI error in Aegis Flutter — two-bug root cause: session close/recreate pattern and wrong WAV format for flutter_gemma (Apr 29 at 12:26 PM)
30 12:28p 🔵 llm_service.dart Re-read Shows Old Content After Edits — Possible Edit Persistence Issue
28 12:51p 🔴 LiteRT-LM JNI Error Fixed: Single Shared Session with Audio Modality
29 " 🔴 WAV Encoding Changed from IEEE Float32 to PCM Int16 for flutter_gemma
S14 Unblock most recent open PR for the project using GitHub integration (Apr 29 at 12:54 PM)
31 1:22p 🔵 Aegis Flutter Project Structure Identified
32 " 🔵 LLM Echo Bug: ASR Prompt Leaks Into Native Session History
33 " 🔵 Full Pipeline Traced: STT Uses Sherpa-ONNX, Not Gemma Audio Modality
34 " 🔵 flutter_gemma 0.13.6 Always Applies Thinking Filter to gemmaIt Models
35 1:24p 🔴 LLM Echo Bug Fixed: Anti-Echo Prompt Wrapper and Response Scrubber Added
36 " 🔄 LlmService Cleanup: Removed Unused Variables from Echo-Scrubber
38 " 🔵 System Flutter SDK Incompatible With Project; FVM Required for All Commands
37 " 🔵 Flutter SDK Cache Lock File Permission Error
39 1:26p 🔵 FVM Flutter Analyze Succeeded: 43 Compile Errors in Patched llm_service.dart
40 " 🔵 STT Returning AI Refusal Text as Transcript — New Root Cause for Echo-Like Behavior
41 4:31p 🔵 SttService Architecture: VAD + Gemma 4 Transcription via Injected Callback — Refusal Text Not Filtered
42 4:32p 🔴 ASR Refusal Filter + Session Cleanup Added to LlmService._transcribeOnce
43 " 🔵 _asrRefusalPattern Still Has Invalid RegExp Syntax — Inline (?is) Flags Not Supported in Dart
44 4:33p 🔴 _asrRefusalPattern RegExp Fixed: Inline Flags Replaced with Named Parameters — llm_service.dart Now Clean
### May 2, 2026
45 2:45p 🔴 FunctionGemma 30s Watchdog Timeout Causes Emergency Alerts to Be Dismissed
46 2:47p 🔵 Codex CLI Not Installed in Aegis Project Environment
S15 Debugging FunctionGemma on-device inference timeout causing emergency alerts to be dismissed in Aegis Android app (May 2 at 2:47 PM)
47 " 🔵 LiteRT-LM SamplerConfig is per-Conversation, not per-Engine in flutter_gemma 0.13.6
48 2:49p 🔵 LiteRT-LM maxTokens ceiling confirmed at Engine init level; topK ceiling is native-binary-only
49 " 🔵 LiteRT-LM native Android library version confirmed as 0.10.0
50 " 🔵 litertlm-android-0.10.0 JAR contains native EngineConfig.class confirming engine-level config exists
51 " 🔵 Native litertlm EngineConfig has NO topK field — only maxNumTokens is an engine-level ceiling
52 2:51p 🔵 SamplerConfig.class bytecode confirms topK is per-conversation with validation; no max_top_k exists anywhere in litertlm-0.10.0
53 " 🔵 Complete litertlm-android-0.10.0 public API surface enumerated; Session.class separate from Conversation.class
54 " 🔵 litertlm-android-0.10.0 AAR structure: JVM bytecode in jars/ but native engine in jni/ .so files
55 2:53p 🔵 max_top_k confirmed in liblitertlm_jni.so native binary — topK ceiling bug is real
56 " 🔵 liblitertlm_jni.so embeds LLGuidance constrained-decoding engine; max_top_k is a config key in that subsystem
57 " 🔵 max_top_k is a core LiteRT backend config field alongside sequence_batch_size and clear_kv_cache_before_prefill
58 " 🔵 litertlm source path confirmed as third_party/odml/litert_lm in Google's internal monorepo
59 " 🔵 FunctionRouter uses LlmService.oneShot() with tight sampling for structured function-call output
61 " 🔵 flutter_gemma-0.13.6 has its own function_call_parser.dart but Aegis uses a custom implementation
63 2:54p 🔵 Cyclone test crash: SIGSEGV from concurrent oneShot sessions + pad-flood output
64 " 🔴 LlmService: serialize oneShot calls via _oneShotChain promise chain to prevent SIGSEGV
60 " 🔵 FunctionCallParser intentionally lenient to handle FunctionGemma 270M quirks including double-encoded JSON arguments
62 2:55p 🔵 flutter_gemma-0.13.6 createSession() and createChat() default to topK=1 (greedy) — the root cause of the max_top_k ceiling bug
### May 3, 2026
65 2:45p 🔵 FunctionGemma 270M pad-flood persists on real inference after SIGSEGV fixes
66 3:17p ⚖️ FunctionGemma 270M Pad-Flood Fix Strategy — Double-Wrap Root Cause Hypothesis
67 " 🔵 LiteRT-LM Android Backend Confirmed to Double-Wrap FunctionGemma Prompts
68 3:18p 🔵 LiteRT-LM 0.10.0 AAR Has No Chat Template Disable Flag
69 " 🔵 LiteRT-LM Conversation.sendMessage(Contents) Bytecode Confirms Auto-User-Role Wrapping
70 " 🔵 LlmService Already Has routerOneShot Implementation; MobileSession Still Calls transformToChatPrompt
71 " 🔵 transformToChatPrompt Returns Raw Text for LiteRT-LM on Android — But InferenceChat Already Added Chat Markers to Text
72 8:46p ⚖️ FunctionGemma pad-flood fix strategy defined for Aegis Android
73 " 🔵 LiteRT-LM Conversation API auto-applies chat template; double-wrap confirmed
74 " 🔵 LlmService._install() hardcodes ModelType.gemmaIt for all packs including router
75 " 🔴 Fixed FunctionGemma pad-flood by eliminating double chat-template wrapping
76 8:52p 🔵 FunctionGemma 270M Pad-Flood Root Cause: Double Chat-Template Wrapping on Android
77 " ⚖️ Fix Strategy: Prefer Direct session Creation Bypassing flutter_gemma Chat Wrapping

Access 1588k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>