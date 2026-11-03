/// Normalizes AI treatment instructions without turning list numbers into tasks.
class TreatmentActionParser {
  TreatmentActionParser._();

  static final RegExp _numberedItemMarker = RegExp(r'\d{1,2}[.)]\s+');
  static final RegExp _placeholder = RegExp(r'^\d{1,2}[.)]$');

  /// Splits prose into actions while preserving each numbered item as a whole.
  ///
  /// A punctuation-based split alone turns `1. Remove leaves.` into `1.` and
  /// `Remove leaves.`. Numbered items are therefore identified before the
  /// sentence fallback is used. Unnumbered prose retains the previous behavior.
  static List<String> split(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final markers = <RegExpMatch>[];
    for (final match in _numberedItemMarker.allMatches(normalized)) {
      if (match.start == 0 || normalized[match.start - 1] == ' ') {
        markers.add(match);
      }
    }

    if (markers.isNotEmpty) {
      final actions = <String>[];
      final prefix = normalized.substring(0, markers.first.start).trim();
      if (prefix.isNotEmpty) actions.add(prefix);
      for (var index = 0; index < markers.length; index++) {
        final start = markers[index].start;
        final end = index + 1 < markers.length
            ? markers[index + 1].start
            : normalized.length;
        actions.add(normalized.substring(start, end).trim());
      }
      return normalize(actions);
    }

    return normalize(normalized.split(RegExp(r'(?<=[.!?])\s+')));
  }

  /// Removes empty and number-only fragments and de-duplicates real actions.
  static List<String> normalize(Iterable<String> actions) {
    final result = <String>[];
    final seen = <String>{};
    for (final action in actions) {
      final trimmed = action.trim();
      if (!isMeaningful(trimmed)) continue;
      final key = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seen.add(key)) result.add(trimmed);
    }
    return result;
  }

  static bool isMeaningful(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !_placeholder.hasMatch(trimmed);
  }
}
