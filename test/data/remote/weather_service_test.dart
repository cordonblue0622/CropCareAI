import 'dart:convert';

import 'package:cropcare_ai/data/remote/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses Open-Meteo fallback and maps the current weather code', () async {
    final requestedUris = <Uri>[];
    final client = MockClient((request) async {
      requestedUris.add(request.url);

      switch (request.url.host) {
        case 'geocoding-api.open-meteo.com':
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'name': 'Los Banos',
                  'admin1': 'Calabarzon',
                  'country': 'Philippines',
                  'latitude': 14.1667,
                  'longitude': 121.25,
                },
              ],
            }),
            200,
          );
        case 'api.open-meteo.com':
          return http.Response(
            jsonEncode({
              'current': {
                'time': '2026-09-06T14:30',
                'temperature_2m': 29.4,
                'relative_humidity_2m': 86,
                'precipitation': 1.2,
                'weather_code': 95,
                'is_day': 0,
              },
            }),
            200,
          );
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
    });

    final snapshot = await WeatherService(client: client)
        .fetchCurrentConditions(' Los Banos ');

    expect(requestedUris, hasLength(2));
    expect(requestedUris.first.host, 'geocoding-api.open-meteo.com');
    expect(requestedUris.first.path, '/v1/search');
    expect(requestedUris.first.queryParameters, {
      'name': 'Los Banos',
      'count': '10',
      'language': 'en',
      'format': 'json',
    });
    expect(requestedUris.last.host, 'api.open-meteo.com');
    expect(requestedUris.last.path, '/v1/forecast');
    expect(requestedUris.last.queryParameters['latitude'], '14.1667');
    expect(requestedUris.last.queryParameters['longitude'], '121.25');
    expect(
      requestedUris.last.queryParameters['current'],
      contains('is_day'),
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.locationLabel, 'Los Banos, Calabarzon, Philippines');
    expect(snapshot.temperatureC, 29.4);
    expect(snapshot.relativeHumidity, 86);
    expect(snapshot.precipitationMm, 1.2);
    expect(snapshot.weatherCode, 95);
    expect(snapshot.isDay, isFalse);
    expect(snapshot.conditionLabel, 'thunderstorms');
    expect(snapshot.fetchedAt, DateTime(2026, 9, 6, 14, 30));
    expect(snapshot.isHumid, isTrue);
    expect(snapshot.isWet, isTrue);
  });

  test('uses the exact barangay match from the user profile location',
      () async {
    final requestedUris = <Uri>[];
    final client = MockClient((request) async {
      requestedUris.add(request.url);

      if (request.url.host == 'geocoding-api.open-meteo.com') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Cebu City',
                'admin1': 'Central Visayas',
                'country': 'Philippines',
                'latitude': 10.3157,
                'longitude': 123.8854,
              },
              {
                'name': 'Lahug',
                'admin1': 'Cebu City',
                'country': 'Philippines',
                'latitude': 10.3308,
                'longitude': 123.8983,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.host == 'api.open-meteo.com') {
        return http.Response(
          jsonEncode({
            'current': {
              'time': '2026-10-11T14:30',
              'temperature_2m': 29,
              'relative_humidity_2m': 81,
              'precipitation': 0,
              'weather_code': 2,
              'is_day': 1,
            },
          }),
          200,
        );
      }
      throw StateError('Unexpected request: ${request.url}');
    });

    final snapshot = await WeatherService(client: client)
        .fetchCurrentConditions('Lahug, Cebu City, Cebu, Philippines');

    expect(snapshot, isNotNull);
    expect(
      requestedUris.first.queryParameters['name'],
      'Lahug',
    );
    expect(requestedUris.last.queryParameters['latitude'], '10.3308');
    expect(requestedUris.last.queryParameters['longitude'], '123.8983');
    expect(
      snapshot!.locationLabel,
      'Lahug, Cebu City, Cebu, Philippines',
    );
  });

  test('does not use a broader city match when barangay is not found',
      () async {
    var weatherRequested = false;
    final client = MockClient((request) async {
      if (request.url.host == 'geocoding-api.open-meteo.com') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Cebu City',
                'admin1': 'Central Visayas',
                'country': 'Philippines',
                'latitude': 10.3157,
                'longitude': 123.8854,
              },
            ],
          }),
          200,
        );
      }
      weatherRequested = true;
      throw StateError('A broad location should not be used for weather.');
    });

    final snapshot = await WeatherService(client: client)
        .fetchCurrentConditions('Lahug, Cebu City, Cebu, Philippines');

    expect(snapshot, isNull);
    expect(weatherRequested, isFalse);
  });
}
