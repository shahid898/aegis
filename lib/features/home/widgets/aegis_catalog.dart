import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../cubit/assistant_cubit.dart';

/// The Aegis catalog ID. Must be cited verbatim in the
/// `createSurface.catalogId` field by the agent. Reverse-domain so it
/// won't collide with other catalogs a host app might mount.
const String aegisCatalogId = 'ai.aegis.crisis_loop.v1';

/// The 9 cards Aegis uses to render every triage / ask surface. We
/// expose them individually so a hosting app can mount only the ones
/// it needs, but the canonical bundle is [aegisCatalog] which mixes
/// them with the basic A2UI catalog (Column, Row, Text, etc.).
///
/// **Why exactly nine.** Damage, casualty, beacon, resource, confirm,
/// thinking-trace, map, go-bag, shelter — these cover every real
/// disaster surface we can imagine. Variation lives in the data and
/// composition, not in the widget vocabulary. Add a 10th only when a
/// fundamentally new information shape (eg. a chemical-plume diagram)
/// genuinely won't fit any existing card.
final CatalogItem damageCard = _buildCard(
  name: 'DamageCard',
  description: 'FEMA HAZUS damage classification produced by the '
      'grade-damage-hazus skill. One per photographed scene.',
  schema: S.object(
    description: 'A damage assessment for one photographed scene.',
    properties: {
      'category': S.integer(
        description: 'HAZUS category 0-4 (None / Slight / Moderate / Extensive / Complete).',
      ),
      'fema_scale': S.string(
        description: 'HAZUS_NONE | HAZUS_SLIGHT | HAZUS_MODERATE | HAZUS_EXTENSIVE | HAZUS_COMPLETE',
      ),
      'description': S.string(description: 'One-line damage description.'),
      'photo_ref': S.string(description: 'Reference to the source photo.'),
    },
    required: ['category', 'fema_scale'],
  ),
  builder: (data, ctx) {
    final category = (data['category'] as num?)?.toInt() ?? 0;
    final scale = (data['fema_scale'] as String?) ?? 'HAZUS_NONE';
    final description = (data['description'] as String?) ?? '';
    final photoRef = (data['photo_ref'] as String?) ?? '';
    final color = _hazusColor(category);
    return _AegisCard(
      icon: Icons.broken_image_outlined,
      iconColor: color,
      title: 'Damage — $scale',
      subtitle: 'HAZUS Category $category',
      body: Text(
        description.isEmpty ? '(no description)' : description,
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      footer: photoRef.isEmpty
          ? null
          : Text('Photo: $photoRef',
              style: Theme.of(ctx).textTheme.bodySmall),
      accentColor: color,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "DamageCard",
    "category": 2,
    "fema_scale": "HAZUS_MODERATE",
    "description": "Partial structural collapse, void spaces visible",
    "photo_ref": "scene_001.jpg"
  }
]''',
);

final CatalogItem casualtyCard = _buildCard(
  name: 'CasualtyCard',
  description: 'A single casualty record with START triage colour, '
      'demographics, and translated statement.',
  schema: S.object(
    description: 'One person mentioned in a survivor / responder statement.',
    properties: {
      'demographics': S.string(description: 'Sex, age, distinguishing features, mobility aids.'),
      'status': S.string(
        description: 'ALIVE_SAFE | ALIVE_INJURED | ALIVE_TRAPPED | ALIVE_UNKNOWN | MISSING | DECEASED',
      ),
      'language': S.string(description: 'Source language of the statement.'),
      'translated_statement': S.string(description: 'English translation of what the person said.'),
      'triage_color': S.string(description: 'RED | YELLOW | GREEN | BLACK | UNTAGGED'),
    },
    required: ['demographics', 'status', 'triage_color'],
  ),
  builder: (data, ctx) {
    final demographics = (data['demographics'] as String?) ?? 'Unknown';
    final status = (data['status'] as String?) ?? 'UNKNOWN';
    final language = (data['language'] as String?) ?? '';
    final statement = (data['translated_statement'] as String?) ?? '';
    final triage = (data['triage_color'] as String?) ?? 'UNTAGGED';
    final color = _triageColor(triage);
    return _AegisCard(
      icon: Icons.person_outline,
      iconColor: color,
      title: 'Casualty — $demographics',
      subtitle: 'Status: $status   ·   Triage: $triage',
      body: Text(
        statement.isEmpty ? '(no statement captured)' : '"$statement"',
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      footer: language.isEmpty
          ? null
          : Text('Source language: $language',
              style: Theme.of(ctx).textTheme.bodySmall),
      accentColor: color,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "CasualtyCard",
    "demographics": "Female, ~70, wheelchair",
    "status": "ALIVE_TRAPPED",
    "language": "Tagalog",
    "translated_statement": "My mother is under the rubble, she is conscious",
    "triage_color": "YELLOW"
  }
]''',
);

final CatalogItem beaconMatchCard = _buildCard(
  name: 'BeaconMatchCard',
  description: 'Cross-reference between a fresh statement and an older '
      'mesh beacon in the incident log. Confidence ≥ 0.70.',
  schema: S.object(
    description: 'A mesh-beacon match from the match-mesh-beacon skill.',
    properties: {
      'matched_id': S.string(description: 'The beacon id that matched.'),
      'confidence': S.number(description: '0.0 to 1.0 match confidence.'),
      'beacon_content': S.string(description: 'Original beacon content, verbatim.'),
    },
    required: ['matched_id', 'confidence'],
  ),
  builder: (data, ctx) {
    final id = (data['matched_id'] as String?) ?? 'unknown';
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
    final content = (data['beacon_content'] as String?) ?? '';
    final pct = (confidence * 100).clamp(0, 100).toStringAsFixed(0);
    return _AegisCard(
      icon: Icons.link,
      iconColor: Colors.blueAccent,
      title: 'Mesh Beacon Match',
      subtitle: '$id   ·   Confidence $pct%',
      body: Text(
        content.isEmpty ? '(no beacon content)' : content,
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      accentColor: Colors.blueAccent,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "BeaconMatchCard",
    "matched_id": "aegis-mesh-4a2f",
    "confidence": 0.92,
    "beacon_content": "Josefina Ramos, alive, wheelchair, heading Civic Center"
  }
]''',
);

final CatalogItem resourceRequestCard = _buildCard(
  name: 'ResourceRequestCard',
  description: 'Recommended SAR / medical / logistics resources based on '
      'the worst HAZUS level and highest triage colour on the scene.',
  schema: S.object(
    description: 'A resource recommendation.',
    properties: {
      'recommended_action': S.string(description: 'What to dispatch and why.'),
      'estimated_eta': S.string(description: 'Human-readable ETA, e.g. "40 minutes".'),
    },
    required: ['recommended_action'],
  ),
  builder: (data, ctx) {
    final action = (data['recommended_action'] as String?) ?? '';
    final eta = (data['estimated_eta'] as String?) ?? '';
    return _AegisCard(
      icon: Icons.local_shipping_outlined,
      iconColor: Colors.deepPurple,
      title: 'Resource Request',
      subtitle: eta.isEmpty ? null : 'ETA: $eta',
      body: Text(
        action.isEmpty ? '(no action specified)' : action,
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      accentColor: Colors.deepPurple,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "ResourceRequestCard",
    "recommended_action": "Dispatch urban SAR with void-space equipment",
    "estimated_eta": "40 minutes"
  }
]''',
);

/// Triage intake — the entry point for an explicit triage report.
/// Rendered when the user taps "Start triage" in the home header
/// (the cubit pushes a synthetic createSurface + updateComponents
/// containing this card; no LLM round-trip).
///
/// Three input rails — photo, audio, text — and a Submit action that
/// hands the gathered evidence to the LLM for analysis. We dispatch
/// distinct action names so the cubit can route to the right device
/// API (camera, recorder, text sheet) without parsing strings.
final CatalogItem triageIntakeCard = CatalogItem(
  name: 'TriageIntakeCard',
  dataSchema: S.object(
    description: 'The triage intake form. Lets the user attach a '
        'photo, voice note, and/or text description before the agent '
        'analyses the evidence.',
    properties: {
      'prompt': S.string(
        description: 'A short instruction shown above the input rails.',
      ),
      'has_photo': S.boolean(
        description: 'True if a photo has been attached to this intake.',
      ),
      'has_audio': S.boolean(
        description: 'True if a voice note has been recorded.',
      ),
      'text_value': S.string(
        description: 'Current text description. Echoed back from the cubit '
            'after the user types in the modal.',
      ),
    },
  ),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "TriageIntakeCard",
    "prompt": "Attach a photo, voice note, or describe the scene."
  }
]''',
  ],
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, Object?>;
    final prompt = (data['prompt'] as String?) ??
        'Attach a photo, voice note, or describe the scene.';
    final hasPhoto = (data['has_photo'] as bool?) ?? false;
    final hasAudio = (data['has_audio'] as bool?) ?? false;
    final textValue = (data['text_value'] as String?) ?? '';
    final ready = hasPhoto || hasAudio || textValue.trim().isNotEmpty;

    void dispatch(String name) {
      itemContext.dispatchEvent(
        UserActionEvent(name: name, sourceComponentId: itemContext.id),
      );
    }

    return _AegisCard(
      icon: Icons.medical_information_outlined,
      iconColor: Colors.deepPurple,
      title: 'Triage intake',
      subtitle: prompt,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _IntakeChip(
                  icon: Icons.photo_camera_outlined,
                  label: hasPhoto ? 'Photo ✓' : 'Photo',
                  onTap: () => dispatch('intake_photo'),
                  attached: hasPhoto,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IntakeChip(
                  icon: Icons.mic_none_outlined,
                  label: hasAudio ? 'Voice ✓' : 'Voice',
                  onTap: () => dispatch('intake_audio'),
                  attached: hasAudio,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IntakeChip(
                  icon: Icons.edit_note_outlined,
                  label: textValue.isEmpty ? 'Text' : 'Text ✓',
                  onTap: () => dispatch('intake_text'),
                  attached: textValue.isNotEmpty,
                ),
              ),
            ],
          ),
          if (textValue.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                textValue,
                style: Theme.of(itemContext.buildContext).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ready ? () => dispatch('intake_submit') : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Analyse with Aegis'),
          ),
        ],
      ),
      accentColor: Colors.deepPurple,
    );
  },
);

class _IntakeChip extends StatelessWidget {
  const _IntakeChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.attached,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool attached;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: attached
              ? Colors.deepPurple.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: attached
                ? Colors.deepPurple
                : Colors.deepPurple.withValues(alpha: 0.30),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22,
                color: attached ? Colors.deepPurple : Colors.deepPurple),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: attached ? FontWeight.w600 : FontWeight.w400,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirm / Reject bar. Emits `UserActionEvent`s with `name: "confirm"`
/// or `name: "reject"` — [TriageCubit] listens on
/// [SurfaceController.onSubmit] and routes accordingly.
final CatalogItem confirmActionBar = CatalogItem(
  name: 'ConfirmActionBar',
  dataSchema: S.object(
    description: 'A two-button bar for verifying a generated surface.',
    properties: {
      'primary_action': S.string(description: 'Label for the Confirm button.'),
      'secondary_action': S.string(description: 'Label for the Edit / Reject button.'),
    },
  ),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "ConfirmActionBar",
    "primary_action": "Confirm & queue for sync",
    "secondary_action": "Edit report"
  }
]''',
  ],
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, Object?>;
    final primary = (data['primary_action'] as String?) ?? 'Confirm';
    final secondary = (data['secondary_action'] as String?) ?? 'Edit';
    return Card(
      elevation: 0,
      color: Theme.of(itemContext.buildContext).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => itemContext.dispatchEvent(
                  UserActionEvent(
                    name: 'reject',
                    sourceComponentId: itemContext.id,
                  ),
                ),
                child: Text(secondary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => itemContext.dispatchEvent(
                  UserActionEvent(
                    name: 'confirm',
                    sourceComponentId: itemContext.id,
                  ),
                ),
                child: Text(primary),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

/// Reasoning-trace drawer — collapsed by default. Tapping reveals the
/// model's reasoning chain. The verification layer that makes
/// generated UI defensible.
final CatalogItem thinkingTraceDrawer = CatalogItem(
  name: 'ThinkingTraceDrawer',
  dataSchema: S.object(
    description: 'A collapsible drawer that exposes the agent\'s '
        'reasoning chain to the user.',
    properties: {
      'trace': S.string(description: 'The reasoning chain, free-form text.'),
    },
    required: ['trace'],
  ),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "ThinkingTraceDrawer",
    "trace": "Photo shows Category 2 damage. Statement matches beacon aegis-mesh-4a2f. START = yellow."
  }
]''',
  ],
  widgetBuilder: (itemContext) {
    final data = itemContext.data as Map<String, Object?>;
    final trace = (data['trace'] as String?) ?? '';
    return _ThinkingTraceDrawerWidget(trace: trace);
  },
);

class _ThinkingTraceDrawerWidget extends StatefulWidget {
  const _ThinkingTraceDrawerWidget({required this.trace});

  final String trace;

  @override
  State<_ThinkingTraceDrawerWidget> createState() =>
      _ThinkingTraceDrawerWidgetState();
}

class _ThinkingTraceDrawerWidgetState
    extends State<_ThinkingTraceDrawerWidget> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Reasoning'),
            subtitle: Text(_open ? 'Tap to hide' : 'Tap to inspect'),
            trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.trace.isEmpty ? '(no trace recorded)' : widget.trace,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

final CatalogItem mapFragment = _buildCard(
  name: 'MapFragment',
  description: 'A lightweight map placeholder card. Caption + lat/lng. '
      'The full map widget lives outside the surface for performance.',
  schema: S.object(
    description: 'A map fragment card.',
    properties: {
      'caption': S.string(description: 'A short label for the fragment.'),
      'lat': S.number(description: 'Latitude.'),
      'lng': S.number(description: 'Longitude.'),
    },
  ),
  builder: (data, ctx) {
    final caption = (data['caption'] as String?) ?? 'Map fragment';
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    return _AegisCard(
      icon: Icons.map_outlined,
      iconColor: Colors.teal,
      title: caption,
      subtitle: lat == null || lng == null
          ? null
          : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      body: Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.location_on_outlined,
          size: 36,
          color: Colors.teal,
        ),
      ),
      accentColor: Colors.teal,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "MapFragment",
    "caption": "Civic Center",
    "lat": 20.8783,
    "lng": -156.6825
  }
]''',
);

final CatalogItem goBagChecklist = _buildCard(
  name: 'GoBagChecklist',
  description: 'Personalised pre-disaster go-bag list. 6-10 prioritised items.',
  schema: S.object(
    description: 'A checklist of items to bring.',
    properties: {
      'items': S.list(
        description: 'List of go-bag item names.',
        items: S.string(),
      ),
    },
    required: ['items'],
  ),
  builder: (data, ctx) {
    final items = _stringList(data['items']);
    return _AegisCard(
      icon: Icons.checklist_outlined,
      iconColor: Colors.indigo,
      title: 'Go-bag checklist',
      subtitle: '${items.length} item${items.length == 1 ? '' : 's'}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_box_outline_blank, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
      accentColor: Colors.indigo,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "GoBagChecklist",
    "items": [
      "Water — 3 litres",
      "Phone charger + battery pack",
      "Medication for 72 hours",
      "Flashlight + spare batteries",
      "Whistle",
      "Cash in small bills"
    ]
  }
]''',
);

final CatalogItem shelterPreviewCard = _buildCard(
  name: 'ShelterPreviewCard',
  description: 'Closest open shelter with walking distance + accessibility flags.',
  schema: S.object(
    description: 'A shelter preview.',
    properties: {
      'name': S.string(description: 'Shelter name.'),
      'distance': S.string(description: 'Walking distance, eg. "1.2 km".'),
      'address': S.string(description: 'Postal address or landmark.'),
      'accessibility': S.string(description: 'Accessibility features.'),
    },
    required: ['name'],
  ),
  builder: (data, ctx) {
    final name = (data['name'] as String?) ?? 'Shelter';
    final distance = (data['distance'] as String?) ?? '';
    final address = (data['address'] as String?) ?? '';
    final accessibility = (data['accessibility'] as String?) ?? '';
    return _AegisCard(
      icon: Icons.home_work_outlined,
      iconColor: Colors.teal,
      title: name,
      subtitle: distance.isEmpty ? null : distance,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (address.isNotEmpty) Text(address),
          if (accessibility.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Accessibility: $accessibility',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      accentColor: Colors.teal,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "ShelterPreviewCard",
    "name": "Civic Center Emergency Shelter",
    "distance": "1.2 km",
    "address": "200 South High Street",
    "accessibility": "wheelchair-accessible, ASL volunteers on site"
  }
]''',
);

/// Long-form incident report card. Used by the
/// `disaster-report-generator` skill to surface the FILLED template
/// body (ICS-209, OCHA SitRep, UN Flash Update, NDRRMC, IFRC, EU
/// ECHO, PDNA) verbatim — the smaller domain cards summarise; this
/// one carries the printable narrative the responder hands off.
///
/// Renders the body in a scrollable monospace block so the report's
/// indentation and table layout survive intact, plus a "Copy" button
/// so the responder can paste it into the agency's intake system
/// without retyping. Title shows the format + report number; subtitle
/// shows incident name and date/time stamp.
final CatalogItem incidentReportCard = _buildCard(
  name: 'IncidentReportCard',
  description: 'Long-form filled incident report (ICS-209, OCHA SitRep, '
      'UN Flash Update, NDRRMC, IFRC, EU ECHO, PDNA). Emitted by the '
      'disaster-report-generator skill alongside the summary cards.',
  schema: S.object(
    description: 'A printable incident report body in a named format.',
    properties: {
      'format': S.string(
        description: 'ICS-209 | OCHA_SITREP | UN_FLASH_UPDATE | NDRRMC | '
            'IFRC_OPS_UPDATE | EU_ECHO_FLASH | PDNA',
      ),
      'title': S.string(description: 'Incident name as shown in Block 1 / header.'),
      'report_number': S.string(description: 'Report version, eg. "Update #3" or "Flash No. 2".'),
      'prepared_at': S.string(description: 'ISO-8601 timestamp the report was drafted.'),
      'prepared_by': S.string(description: 'Author + agency, eg. "S. Yamamoto (SITL) — USFS".'),
      'gps': S.string(
        description: 'GPS coordinates the report was captured at, '
            'verbatim from the user prompt\'s `gps=` line, eg. '
            '`lat=19.20337, lng=72.82770 (±15m)`. Empty if no GPS fix.',
      ),
      'body': S.string(
        description: 'Full filled report text, preserving line breaks and '
            'indentation. Up to ~4 KB. Use placeholders like '
            '"[INFERRED — verify before submission]" for fields the '
            'responder must confirm.',
      ),
    },
    required: ['format', 'body'],
  ),
  builder: (data, ctx) {
    final format = (data['format'] as String?) ?? 'REPORT';
    final title = (data['title'] as String?) ?? '';
    final reportNumber = (data['report_number'] as String?) ?? '';
    final preparedAt = (data['prepared_at'] as String?) ?? '';
    final preparedBy = (data['prepared_by'] as String?) ?? '';
    final gps = (data['gps'] as String?) ?? '';
    final body = (data['body'] as String?) ?? '';

    final headerLine = [
      if (title.isNotEmpty) title,
      if (reportNumber.isNotEmpty) reportNumber,
    ].join(' — ');
    final preparedAtPretty = _humanReadableTimestamp(preparedAt);
    final gpsPretty = _humanReadableGps(gps);
    final footerLine = [
      if (preparedBy.isNotEmpty) preparedBy,
      if (preparedAtPretty.isNotEmpty) preparedAtPretty,
    ].join(' · ');

    return _AegisCard(
      icon: Icons.description_outlined,
      iconColor: Colors.indigo,
      title: format,
      subtitle: headerLine.isEmpty ? null : headerLine,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EvidenceBlock(),
          if (preparedAtPretty.isNotEmpty || gpsPretty.isNotEmpty)
            _ReportMetadataStrip(
              capturedAt: preparedAtPretty,
              location: gpsPretty,
            ),
          if (body.contains('[INFERRED') || body.contains('[UNKNOWN'))
            const _PlaceholderLegend(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.indigo.withValues(alpha: 0.18),
                ),
              ),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: _IncidentReportBody(body: body),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: body.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: body));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Report copied to clipboard'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
      footer: footerLine.isEmpty
          ? null
          : Text(footerLine,
              style: Theme.of(ctx).textTheme.bodySmall),
      accentColor: Colors.indigo,
    );
  },
  exampleJson: '''
[
  {
    "id": "root",
    "component": "IncidentReportCard",
    "format": "ICS-209",
    "title": "Redrock Canyon Fire",
    "report_number": "Update #3",
    "prepared_at": "2026-05-10T06:00:00Z",
    "prepared_by": "S. Yamamoto (SITL) — USFS",
    "body": "INCIDENT STATUS SUMMARY — ICS FORM 209\\nBLOCK 1. INCIDENT NAME: Redrock Canyon Fire\\nBLOCK 7. INCIDENT TYPE: [X] Wildfire\\nBLOCK 14. SITUATION: 4,820 acres, 22% contained..."
  }
]''',
);

/// The full Aegis catalog — basic A2UI items (Column, Row, Text, etc.)
/// plus the 9 disaster-domain cards above. The agent picks ids from
/// either set when composing a surface.
///
/// Hosting notes:
///   * `catalogId` is set to [aegisCatalogId] so the agent knows what
///     to cite in `createSurface.catalogId`.
///   * Aegis-specific guidance is appended to the basic catalog's
///     system prompt fragments via [_aegisCatalogRules]. The
///     `Conversation` / system-prompt builder concatenates these
///     before sending the user turn to Gemma 4.
Catalog buildAegisCatalog() {
  return BasicCatalogItems.asCatalog(
    systemPromptFragments: [_aegisCatalogRules],
  ).copyWith(
    newItems: [
      triageIntakeCard,
      damageCard,
      casualtyCard,
      beaconMatchCard,
      resourceRequestCard,
      confirmActionBar,
      thinkingTraceDrawer,
      mapFragment,
      goBagChecklist,
      shelterPreviewCard,
      incidentReportCard,
    ],
    catalogId: aegisCatalogId,
  );
}

/// Aegis-specific rules appended to the basic catalog's system-prompt
/// fragments. Picks up where the basic-catalog rules leave off — the
/// model already knows about Column/Row/Text from the basic rules.
const String _aegisCatalogRules = r'''
**AEGIS CRISIS-LOOP RULES:**

When the captured evidence is a disaster-response interaction (Ask
Mode for survivors, Triage Mode for responders), prefer the Aegis
domain cards over generic Text widgets:

* `DamageCard` for FEMA HAZUS damage grading from a photo.
* `CasualtyCard` for a person mentioned in a survivor / responder
  statement, with START triage colour.
* `BeaconMatchCard` only when confidence ≥ 0.70.
* `ResourceRequestCard` whenever HAZUS ≥ 2 or any RED/YELLOW casualty
  is present.
* `ConfirmActionBar` is REQUIRED on every Triage Mode surface — the
  responder must explicitly confirm before the report is queued.
* `ThinkingTraceDrawer` is RECOMMENDED on every Triage Mode surface
  so the responder can verify the reasoning before confirming.
* `MapFragment`, `GoBagChecklist`, `ShelterPreviewCard` for Ask Mode
  briefings.

**Surface composition.** Wrap the whole surface in a Column with
id "root". Children are referenced by id. Use the basic `Text` widget
for headings; do NOT invent disaster-domain cards from Text alone.

**Triage priority bubble-up.** The highest START colour across all
CasualtyCards drives the surface's overall priority. Mention that
priority in the spoken response; render it via the title text on the
root Column if needed.
''';

// ---- helpers ---------------------------------------------------------------

typedef _CardWidgetBuilder =
    Widget Function(Map<String, Object?> data, BuildContext context);

/// Helper for the leaf cards that don't need to dispatch events. Wraps
/// the verbose CatalogItem boilerplate so each card definition above
/// stays readable.
CatalogItem _buildCard({
  required String name,
  required String description,
  required Schema schema,
  required _CardWidgetBuilder builder,
  required String exampleJson,
}) {
  return CatalogItem(
    name: name,
    dataSchema: schema,
    exampleData: [() => exampleJson],
    widgetBuilder: (itemContext) {
      final data = itemContext.data as Map<String, Object?>;
      return builder(data, itemContext.buildContext);
    },
  );
}

Color _hazusColor(int category) {
  return switch (category) {
    0 => Colors.green,
    1 => Colors.lightGreen,
    2 => Colors.orange,
    3 => Colors.deepOrange,
    _ => Colors.red,
  };
}

Color _triageColor(String triage) {
  return switch (triage.toUpperCase()) {
    'RED' => Colors.red,
    'YELLOW' => Colors.amber,
    'GREEN' => Colors.green,
    'BLACK' => Colors.black87,
    _ => Colors.grey,
  };
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return [
      for (final v in raw)
        if (v is String) v else v.toString(),
    ];
  }
  return const <String>[];
}

/// Evidence header for the IncidentReportCard. Surfaces the original
/// user input (image, voice transcript, typed text) above the filled
/// report body so the responder can compare what was captured against
/// what the model wrote. Reads from [AssistantCubit.evidenceSink] —
/// a top-level [ValueNotifier] — because genui's `Surface` widget
/// mounts catalog children outside our [BlocProvider] inheritance
/// chain, so a direct `BlocBuilder` lookup throws
/// `ProviderNotFoundException`. The sink is updated by the cubit on
/// every intake submit and turn commit. Renders nothing when no
/// evidence is attached.
/// Convert an ISO-8601 timestamp ("2026-05-10T11:45:00Z") into a
/// human-readable local label ("May 10, 2026 · 11:45 AM"). Falls back
/// to the original string if parsing fails so a malformed model
/// output still surfaces something useful.
String _humanReadableTimestamp(String iso) {
  if (iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('MMM d, yyyy · h:mm a').format(dt);
  } on FormatException {
    return iso;
  }
}

/// Distil a `gps=lat=…, lng=…(±Nm)` evidence string down to a clean
/// "19.20337°N, 72.82770°E (±15 m)" label. Accepts the loose formats
/// the model can echo back without re-asking.
String _humanReadableGps(String raw) {
  if (raw.isEmpty) return '';
  final latMatch = RegExp(r'lat\s*=\s*(-?\d+\.\d+)').firstMatch(raw);
  final lngMatch = RegExp(r'(?:lng|lon)\s*=\s*(-?\d+\.\d+)').firstMatch(raw);
  if (latMatch == null || lngMatch == null) return raw;
  final lat = double.tryParse(latMatch.group(1)!);
  final lng = double.tryParse(lngMatch.group(1)!);
  if (lat == null || lng == null) return raw;
  final accMatch = RegExp(r'±\s*([\d.]+)\s*m').firstMatch(raw);
  final acc = accMatch?.group(1);
  final latLabel = '${lat.abs().toStringAsFixed(5)}° ${lat >= 0 ? "N" : "S"}';
  final lngLabel = '${lng.abs().toStringAsFixed(5)}° ${lng >= 0 ? "E" : "W"}';
  return acc == null
      ? '$latLabel, $lngLabel'
      : '$latLabel, $lngLabel (±$acc m)';
}

/// Compact captured-at + location pill row rendered above the report
/// body. Surfaces the responder-facing metadata the model embedded in
/// `prepared_at` / `gps` without forcing them to scan the form blocks.
class _ReportMetadataStrip extends StatelessWidget {
  const _ReportMetadataStrip({
    required this.capturedAt,
    required this.location,
  });

  final String capturedAt;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (capturedAt.isNotEmpty)
            _MetadataPill(
              icon: Icons.schedule,
              label: capturedAt,
            ),
          if (location.isNotEmpty)
            _MetadataPill(
              icon: Icons.place_outlined,
              label: location,
            ),
        ],
      ),
    );
  }
}

/// One-line explainer rendered above the form body whenever the
/// model emitted `[INFERRED …]` or `[UNKNOWN …]` placeholders. The
/// markers themselves are amber-pilled inline, but a responder
/// glancing at the report needs to know what those chips MEAN
/// before they hit Confirm.
class _PlaceholderLegend extends StatelessWidget {
  const _PlaceholderLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 14, color: Colors.brown.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Amber chips mark fields the model could not verify from '
              'the captured evidence — confirm or replace them before '
              'submitting. "0 reported" means no count was given; edit '
              'if you have a real number.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.brown.shade900,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.indigo.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.indigo.shade700),
          const SizedBox(width: 5),
          SelectableText(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.indigo.shade900,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceBlock extends StatelessWidget {
  const _EvidenceBlock();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantEvidenceSnapshot>(
      valueListenable: AssistantCubit.evidenceSink,
      builder: (context, snapshot, _) {
        final image = snapshot.image;
        final audio = snapshot.audio;
        final text = snapshot.text;
        final hasImage = image != null && image.isNotEmpty;
        final hasAudio = audio != null && audio.isNotEmpty;
        final hasText = text.trim().isNotEmpty;
        if (!hasImage && !hasAudio && !hasText) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.indigo.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.attach_file_outlined,
                        size: 14, color: Colors.indigo),
                    const SizedBox(width: 4),
                    Text(
                      'EVIDENCE CAPTURED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: Image.memory(image, fit: BoxFit.cover),
                    ),
                  ),
                if (hasImage && (hasAudio || hasText))
                  const SizedBox(height: 8),
                if (hasAudio) AegisAudioChip(wavBytes: audio),
                if (hasAudio && hasText) const SizedBox(height: 8),
                if (hasText)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.format_quote,
                            size: 14, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            text.trim(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Inline audio-evidence player. Plays the raw mono 16 kHz IEEE-float32
/// WAV the responder recorded during voice intake — same bytes that
/// were sent to Gemma 4. Uses `just_audio` with a custom byte-stream
/// audio source so we don't have to spill the recording to disk.
class AegisAudioChip extends StatefulWidget {
  const AegisAudioChip({super.key, required this.wavBytes});

  final Uint8List wavBytes;

  @override
  State<AegisAudioChip> createState() => _AegisAudioChipState();
}

class _AegisAudioChipState extends State<AegisAudioChip> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  bool _ready = false;
  bool _playing = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bind();
  }

  Future<void> _bind() async {
    try {
      // Spill the WAV to a temp file rather than using
      // `StreamAudioSource`. just_audio's stream path spins up a
      // localhost HTTP proxy, and Android's default
      // `usesCleartextTraffic=false` (or our network_security_config)
      // blocks cleartext to `127.0.0.1` — ExoPlayer raises
      // `CleartextNotPermittedException`. A file source has zero
      // network surface so it sidesteps the policy entirely. Files
      // are content-hashed so identical WAV bytes reuse the same
      // path across rebuilds (important for the chat-history replay
      // path that re-mounts the chip on every scroll).
      final dir = await getTemporaryDirectory();
      final hash = md5.convert(widget.wavBytes).toString().substring(0, 16);
      final file = File('${dir.path}/aegis-evidence-$hash.wav');
      if (!await file.exists()) {
        await file.writeAsBytes(widget.wavBytes, flush: true);
      }
      final loaded = await _player.setFilePath(file.path);
      if (!mounted) return;
      setState(() {
        _duration = loaded ?? Duration.zero;
        _ready = true;
      });
      _stateSub = _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing &&
            s.processingState != ProcessingState.completed);
        if (s.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    } on Object catch (e) {
      // Player init failure leaves _ready=false; chip shows duration
      // unknown and a disabled button.
      debugPrint('[Aegis][AudioEvidence] bind failed: $e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.seek(Duration.zero);
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = (widget.wavBytes.length / 1024).toStringAsFixed(0);
    final durationLabel = _duration > Duration.zero
        ? _fmtDuration(_duration)
        : '$size KB';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _ready ? _toggle : null,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.graphic_eq, size: 16, color: Colors.indigo),
          const SizedBox(width: 6),
          Text(
            'Voice note · $durationLabel',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}


/// Renders a multi-format disaster-report body as structured UI.
/// Detects three line shapes:
///
///   * **Section heading** — uppercase line with no `:`, or a line
///     wrapped in box-drawing dashes. Bigger weight, indigo accent,
///     extra top padding.
///   * **Field row** — `LABEL: VALUE`. Label in muted bold, value in
///     normal weight, wrapped on overflow. `[INFERRED — verify…]`
///     and `[UNKNOWN…]` markers get an amber chip pill so the
///     responder can spot edits at a glance.
///   * **Free-form line** — plain body text. Indented under the
///     current section heading.
///
/// Format-agnostic — works for ICS-209 BLOCK lines, OCHA "AT A
/// GLANCE", NDRRMC PUBLIC STATUS SUMMARY, etc. Falls back gracefully
/// when the body has no recognisable structure (renders as monospace
/// pre-block).
class _IncidentReportBody extends StatelessWidget {
  const _IncidentReportBody({required this.body});

  final String body;

  static final RegExp _fieldPattern = RegExp(r'^\s*([^:\n]{1,80}?):\s*(.*)$');
  static final RegExp _placeholderPattern =
      RegExp(r'\[(?:INFERRED|UNKNOWN)[^\]]*\]', caseSensitive: false);

  /// Strip noisy admin prefixes ICS-209 / NDRRMC use ("BLOCK 1.",
  /// "Section 4.", "1.2", etc) and Title Case the surviving label so
  /// "BLOCK 16. PUBLIC" reads as "Public" — the block number is
  /// agency-internal noise that hurts at-a-glance scan in the
  /// responder UI.
  /// Strip pure box-drawing / dash-rule decoration from a heading.
  /// Returns empty when the whole line is a horizontal rule so the
  /// caller renders a Divider instead.
  static String _cleanHeading(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^[─━—=─]+|[─━—=─]+\$'), '').trim();
    s = s.replaceAll(RegExp(r'\s+[─━—=─]+\s*'), ' ').trim();
    if (s.replaceAll(RegExp(r'[─━—=─\s]'), '').isEmpty) return '';
    final words = s.split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static String _cleanLabel(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(
        RegExp(r'^(?:BLOCK|SECTION|ITEM)\s+\d+[A-Za-z]?\.?\s*',
            caseSensitive: false),
        '');
    s = s.replaceFirst(RegExp(r'^\d+(?:\.\d+)?\.?\s*'), '');
    if (s.isEmpty) return raw.trim();
    final words = s.split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) return w; // keep IC, GPS, NFI
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  bool _isHeading(String line) {
    final stripped = line.trim();
    if (stripped.isEmpty) return false;
    if (stripped.length < 3) return false;
    if (stripped.contains(':') && !stripped.endsWith(':')) return false;
    final letters = stripped.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return false;
    final upperRatio =
        letters.split('').where((c) => c == c.toUpperCase()).length /
            letters.length;
    return upperRatio > 0.85;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const Text(
        '(empty report)',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    final lines = trimmed.split('\n');
    final widgets = <Widget>[];
    var prevWasHeading = false;
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 6));
        prevWasHeading = false;
        continue;
      }
      if (_isHeading(line)) {
        final headingText = _cleanHeading(line);
        if (headingText.isEmpty) {
          // Pure rule line (e.g. ─── or ===) — render as divider.
          widgets.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: Colors.indigo, thickness: 1),
          ));
          prevWasHeading = true;
          continue;
        }
        widgets.add(Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 10, bottom: 4),
          child: SelectableText(
            headingText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.indigo,
              letterSpacing: 0.3,
            ),
          ),
        ));
        prevWasHeading = true;
        continue;
      }
      final match = _fieldPattern.firstMatch(line);
      if (match != null) {
        final label = _cleanLabel(match.group(1)!);
        final value = match.group(2)!.trim();
        widgets.add(Padding(
          padding: EdgeInsets.only(
            left: prevWasHeading ? 4 : 0,
            top: 2,
            bottom: 2,
          ),
          child: _ReportFieldRow(label: label, value: value),
        ));
        prevWasHeading = false;
        continue;
      }
      widgets.add(Padding(
        padding: EdgeInsets.only(left: prevWasHeading ? 4 : 0, bottom: 2),
        child: SelectableText(
          line,
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
      ));
      prevWasHeading = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}

class _ReportFieldRow extends StatelessWidget {
  const _ReportFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelText = '$label:';
    final spans = <InlineSpan>[];
    if (value.isEmpty) {
      spans.add(const TextSpan(
        text: '—',
        style: TextStyle(color: Colors.black38),
      ));
    } else {
      var cursor = 0;
      for (final match
          in _IncidentReportBody._placeholderPattern.allMatches(value)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: value.substring(cursor, match.start)));
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              match.group(0)!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.brown,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ));
        cursor = match.end;
      }
      if (cursor < value.length) {
        spans.add(TextSpan(text: value.substring(cursor)));
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 160),
          padding: const EdgeInsets.only(right: 8, top: 1),
          child: Text(
            labelText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, height: 1.4),
              children: spans,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared visual chrome for the leaf cards. Keeps padding, hierarchy,
/// and accent stripe consistent so the agent's progressively-emitted
/// output reads as one coherent surface.
class _AegisCard extends StatelessWidget {
  const _AegisCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.subtitle,
    this.footer,
    this.accentColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? iconColor;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            body,
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
