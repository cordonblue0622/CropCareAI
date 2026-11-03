import 'package:shared_preferences/shared_preferences.dart';

/// Stores post-registration tour status locally, independently for each user.
class GuidedTourService {
  static const String _preferencePrefix = 'guided_app_tour_completed_v1_';

  const GuidedTourService();

  Future<bool> isComplete(String userId) async {
    if (userId.trim().isEmpty) return true;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('$_preferencePrefix$userId') ?? false;
  }

  Future<void> markComplete(String userId) async {
    if (userId.trim().isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_preferencePrefix$userId', true);
  }
}
