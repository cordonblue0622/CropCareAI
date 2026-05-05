class AiBackendProgressResponse {
  final double healthScore;
  final String progressStatus;
  final String assessment;
  final List<String> nextSteps;

  const AiBackendProgressResponse({
    required this.healthScore,
    required this.progressStatus,
    required this.assessment,
    required this.nextSteps,
  });

  factory AiBackendProgressResponse.fromMap(Map<String, dynamic> map) {
    return AiBackendProgressResponse(
      healthScore: (map['health_score'] as num?)?.toDouble() ?? 50.0,
      progressStatus: map['progress_status'] as String? ?? 'stable',
      assessment: map['assessment'] as String? ?? '',
      nextSteps: (map['next_steps'] is List)
          ? (map['next_steps'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class AiBackendDetectResponse {
  final String status;
  final String source;
  final String? cropType;
  final List<AiBackendDetectionItem> detections;
  final AiBackendModelInfo model;
  final List<String> notes;

  const AiBackendDetectResponse({
    required this.status,
    required this.source,
    required this.cropType,
    required this.detections,
    required this.model,
    required this.notes,
  });

  AiBackendDetectionItem? get primaryDetection =>
      detections.isEmpty ? null : detections.first;

  Map<String, dynamic> toDetectedRegionsJson() {
    return {
      'status': status,
      'source': source,
      'crop_type': cropType,
      'model': model.toMap(),
      'notes': notes,
      'detections': detections.map((detection) => detection.toMap()).toList(),
    };
  }

  factory AiBackendDetectResponse.fromMap(Map<String, dynamic> map) {
    final rawDetections = map['detections'];
    return AiBackendDetectResponse(
      status: (map['status'] as String? ?? 'unknown').trim(),
      source: (map['source'] as String? ?? 'backend').trim(),
      cropType: map['crop_type'] as String?,
      detections: rawDetections is List
          ? rawDetections
              .whereType<Map>()
              .map((row) => AiBackendDetectionItem.fromMap(
                  Map<String, dynamic>.from(row)))
              .toList()
          : const [],
      model: AiBackendModelInfo.fromMap(
        Map<String, dynamic>.from((map['model'] as Map?) ?? const {}),
      ),
      notes: (map['notes'] is List)
          ? (map['notes'] as List).map((item) => item.toString()).toList()
          : const [],
    );
  }
}

class AiBackendDetectionItem {
  final String label;
  final String? labelKey;
  final double confidence;
  final AiBackendBoundingBox bbox;

  const AiBackendDetectionItem({
    required this.label,
    this.labelKey,
    required this.confidence,
    required this.bbox,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'label_key': labelKey,
      'confidence': confidence,
      'bbox': bbox.toMap(),
    };
  }

  factory AiBackendDetectionItem.fromMap(Map<String, dynamic> map) {
    return AiBackendDetectionItem(
      label: (map['label'] as String? ?? 'unknown').trim(),
      labelKey: (map['label_key'] as String?)?.trim(),
      confidence: ((map['confidence'] as num?) ?? 0).toDouble(),
      bbox: AiBackendBoundingBox.fromMap(
        Map<String, dynamic>.from((map['bbox'] as Map?) ?? const {}),
      ),
    );
  }
}

class AiBackendBoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const AiBackendBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  factory AiBackendBoundingBox.fromMap(Map<String, dynamic> map) {
    return AiBackendBoundingBox(
      x: ((map['x'] as num?) ?? 0).toDouble(),
      y: ((map['y'] as num?) ?? 0).toDouble(),
      width: ((map['width'] as num?) ?? 0).toDouble(),
      height: ((map['height'] as num?) ?? 0).toDouble(),
    );
  }
}

class AiBackendModelInfo {
  final String name;
  final String version;

  const AiBackendModelInfo({
    required this.name,
    required this.version,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'version': version,
    };
  }

  factory AiBackendModelInfo.fromMap(Map<String, dynamic> map) {
    return AiBackendModelInfo(
      name: (map['name'] as String? ?? 'backend').trim(),
      version: (map['version'] as String? ?? 'unknown').trim(),
    );
  }
}