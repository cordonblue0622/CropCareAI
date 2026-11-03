import 'package:cropcare_ai/features/onboarding/guided_tour/guided_tour_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('completion persists across service instances and is scoped per user',
      () async {
    const firstService = GuidedTourService();

    expect(await firstService.isComplete('user-a'), isFalse);
    await firstService.markComplete('user-a');

    const recreatedService = GuidedTourService();
    expect(await recreatedService.isComplete('user-a'), isTrue);
    expect(await recreatedService.isComplete('user-b'), isFalse);
  });

  test('an empty user id never starts or changes a tour status', () async {
    const service = GuidedTourService();

    expect(await service.isComplete(''), isTrue);
    await service.markComplete('');
    expect(await service.isComplete('user-a'), isFalse);
  });
}
