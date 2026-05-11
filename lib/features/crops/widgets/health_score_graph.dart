import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/health_score_service.dart';

/// Renders a 14-day health-score line chart. Stateless — selection state
/// is owned by the parent screen and passed in via [selectedDate].
class HealthScoreGraph extends StatelessWidget {
  final List<HealthScorePoint> points;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onPointTap;

  const HealthScoreGraph({
    required this.points,
    required this.selectedDate,
    required this.onPointTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _emptyState();
    }

    final hasAnyTasks =
        points.any((p) => p.totalTasks > 0 || p.latestSeverity != null);
    if (!hasAnyTasks) {
      return _emptyState();
    }

    final selectedIdx = _indexForDate(selectedDate);

    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].score.toDouble()),
    ];

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.textLightGray.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 30,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textGray),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 3,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    DateFormat('M/d').format(points[i].date),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textGray),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.primaryDark,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final p = points[i];
                return LineTooltipItem(
                  '${DateFormat('MMM d').format(p.date)}\n'
                  'Score ${p.score} · ${_statusLabel(p.status)}',
                  const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                );
              }).toList(),
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent &&
                  response?.lineBarSpots != null &&
                  response!.lineBarSpots!.isNotEmpty) {
                final i = response.lineBarSpots!.first.x.toInt();
                if (i >= 0 && i < points.length) {
                  onPointTap(points[i].date);
                }
              }
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final isSelected = index == selectedIdx;
                  return FlDotCirclePainter(
                    radius: isSelected ? 6 : 3,
                    color: isSelected ? AppColors.primaryDark : AppColors.primary,
                    strokeColor: Colors.white,
                    strokeWidth: isSelected ? 2 : 1,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _indexForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (int i = 0; i < points.length; i++) {
      if (points[i].date == d) return i;
    }
    return points.length - 1; // fall back to "today"
  }

  String _statusLabel(ProgressStatus s) {
    switch (s) {
      case ProgressStatus.improving:
        return 'Improving';
      case ProgressStatus.worsening:
        return 'Worsening';
      case ProgressStatus.stable:
        return 'Stable';
      default:
        return 'Tracking';
    }
  }

  Widget _emptyState() {
    return Container(
      height: 140,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textLightGray.withValues(alpha: 0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Add a diagnosis or complete tasks to start tracking your crop\'s health.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppColors.textGray, fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}
