import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

class FarmWeatherHour {
  final DateTime time;
  final double temperatureC;
  final int precipitationProbability;
  final double windSpeedKph;
  final int weatherCode;
  final String conditionLabel;

  const FarmWeatherHour({
    required this.time,
    required this.temperatureC,
    required this.precipitationProbability,
    this.windSpeedKph = 0,
    required this.weatherCode,
    required this.conditionLabel,
  });
}

class FarmWeatherDay {
  final DateTime date;
  final double highC;
  final double lowC;
  final int precipitationProbability;
  final int weatherCode;
  final String conditionLabel;

  const FarmWeatherDay({
    required this.date,
    required this.highC,
    required this.lowC,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.conditionLabel,
  });
}

class FarmWeatherSnapshot {
  final String locationLabel;
  final String providerName;
  final double temperatureC;
  final int relativeHumidity;
  final double precipitationMm;
  final double windSpeedKph;
  final int weatherCode;
  final bool isDay;
  final String conditionLabel;
  final DateTime fetchedAt;
  final List<FarmWeatherHour> hourlyForecast;
  final List<FarmWeatherDay> dailyForecast;

  const FarmWeatherSnapshot({
    required this.locationLabel,
    this.providerName = 'Open-Meteo',
    required this.temperatureC,
    required this.relativeHumidity,
    required this.precipitationMm,
    this.windSpeedKph = 0,
    required this.weatherCode,
    this.isDay = true,
    required this.conditionLabel,
    required this.fetchedAt,
    this.hourlyForecast = const [],
    this.dailyForecast = const [],
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
  static const Duration _requestTimeout = Duration(seconds: 12);

  final http.Client _client;

  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  /// Loads live conditions plus hourly and seven-day forecasts for a farm.
  /// WeatherAPI is used when the app has a key; Open-Meteo is the no-key
  /// provider and also serves as a fallback when WeatherAPI is unavailable.
  Future<FarmWeatherSnapshot?> fetchCurrentConditions(
    String rawLocation,
  ) async {
    final location = rawLocation.trim();
    if (location.isEmpty) return null;

    if (AppConstants.weatherApiKey.isNotEmpty) {
      final weatherApiSnapshot = await _fetchWeatherApiForecast(location);
      if (weatherApiSnapshot != null) return weatherApiSnapshot;
    }
    return _fetchOpenMeteoForecast(location);
  }

  Future<FarmWeatherSnapshot?> _fetchWeatherApiForecast(
    String location,
  ) async {
    try {
      final uri = Uri.https(_host, '/v1/forecast.json', {
        'key': AppConstants.weatherApiKey,
        'q': location,
        'days': '7',
        'aqi': 'no',
        'alerts': 'no',
      });
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final locationData = body['location'];
      final current = body['current'];
      final forecast = body['forecast'];
      if (locationData is! Map<String, dynamic> ||
          current is! Map<String, dynamic> ||
          forecast is! Map<String, dynamic>) {
        return null;
      }

      final currentCondition = current['condition'];
      if (currentCondition is! Map<String, dynamic>) return null;
      final forecastDays = forecast['forecastday'];
      final days = forecastDays is List
          ? forecastDays
              .whereType<Map<String, dynamic>>()
              .map(_weatherApiDay)
              .whereType<FarmWeatherDay>()
              .toList(growable: false)
          : const <FarmWeatherDay>[];
      final hours = <FarmWeatherHour>[];
      if (forecastDays is List) {
        for (final day in forecastDays.whereType<Map<String, dynamic>>()) {
          final rawHours = day['hour'];
          if (rawHours is! List) continue;
          for (final hour in rawHours.whereType<Map<String, dynamic>>()) {
            final parsed = _weatherApiHour(hour);
            if (parsed != null) hours.add(parsed);
          }
        }
      }

      return FarmWeatherSnapshot(
        locationLabel: _weatherLocationLabel(locationData, location),
        providerName: 'WeatherAPI.com',
        temperatureC: (current['temp_c'] as num?)?.toDouble() ?? 0,
        relativeHumidity: (current['humidity'] as num?)?.round() ?? 0,
        precipitationMm: (current['precip_mm'] as num?)?.toDouble() ?? 0,
        windSpeedKph: (current['wind_kph'] as num?)?.toDouble() ?? 0,
        weatherCode: (currentCondition['code'] as num?)?.round() ?? -1,
        isDay: ((current['is_day'] as num?)?.round() ?? 1) == 1,
        conditionLabel: _stringOr(
          currentCondition['text'],
          'mixed conditions',
        ).toLowerCase(),
        fetchedAt:
            DateTime.tryParse(current['last_updated'] as String? ?? '') ??
                DateTime.now(),
        hourlyForecast: hours,
        dailyForecast: days,
      );
    } catch (_) {
      return null;
    }
  }

  Future<FarmWeatherSnapshot?> _fetchOpenMeteoForecast(
    String location,
  ) async {
    try {
      final place = await _geocodeOpenMeteoLocation(location);
      if (place == null) return null;
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
              'temperature_2m,relative_humidity_2m,precipitation,weather_code,is_day,wind_speed_10m',
          'hourly':
              'temperature_2m,precipitation_probability,weather_code,wind_speed_10m',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'forecast_days': '7',
          'timezone': 'auto',
        },
      );
      final weatherResponse =
          await _client.get(weatherUri).timeout(_requestTimeout);
      if (weatherResponse.statusCode != 200) return null;

      final weatherBody =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherBody['current'];
      if (current is! Map<String, dynamic>) return null;
      final code = (current['weather_code'] as num?)?.round() ?? -1;

      return FarmWeatherSnapshot(
        locationLabel: _weatherLocationLabel(place, location),
        temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        relativeHumidity:
            (current['relative_humidity_2m'] as num?)?.round() ?? 0,
        precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
        windSpeedKph: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        weatherCode: code,
        isDay: ((current['is_day'] as num?)?.round() ?? 1) == 1,
        conditionLabel: _openMeteoConditionLabel(code),
        fetchedAt: DateTime.tryParse(current['time'] as String? ?? '') ??
            DateTime.now(),
        hourlyForecast: _openMeteoHourly(weatherBody['hourly']),
        dailyForecast: _openMeteoDaily(weatherBody['daily']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _geocodeOpenMeteoLocation(
    String location,
  ) async {
    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    final hasAdminContext = parts.length > 1;
    final mostSpecificPlace = parts.first;
    final queries = <String>{mostSpecificPlace, location};

    for (final query in queries) {
      if (query.isEmpty) continue;
      try {
        final uri = Uri.https(
          _openMeteoGeocodingHost,
          '/v1/search',
          {'name': query, 'count': '10', 'language': 'en', 'format': 'json'},
        );
        final response = await _client.get(uri).timeout(_requestTimeout);
        if (response.statusCode != 200) continue;
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final results = body['results'];
        if (results is! List || results.isEmpty) continue;
        final candidates = results.whereType<Map<String, dynamic>>().toList();
        if (candidates.isEmpty) continue;
        final countryHint = parts.length > 2 ? parts.last.toLowerCase() : '';
        final matchingCountry = candidates.where((candidate) {
          final country = (candidate['country'] as String? ?? '').toLowerCase();
          return countryHint.isEmpty ||
              country.contains(countryHint) ||
              countryHint.contains(country);
        }).toList();
        if (countryHint.isNotEmpty && matchingCountry.isEmpty) continue;

        final placeName = mostSpecificPlace.toLowerCase();
        final exactPlace = matchingCountry.where((candidate) {
          final name =
              (candidate['name'] as String? ?? '').trim().toLowerCase();
          return name == placeName;
        }).toList();
        if (exactPlace.isNotEmpty) return exactPlace.first;

        // Do not quietly return weather for a less-specific city or province.
        if (hasAdminContext) continue;
      } catch (_) {
        // Try the full address if a locality-only query fails.
      }
    }
    return null;
  }

  List<FarmWeatherHour> _openMeteoHourly(Object? rawHourly) {
    if (rawHourly is! Map<String, dynamic>) return const [];
    final times = rawHourly['time'];
    final temperatures = rawHourly['temperature_2m'];
    final probabilities = rawHourly['precipitation_probability'];
    final codes = rawHourly['weather_code'];
    final winds = rawHourly['wind_speed_10m'];
    if (times is! List || temperatures is! List || codes is! List) {
      return const [];
    }

    final now = DateTime.now();
    final result = <FarmWeatherHour>[];
    for (var index = 0;
        index < times.length &&
            index < temperatures.length &&
            index < codes.length;
        index++) {
      final time = DateTime.tryParse(times[index]?.toString() ?? '');
      final temperature = (temperatures[index] as num?)?.toDouble();
      final code = (codes[index] as num?)?.round();
      if (time == null || temperature == null || code == null) continue;
      if (time.isBefore(now.subtract(const Duration(hours: 1)))) continue;
      final probability = probabilities is List && index < probabilities.length
          ? (probabilities[index] as num?)?.round() ?? 0
          : 0;
      result.add(FarmWeatherHour(
        time: time,
        temperatureC: temperature,
        precipitationProbability: probability,
        windSpeedKph: winds is List && index < winds.length
            ? (winds[index] as num?)?.toDouble() ?? 0
            : 0,
        weatherCode: code,
        conditionLabel: _openMeteoConditionLabel(code),
      ));
      if (result.length == 36) break;
    }
    return result;
  }

  List<FarmWeatherDay> _openMeteoDaily(Object? rawDaily) {
    if (rawDaily is! Map<String, dynamic>) return const [];
    final dates = rawDaily['time'];
    final highs = rawDaily['temperature_2m_max'];
    final lows = rawDaily['temperature_2m_min'];
    final probabilities = rawDaily['precipitation_probability_max'];
    final codes = rawDaily['weather_code'];
    if (dates is! List || highs is! List || lows is! List || codes is! List) {
      return const [];
    }

    final result = <FarmWeatherDay>[];
    for (var index = 0;
        index < dates.length &&
            index < highs.length &&
            index < lows.length &&
            index < codes.length;
        index++) {
      final date = DateTime.tryParse(dates[index]?.toString() ?? '');
      final high = (highs[index] as num?)?.toDouble();
      final low = (lows[index] as num?)?.toDouble();
      final code = (codes[index] as num?)?.round();
      if (date == null || high == null || low == null || code == null) continue;
      final probability = probabilities is List && index < probabilities.length
          ? (probabilities[index] as num?)?.round() ?? 0
          : 0;
      result.add(FarmWeatherDay(
        date: date,
        highC: high,
        lowC: low,
        precipitationProbability: probability,
        weatherCode: code,
        conditionLabel: _openMeteoConditionLabel(code),
      ));
    }
    return result;
  }

  FarmWeatherDay? _weatherApiDay(Map<String, dynamic> day) {
    final date = DateTime.tryParse(day['date'] as String? ?? '');
    final rawDay = day['day'];
    if (date == null || rawDay is! Map<String, dynamic>) return null;
    final condition = rawDay['condition'];
    final code = condition is Map<String, dynamic>
        ? (condition['code'] as num?)?.round() ?? -1
        : -1;
    return FarmWeatherDay(
      date: date,
      highC: (rawDay['maxtemp_c'] as num?)?.toDouble() ?? 0,
      lowC: (rawDay['mintemp_c'] as num?)?.toDouble() ?? 0,
      precipitationProbability:
          (rawDay['daily_chance_of_rain'] as num?)?.round() ?? 0,
      weatherCode: code,
      conditionLabel: condition is Map<String, dynamic>
          ? _stringOr(condition['text'], 'mixed conditions').toLowerCase()
          : 'mixed conditions',
    );
  }

  FarmWeatherHour? _weatherApiHour(Map<String, dynamic> hour) {
    final time = DateTime.tryParse(hour['time'] as String? ?? '');
    if (time == null) return null;
    final condition = hour['condition'];
    final code = condition is Map<String, dynamic>
        ? (condition['code'] as num?)?.round() ?? -1
        : -1;
    return FarmWeatherHour(
      time: time,
      temperatureC: (hour['temp_c'] as num?)?.toDouble() ?? 0,
      precipitationProbability: (hour['chance_of_rain'] as num?)?.round() ?? 0,
      windSpeedKph: (hour['wind_kph'] as num?)?.toDouble() ?? 0,
      weatherCode: code,
      conditionLabel: condition is Map<String, dynamic>
          ? _stringOr(condition['text'], 'mixed conditions').toLowerCase()
          : 'mixed conditions',
    );
  }

  static String _openMeteoConditionLabel(int code) {
    if (code == 0) return 'clear sky';
    if (code == 1) return 'mainly clear';
    if (code == 2) return 'partly cloudy';
    if (code == 3) return 'overcast';
    if (code == 45 || code == 48) return 'foggy';
    if (code >= 51 && code <= 57) return 'drizzle';
    if (code >= 61 && code <= 67) return 'rain';
    if (code >= 71 && code <= 77) return 'snow';
    if (code >= 80 && code <= 82) return 'rain showers';
    if (code >= 85 && code <= 86) return 'snow showers';
    if (code == 95) return 'thunderstorms';
    if (code >= 96) return 'thunderstorms with hail';
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
      locationData['region'] ?? locationData['admin1'],
      locationData['country'],
    ]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return fallback;
    return parts.toSet().take(3).join(', ');
  }

  String _weatherLocationLabel(
    Map<String, dynamic> locationData,
    String requestedLocation,
  ) {
    if (requestedLocation.contains(',')) return requestedLocation;
    return _composeLocationLabel(locationData, fallback: requestedLocation);
  }

  String _stringOr(Object? value, String fallback) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? fallback : text;
  }
}
