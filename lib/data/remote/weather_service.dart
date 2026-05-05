import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

class FarmWeatherSnapshot {
  final String locationLabel;
  final double temperatureC;
  final int relativeHumidity;
  final double precipitationMm;
  final int weatherCode;
  final String conditionLabel;
  final DateTime fetchedAt;

  const FarmWeatherSnapshot({
    required this.locationLabel,
    required this.temperatureC,
    required this.relativeHumidity,
    required this.precipitationMm,
    required this.weatherCode,
    required this.conditionLabel,
    required this.fetchedAt,
  });

  bool get isHumid => relativeHumidity >= 80;

  bool get isWet =>
      precipitationMm >= 0.2 ||
      WeatherService.isWetCode(weatherCode) ||
      WeatherService.isWetText(conditionLabel);
}

class WeatherService {
  static const String _host = 'api.weatherapi.com';

  Future<FarmWeatherSnapshot?> fetchCurrentConditions(
      String rawLocation) async {
    final location = rawLocation.trim();
    if (location.isEmpty || AppConstants.weatherApiKey.isEmpty) return null;

    try {
      final uri = Uri.https(_host, '/v1/current.json', {
        'key': AppConstants.weatherApiKey,
        'q': location,
        'aqi': 'no',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('error')) return null;

      final locationData = body['location'];
      final current = body['current'];
      if (locationData is! Map<String, dynamic> ||
          current is! Map<String, dynamic>) {
        return null;
      }

      final condition = current['condition'];
      if (condition is! Map<String, dynamic>) return null;

      return FarmWeatherSnapshot(
        locationLabel: _composeLocationLabel(locationData, fallback: location),
        temperatureC: (current['temp_c'] as num?)?.toDouble() ?? 0,
        relativeHumidity: (current['humidity'] as num?)?.round() ?? 0,
        precipitationMm: (current['precip_mm'] as num?)?.toDouble() ?? 0,
        weatherCode: (condition['code'] as num?)?.round() ?? -1,
        conditionLabel:
            (condition['text'] as String?)?.trim().isNotEmpty == true
                ? (condition['text'] as String).trim().toLowerCase()
                : 'mixed conditions',
        fetchedAt:
            DateTime.tryParse(current['last_updated'] as String? ?? '') ??
                DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static bool isWetCode(int code) => const {
        1063,
        1066,
        1069,
        1072,
        1087,
        1114,
        1117,
        1150,
        1153,
        1168,
        1171,
        1180,
        1183,
        1186,
        1189,
        1192,
        1195,
        1198,
        1201,
        1204,
        1207,
        1210,
        1213,
        1216,
        1219,
        1222,
        1225,
        1237,
        1240,
        1243,
        1246,
        1249,
        1252,
        1255,
        1258,
        1261,
        1264,
        1273,
        1276,
        1279,
        1282,
      }.contains(code);

  static bool isWetText(String condition) {
    final lower = condition.toLowerCase();
    return lower.contains('rain') ||
        lower.contains('drizzle') ||
        lower.contains('snow') ||
        lower.contains('sleet') ||
        lower.contains('ice pellets') ||
        lower.contains('thunder');
  }

  String _composeLocationLabel(
    Map<String, dynamic> locationData, {
    required String fallback,
  }) {
    final parts = [
      locationData['name'],
      locationData['region'],
      locationData['country'],
    ]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return fallback;
    return parts.toSet().take(3).join(', ');
  }
}
