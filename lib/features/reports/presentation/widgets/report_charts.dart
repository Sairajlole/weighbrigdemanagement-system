import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

/// Line chart showing net tonnage trend over days
class TonnageTrendChart extends StatelessWidget {
  final Map<String, double> dailyTonnage; // date string → tonnes
  final ColorScheme scheme;

  const TonnageTrendChart({super.key, required this.dailyTonnage, required this.scheme});

  @override
  Widget build(BuildContext context) {
    if (dailyTonnage.isEmpty) return const SizedBox.shrink();

    final entries = dailyTonnage.entries.toList();
    final maxY = entries.map((e) => e.value).reduce(max);
    final spots = entries.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();

    return Container(
      height: 200,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net Tonnage Trend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.15), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}T', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20, interval: max(1, entries.length / 6).toDouble(), getTitlesWidget: (v, _) { final i = v.toInt(); return i < entries.length ? Text(entries[i].key.substring(0, 5), style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)) : const SizedBox.shrink(); })),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: scheme.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(show: spots.length < 15),
                    belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.08)),
                  ),
                ],
                minY: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Donut chart for material or customer breakdown
class BreakdownDonutChart extends StatelessWidget {
  final String title;
  final Map<String, double> data; // name → value
  final ColorScheme scheme;

  const BreakdownDonutChart({super.key, required this.title, required this.data, required this.scheme});

  static const _colors = [
    Color(0xFF0D9488), Color(0xFF2563EB), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF10B981),
    Color(0xFFEC4899), Color(0xFF6366F1),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final sorted = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final total = data.values.fold(0.0, (a, b) => a + b);

    return Container(
      height: 220,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: top.asMap().entries.map((e) {
                        final pct = total > 0 ? (e.value.value / total * 100) : 0.0;
                        return PieChartSectionData(
                          value: e.value.value,
                          color: _colors[e.key % _colors.length],
                          radius: 40,
                          title: '${pct.toStringAsFixed(0)}%',
                          titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: top.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: _colors[e.key % _colors.length], borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.value.key, style: TextStyle(fontSize: 11, color: scheme.onSurface), overflow: TextOverflow.ellipsis)),
                          Text('${(e.value.value / 1000).toStringAsFixed(1)}T', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Heatmap grid — hour (Y) × day-of-week (X)
class ActivityHeatmap extends StatelessWidget {
  final List<List<int>> grid; // 7 days × 24 hours
  final ColorScheme scheme;

  const ActivityHeatmap({super.key, required this.grid, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final maxVal = grid.expand((r) => r).fold(0, max);

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity Heatmap (Hour × Day)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y-axis labels (hours)
              Column(
                children: List.generate(24, (h) => SizedBox(
                  height: 14,
                  child: Text('${h}h', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                )),
              ),
              const SizedBox(width: 6),
              // Grid
              Expanded(
                child: Column(
                  children: [
                    // X-axis labels (days)
                    Row(
                      children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => Expanded(
                        child: Center(child: Text(d, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant))),
                      )).toList(),
                    ),
                    const SizedBox(height: 4),
                    // Cells
                    ...List.generate(24, (h) => Row(
                      children: List.generate(7, (d) {
                        final val = d < grid.length && h < grid[d].length ? grid[d][h] : 0;
                        final intensity = maxVal > 0 ? val / maxVal : 0.0;
                        return Expanded(
                          child: Container(
                            height: 12,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: intensity == 0
                                  ? scheme.surfaceContainerLow
                                  : scheme.primary.withValues(alpha: 0.15 + intensity * 0.85),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal bar chart for rankings (customers, operators)
class RankingBars extends StatelessWidget {
  final String title;
  final Map<String, double> data;
  final String unit;
  final ColorScheme scheme;

  const RankingBars({super.key, required this.title, required this.data, required this.unit, required this.scheme});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final sorted = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();
    final maxVal = top.isNotEmpty ? top.first.value : 1.0;

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 12),
          ...top.map((e) {
            final pct = maxVal > 0 ? e.value / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 100, child: Text(e.key, style: TextStyle(fontSize: 11, color: scheme.onSurface), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(height: 16, decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(4))),
                        FractionallySizedBox(
                          widthFactor: pct,
                          child: Container(height: 16, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: Text('${e.value.toStringAsFixed(1)} $unit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant), textAlign: TextAlign.end)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
