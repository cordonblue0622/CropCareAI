import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

class FarmWeatherSnapshot {
  final String locationLabel;
  final double temperatureC;
  final int relativeHumidity;
  final double precipitationMm;
  final int weatherCode;
  final bool isDay;
  final String conditionLabel;
  final DateTime fetchedAt;

  const FarmWeatherSnapshot({
    required this.locationLabel,
    required this.temperatureC,
    required this.relativeHumidity,
    required this.precipitationMm,
    required this.weatherCode,
    this.isDay = true,
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
  static const String _openMeteoGeocodingHost = 'geocoding-api.open-meteo.com';
  static const String _openMeteoWeatherHost = 'api.open-meteo.com';

  final http.Client _client;

  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  Future<FarmWeatherSnapshot?> fetchCurrentConditions(
      String rawLocation) async {
    final location = rawLocation.trim();
    if (location.isEmpty) return null;

    try {
      if (AppConstants.weatherApiKey.isEmpty) {
        return _fetchOpenMeteoConditions(location);
      }
      final uri = Uri.https(_host, '/v1/current.json', {
        'key': AppConstants.weatherApiKey,
        'q': location,
        'aqi': 'no',
      });
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return _fetchOpenMeteoConditions(location);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('error')) return _fetchOpenMeteoConditions(location);

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
        isDay: ((current['is_day'] as num?)?.round() ?? 1) == 1,
        conditionLabel:
            (condition['text'] as String?)?.trim().isNotEmpty == true
                ? (condition['text'] as String).trim().toLowerCase()
                : 'mixed conditions',
        fetchedAt:
            DateTime.tryParse(current['last_updated'] as String? ?? '') ??
                DateTime.now(),
      );
    } catch (_) {
      return _fetchOpenMeteoConditions(location);
    }
  }

  Future<FarmWeatherSnapshot?> _fetchOpenMeteoConditions(
      String location) async {
    try {
      final geocodingUri = Uri.https(
        _openMeteoGeocodingHost,
        '/v1/search',
        {'name': location, 'count': '1', 'language': 'en', 'format': 'json'},
      );
      final geocodingResponse = await _client.get(geocodingUri);
      if (geocodingResponse.statusCode != 200) return null;

      final geocodingBody =
          jsonDecode(geocodingResponse.body) as Map<String, dynamic>;
      final results = geocodingBody['results'];
      if (results is! List || results.isEmpty) return null;
      final place = results.first;
      if (place is! Map<String, dynamic>) return null;
      final latitude = (place['latitude'] as num?)?.toDouble();
      final longitude = (place['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return null;

      final weatherUri = Uri.https(
        _openMeteoWeatherHost,
        '/v1/forecast',
        {
          'latitude': '$latitude',
          'longitude': '$longitude',
          'current':
              'temperature_2m,relative_humidity_2m,precipitation,weather_code,is_day',
          'timezone': 'auto',
        },
      );
      final weatherResponse = await _client.get(weatherUri);
      if (weatherResponse.statusCode != 200) return null;

      final weatherBody =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherBody['current'];
      if (current is! Map<String, dynamic>) return null;
      final code = (current['weather_code'] as num?)?.round() ?? -1;

      return FarmWeatherSnapshot(
        locationLabel: _composeLocationLabel(place, fallback: location),
        temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        relativeHumidity:
            (current['relative_humidity_2m'] as num?)?.round() ?? 0,
        precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
        weatherCode: code,
        isDay: ((current['is_day'] as num?)?.round() ?? 1) == 1,
        conditionLabel: _openMeteoConditionLabel(code),
        fetchedAt: DateTime.tryParse(current['time'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static String _openMeteoConditionLabel(int code) {
    if (code == 0) return 'clear sky';
    if (code <= 3) return 'partly cloudy';
    if (code == 45 || code == 48) return 'foggy';
    if (code >= 51 && code <= 67) return 'rain or drizzle';
    if (code >= 71 && code <= 77) return 'snow';
    if (code >= 80 && code <= 82) return 'rain showers';
    if (code >= 85 && code <= 86) return 'snow showers';
    if (code >= 95) return 'thunderstorms';
    return 'mixed conditions';
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
