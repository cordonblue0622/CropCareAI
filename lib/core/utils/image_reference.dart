import 'dart:convert';
import 'dart:typed_data';

String buildInlineImageDataUrl(
  List<int> bytes, {
  String mimeType = 'image/jpeg',
}) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

bool isInlineImageDataUrl(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.startsWith('data:image/') &&
      normalized.contains(';base64,');
}

bool isRemoteImageReference(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return normalized.startsWith('http://') || normalized.startsWith('https://');
}

String? normalizeImageReference(dynamic raw) {
  if (raw is! String) {
    return null;
  }
  final normalized = raw.trim();
  return normalized.isEmpty ? null : normalized;
}

Uint8List? decodeInlineImageDataUrl(String? value) {
  final normalized = value?.trim() ?? '';
  if (!isInlineImageDataUrl(normalized)) {
    return null;
  }

  final commaIndex = normalized.indexOf(',');
  if (commaIndex == -1 || commaIndex >= normalized.length - 1) {
    return null;
  }

  try {
    return base64Decode(normalized.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}
