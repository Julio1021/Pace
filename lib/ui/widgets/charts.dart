import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Gráfico de barras de quilometragem (um rótulo por barra). Toque mostra o valor.
class KmBarChart extends StatelessWidget {
  final List<({String label, double km})> data;
  final double height;
  final int? highlightIndex;
  final int labelEvery;

  const KmBarChart({super.key, required this.data, this.height = 160, this.highlightIndex, this.labelEvery = 1});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final maxKm = data.fold<double>(0, (m, e) => math.max(m, e.km));
    final top = maxKm <= 0 ? 5.0 : _niceCeil(maxKm * 1.15);
    final barW = data.length > 20 ? 6.0 : (data.length > 10 ? 10.0 : 18.0);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: muted.withValues(alpha: 0.15), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: top / 4,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(_fmtAxis(v), style: TextStyle(fontSize: 10, color: muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox.shrink();
                  if (i % labelEvery != 0 && i != data.length - 1) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(data[i].label, style: TextStyle(fontSize: 10, color: muted)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${data[group.x].label}\n${rod.toY.toStringAsFixed(1).replaceAll('.', ',')} km',
                TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].km,
                    width: barW,
                    color: i == highlightIndex ? cs.secondary : cs.primary,
                    borderRadius: BorderRadius.circular(barW / 2.5),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: top,
                      color: muted.withValues(alpha: 0.06),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtAxis(double v) => v >= 10 ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
}

double _niceCeil(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final n = v / mag;
  final double nice = n <= 1 ? 1.0 : n <= 2 ? 2.0 : n <= 2.5 ? 2.5 : n <= 5 ? 5.0 : 10.0;
  return nice * mag;
}

/// Linha ao longo da distância (pace, altitude, velocidade).
/// Para pace, [invert] = true coloca o ritmo mais rápido no alto.
class DistanceLineChart extends StatelessWidget {
  final List<({double x, double y})> data;
  final Color color;
  final String Function(double) formatY;
  final bool invert;
  final double height;
  final bool fill;

  const DistanceLineChart({
    super.key,
    required this.data,
    required this.color,
    required this.formatY,
    this.invert = false,
    this.height = 170,
    this.fill = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    if (data.length < 2) return const SizedBox.shrink();
    var minY = data.map((e) => e.y).reduce(math.min);
    var maxY = data.map((e) => e.y).reduce(math.max);
    if (maxY - minY < 1) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.12;
    minY -= pad;
    maxY += pad;
    final maxX = data.last.x;
    double ty(double y) => invert ? -y : y;
    final spots = data.map((e) => FlSpot(e.x, ty(e.y))).toList();
    final lo = invert ? -maxY : minY;
    final hi = invert ? -minY : maxY;
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: lo,
          maxY: hi,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (hi - lo) / 3,
            getDrawingHorizontalLine: (_) => FlLine(color: muted.withValues(alpha: 0.15), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: (hi - lo) / 3,
                getTitlesWidget: (v, meta) {
                  if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(formatY(invert ? -v : v), style: TextStyle(fontSize: 10, color: muted)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: _xInterval(maxX),
                getTitlesWidget: (v, meta) {
                  if (v == meta.max && v % _xInterval(maxX) != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text('${v.round()} km', style: TextStyle(fontSize: 10, color: muted)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.x.toStringAsFixed(2).replaceAll('.', ',')} km\n${formatY(invert ? -s.y : s.y)}',
                        TextStyle(color: cs.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: fill,
                applyCutOffY: true,
                cutOffY: lo,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _xInterval(double maxX) {
    if (maxX <= 3) return 1;
    if (maxX <= 12) return 2;
    if (maxX <= 25) return 5;
    return 10;
  }
}
