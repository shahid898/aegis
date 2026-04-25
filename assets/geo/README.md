# Geo assets

Reserved for any bundled GeoJSON / lookup tables in later phases.

Phase 2 ships GPS → ISO-3166 alpha-2 resolution **in Dart** (see
`lib/core/geo/country_resolver.dart`) using axis-aligned bounding boxes —
no bundled asset required. This folder is registered in `pubspec.yaml`
ahead of time so we don't have to bump the Flutter manifest when we
swap in a polygon dataset.
