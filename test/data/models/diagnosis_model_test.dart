import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves the linked chat session when serialized', () {
    final now = DateTime.utc(2026, 3, 6, 12);
    final diagnosis = DiagnosisModel(
      id: 'diagnosis-1',
      cropId: 'crop-1',
      userId: 'user-1',
      chatSessionId: 'session-1',
      diagnosisMode: DiagnosisMode.online,
      diseaseName: 'Tomato early blight',
      diagnosedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final restored = DiagnosisModel.fromMap(diagnosis.toMap());

    expect(restored.chatSessionId, 'session-1');
  });
}