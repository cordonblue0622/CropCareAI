/// Converts a raw model label into a human-readable Title Case string.
///
/// Examples:
///   'tomato_bacterial_spot' -> 'Tomato Bacterial Spot'
///   'healthy'               -> 'Healthy'
///   'Tomato Bacterial Spot' -> 'Tomato Bacterial Spot' (idempotent)
///   ''                      -> ''
///
/// Splits on underscores and whitespace, collapses repeated separators,
/// title-cases each token (first char upper, rest lower).
String humanizeDiseaseLabel(String raw) {
  if (raw.isEmpty) return raw;
  final tokens = raw
      .split(RegExp(r'[_\s]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return '';
  return tokens
      .map((t) => t[0].toUpperCase() + t.substring(1).toLowerCase())
      .join(' ');
}
