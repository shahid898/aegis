import 'package:flutter/foundation.dart';

/// One unit of work fed to Gemma 4's unified crisis pipeline. The same
/// shape works for Ask Mode (survivor) and Triage Mode (responder) —
/// the only thing that differs at the call site is which fields are
/// populated and which prompt template gets selected at the LLM
/// boundary.
@immutable
class TriageInput {
  const TriageInput({
    required this.userText,
    this.audioWav,
    this.imageJpeg,
    this.gpsContext,
    this.incidentLog = const <String>[],
    this.activeRegionPackId,
    this.requestId,
  });

  /// What the user said (already transcribed if it came from audio)
  /// or typed. Required even when audio/image dominate — it's how the
  /// model knows what the responder *wants*.
  final String userText;

  /// 16kHz mono int16 PCM WAV. Optional — present when the responder
  /// recorded a survivor statement and needs in-the-loop transcription
  /// + intake. The pipeline uses this for `intake-survivor-statement`.
  final Uint8List? audioWav;

  /// JPEG bytes already scaled to 512px on the longest edge. Optional
  /// — present when the responder photographed damage. Used by
  /// `grade-damage-hazus`.
  final Uint8List? imageJpeg;

  /// One-line summary of where the user is, in the form
  /// `lat=20.8783, lng=-156.6825 (±15m)` or similar. Skip if we have
  /// no GPS fix — better to omit than to lie.
  final String? gpsContext;

  /// Recent Isar entries scoped to this incident, oldest-first. The
  /// pipeline budgets up to 100K tokens for these; the caller is
  /// responsible for truncation.
  final List<String> incidentLog;

  /// Active region pack id (eg. `india-maharashtra-2026Q1`). The pack
  /// supplies shelter / route / protocol corpus that grounds the
  /// model's reply. The system prompt cites the pack so partner orgs
  /// know which version generated the report.
  final String? activeRegionPackId;

  /// Optional client-side correlation id surfaced in the
  /// `thinking_trace` so we can debug end-to-end after a shipment.
  final String? requestId;

  bool get hasAudio => audioWav != null && audioWav!.isNotEmpty;
  bool get hasImage => imageJpeg != null && imageJpeg!.isNotEmpty;
}
