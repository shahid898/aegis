import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

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
