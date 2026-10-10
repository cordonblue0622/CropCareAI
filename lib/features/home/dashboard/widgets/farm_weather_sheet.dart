import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/remote/weather_service.dart';

enum _WeatherChartMetric { temperature, rainChance, wind }

class FarmWeatherSheet extends StatefulWidget {
  final String locationQuery;
  final FarmWeatherSnapshot? initialWeather;
  final Future<FarmWeatherSnapshot?> Function() loadWeather;

  const FarmWeatherSheet({
    super.key,
    required this.locationQuery,
    required this.initialWeather,
    required this.loadWeather,
  });

  @override
  State<FarmWeatherSheet> createState() => _FarmWeatherSheetState();
}

class _FarmWeatherSheetState extends State<FarmWeatherSheet> {
  FarmWeatherSnapshot? _weather;
  bool _loading = false;
  _WeatherChartMetric _metric = _WeatherChartMetric.temperature;

  @override
  void initState() {
    super.initState();
    _weather = widget.initialWeather;
    if (_weather == null) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final weather = await widget.loadWeather();
    if (!mounted) return;
    setState(() {
      _weather = weather;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.58,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAF4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Farm weather',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh weather',
                          onPressed: _loading ? null : _refresh,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    Text(
                      weather?.locationLabel ?? widget.locationQuery,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (weather == null)
                      _weatherUnavailable()
                    else ...[
                      _currentConditions(weather),
                      const SizedBox(height: 22),
                      _hourlyChart(weather),
                      const SizedBox(height: 22),
                      _dailyForecast(weather),
                      const SizedBox(height: 14),
                      Text(
                        'Updated ${DateFormat('h:mm a').format(weather.fetchedAt.toLocal())}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(weather.providerName == 'Open-Meteo'
                                ? 'https://open-meteo.com/'
                                : 'https://www.weatherapi.com/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label:
                              Text('Weather data by ${weather.providerName}'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textGray,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherUnavailable() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            _loading ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined,
            size: 42,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            _loading ? 'Loading live farm weather…' : 'Weather is unavailable',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          if (!_loading) ...[
            const SizedBox(height: 6),
            const Text(
              'Check the farm address in your profile and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGray),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _currentConditions(FarmWeatherSnapshot weather) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _conditionIcon(
                weather.conditionLabel,
                weather.weatherCode,
                weather.isDay,
                size: 52,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${weather.temperatureC.round()}°',
                      style: const TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _capitalize(weather.conditionLabel),
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                weather.isDay ? 'Day' : 'Night',
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _weatherStat(
                Icons.water_drop_outlined,
                '${weather.relativeHumidity}%',
                'Humidity',
              ),
              _weatherStat(
                Icons.umbrella_outlined,
                '${weather.precipitationMm.toStringAsFixed(1)} mm',
                'Rain now',
              ),
              _weatherStat(
                Icons.air_rounded,
                '${weather.windSpeedKph.round()} km/h',
                'Wind',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weatherStat(IconData icon, String value, String title) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _hourlyChart(FarmWeatherSnapshot weather) {
    final hours = weather.hourlyForecast.take(24).toList(growable: false);
    final values = hours
        .map((hour) => switch (_metric) {
              _WeatherChartMetric.temperature => hour.temperatureC,
              _WeatherChartMetric.rainChance =>
                hour.precipitationProbability.toDouble(),
              _WeatherChartMetric.wind => hour.windSpeedKph,
            })
        .toList(growable: false);
    final title = switch (_metric) {
      _WeatherChartMetric.temperature => 'Temperature',
      _WeatherChartMetric.rainChance => 'Rain chance',
      _WeatherChartMetric.wind => 'Wind speed',
    };
    final unit = switch (_metric) {
      _WeatherChartMetric.temperature => '°C',
      _WeatherChartMetric.rainChance => '%',
      _WeatherChartMetric.wind => 'km/h',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hourly forecast',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            children: [
              _metricButton(_WeatherChartMetric.temperature, 'Temperature'),
              _metricButton(_WeatherChartMetric.rainChance, 'Rain'),
              _metricButton(_WeatherChartMetric.wind, 'Wind'),
            ],
          ),
          const SizedBox(height: 12),
          if (hours.length < 2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Hourly forecast is not available.',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
            )
          else
            SizedBox(
              height: 178,
              child: LineChart(
                LineChartData(
                  minY: _minimum(values),
                  maxY: _maximum(values),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _gridInterval(values),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textGray,
                        ),
                      ),
                      sideTitles: const SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 10,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval:
                            math.max(1, (hours.length / 5).floor()).toDouble(),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= hours.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              DateFormat('ha')
                                  .format(hours[index].time.toLocal())
                                  .toLowerCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.textGray,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values
                          .asMap()
                          .entries
                          .map((entry) => FlSpot(
                                entry.key.toDouble(),
                                entry.value,
                              ))
                          .toList(growable: false),
                      isCurved: true,
                      barWidth: 3,
                      color: AppColors.primary,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) =>
                            spot.x.round() % 4 == 0,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: AppColors.primary,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            '$title for the next 24 hours',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }

  Widget _metricButton(_WeatherChartMetric metric, String label) {
    final selected = _metric == metric;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _metric = metric),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppColors.textGray,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: const Color(0xFFF1F5F0),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }

  Widget _dailyForecast(FarmWeatherSnapshot weather) {
    if (weather.dailyForecast.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '3-day forecast',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: weather.dailyForecast
                .take(3)
                .toList(growable: false)
                .asMap()
                .entries
                .map((entry) {
              final day = entry.value;
              final isToday = _sameDate(day.date, DateTime.now());
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Text(
                            isToday
                                ? 'Today'
                                : DateFormat('EEE').format(day.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        _conditionIcon(
                          day.conditionLabel,
                          day.weatherCode,
                          true,
                          size: 25,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _capitalize(day.conditionLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textGray,
                            ),
                          ),
                        ),
                        Text(
                          '${day.precipitationProbability}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4779A7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${day.highC.round()}°',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${day.lowC.round()}°',
                          style: const TextStyle(color: AppColors.textGray),
                        ),
                      ],
                    ),
                  ),
                  if (entry.key < math.min(weather.dailyForecast.length, 3) - 1)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: AppColors.primary.withValues(alpha: 0.10),
                    ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _conditionIcon(
    String condition,
    int code,
    bool isDay, {
    required double size,
  }) {
    final lower = condition.toLowerCase();
    final isStorm = lower.contains('thunder') || code == 95 || code >= 96;
    final isRain = lower.contains('rain') ||
        lower.contains('drizzle') ||
        lower.contains('shower') ||
        (code >= 51 && code <= 67) ||
        (code >= 80 && code <= 82);
    final isSnow = lower.contains('snow') || (code >= 71 && code <= 86);
    final isFog = lower.contains('fog') ||
        lower.contains('mist') ||
        code == 45 ||
        code == 48;
    final isCloudy = lower.contains('cloud') ||
        lower.contains('overcast') ||
        lower.contains('partly') ||
        lower.contains('mainly clear') ||
        code == 1 ||
        code == 2 ||
        code == 3;

    if (isStorm) {
      return Icon(Icons.thunderstorm_rounded,
          size: size, color: const Color(0xFF64748B));
    }
    if (isRain) {
      return Icon(Icons.cloudy_snowing,
          size: size, color: const Color(0xFF5385A8));
    }
    if (isSnow) {
      return Icon(Icons.ac_unit_rounded,
          size: size, color: const Color(0xFF69A3C3));
    }
    if (isFog) {
      return Icon(Icons.foggy, size: size, color: const Color(0xFF82919B));
    }
    if (isCloudy) {
      final isPartlyCloudy = lower.contains('partly') ||
          lower.contains('mainly clear') ||
          code == 1 ||
          code == 2;
      if (!isPartlyCloudy) {
        return Icon(Icons.cloud_rounded,
            size: size, color: const Color(0xFF82919B));
      }
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Icon(
                isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                size: size * 0.68,
                color:
                    isDay ? const Color(0xFFF4A62A) : const Color(0xFF526F93),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(
                Icons.cloud_rounded,
                size: size * 0.72,
                color: const Color(0xFF82919B),
              ),
            ),
          ],
        ),
      );
    }
    return Icon(
      isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
      size: size,
      color: isDay ? const Color(0xFFF4A62A) : const Color(0xFF526F93),
    );
  }

  double _minimum(List<double> values) {
    if (values.isEmpty) return 0;
    final min = values.reduce(math.min);
    return (min / 10).floorToDouble() * 10;
  }

  double _maximum(List<double> values) {
    if (values.isEmpty) return 100;
    final max = values.reduce(math.max);
    return (max / 10).ceilToDouble() * 10 + 10;
  }

  double _gridInterval(List<double> values) {
    if (values.isEmpty) return 10;
    final span = _maximum(values) - _minimum(values);
    return math.max(5, (span / 4).ceilToDouble());
  }

  String _capitalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
