import '../data/models/ai_backend_models.dart';

class LocalClassifierService {
  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) {
    throw UnsupportedError(
      'Local TFLite classification is not available on this platform.',
    );
  }
}
