import 'dart:async';
import 'dart:convert';

import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/progress_update_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/features/crops/screens/crop_detail_screen.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ImagePicker's existing platform interface supplies the test double.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';

class _Picker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource(
          {required ImageSource source,
          ImagePickerOptions options = const ImagePickerOptions()}) async =>
      XFile.fromData(
          base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg+M/wHwAEAQH/cetH5QAAAABJRU5ErkJggg=='),
          name: 'proof.png');
}

class _Connectivity implements ConnectivityService {
  bool online = true;
  @override
  Future<bool> get isConnected async => online;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements AiBackendService {
  int calls = 0;
  var result = Completer<AiBackendProgressResponse>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #assessCropHealth) {
      calls++;
      expect(
          invocation.namedArguments[#imageDataUrl], startsWith('data:image/'));
      expect(invocation.namedArguments[#imageBytes], isNull);
      return result.future;
    }
    return super.noSuchMethod(invocation);
  }
}

AiBackendProgressResponse decision(bool accepted) => AiBackendProgressResponse(
      accepted: accepted,
      rejectionReason:
          accepted ? null : 'Please upload a clear photo of the correct plant.',
      healthScore: 65,
      progressStatus: 'improving',
      assessment: 'New growth.',
      nextSteps: const ['Continue care'],
    );

void main() {
  testWidgets('proof rejection, retry, duplicate taps and acceptance',
      (tester) async {
    final backend = _Backend();
    final saved = <ProgressUpdateModel>[];
    await _openSheet(tester, backend, _Connectivity(), saved);
    await _submit(tester);
    await tester.tap(find.byType(FilledButton));
    expect(backend.calls, 1);
    backend.result.complete(decision(false));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('Please upload a clear photo of the correct plant.'),
        findsOneWidget);
    expect(find.text('Submit & Analyze'), findsOneWidget);
    backend.result = Completer<AiBackendProgressResponse>();
    await tester.tap(find.text('Change evidence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo from gallery'));
    await tester.pumpAndSettle();
    await _submit(tester);
    expect(backend.calls, 2);
    backend.result.complete(decision(true));
    await tester.pumpAndSettle();
    expect(saved.single.aiAnalysisStatus, AiAnalysisStatus.completed);
    expect(saved.single.healthScore, 65);
  });

  for (final error in [
    TimeoutException('timeout'),
    const FormatException('bad response')
  ]) {
    testWidgets('online $error ends loading without saving', (tester) async {
      final backend = _Backend();
      final saved = <ProgressUpdateModel>[];
      await _openSheet(tester, backend, _Connectivity(), saved);
      await _submit(tester);
      backend.result.completeError(error);
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Submit & Analyze'), findsOneWidget);
      expect(find.textContaining('Photo validation could not finish'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('offline and disconnected submissions stay pending',
      (tester) async {
    for (final initiallyOnline in [false, true]) {
      final backend = _Backend();
      final connection = _Connectivity()..online = initiallyOnline;
      final saved = <ProgressUpdateModel>[];
      await _openSheet(tester, backend, connection, saved);
      await _submit(tester);
      if (initiallyOnline) {
        connection.online = false;
        backend.result.completeError(TimeoutException('connection lost'));
      }
      await tester.pumpAndSettle();
      expect(saved.single.aiAnalysisStatus, AiAnalysisStatus.pending);
      expect(saved.single.healthScore, 55);
      expect(backend.calls, initiallyOnline ? 1 : 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  testWidgets('dismissed sheet ignores a late valid result', (tester) async {
    final backend = _Backend();
    final saved = <ProgressUpdateModel>[];
    await _openSheet(tester, backend, _Connectivity(), saved);
    await _submit(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    backend.result.complete(decision(true));
    await tester.pump();
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSheet(WidgetTester tester, _Backend backend,
    _Connectivity connection, List<ProgressUpdateModel> saved) async {
  final oldPicker = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = _Picker();
  addTearDown(() => ImagePickerPlatform.instance = oldPicker);
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final now = DateTime.now();
  await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AiBackendService>.value(value: backend),
        Provider<ConnectivityService>.value(value: connection),
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    child: const Text('Open'),
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => DailyCheckInSheet(
                              crop: CropModel(
                                  id: 'crop',
                                  userId: 'user',
                                  cropType: CropType.eggplant,
                                  cropName: 'Eggplant',
                                  latestHealthScore: 55,
                                  createdAt: now,
                                  updatedAt: now),
                              allTasks: const [],
                              checkedTasks: const [],
                              activeTreatment: null,
                              latestDiagnosis: null,
                              previousUpdate: null,
                              onSubmitted:
                                  (score, status, update, nextSteps) async =>
                                      saved.add(update),
                            )),
                  ))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tap to take a photo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose a photo from gallery'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Submit & Analyze'));
  // compute() runs in a real isolate; allow its response to reach the widget.
  await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump();
}
