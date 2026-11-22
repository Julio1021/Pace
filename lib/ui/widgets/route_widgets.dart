import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';

/// Permite desligar o carregamento de mapas (usado nos testes e prints).
class MapConfig {
  static bool tilesEnabled = true;
  static const userAgent = 'br.com.julio.pace';
}

/// Miniatura do percurso desenhada localmente (sem baixar mapa).
class RouteThumbnail extends StatelessWidget {
  final List<List<double>> points;
  final double size;
  final Color? color;
  final double strokeWidth;

  const RouteThumbnail({super.key, required this.points, this.size = 56, this.color, this.strokeWidth = 2.5});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: points.length < 2
          ? Icon(Icons.directions_run, color: cs.primary.withValues(alpha: 0.6), size: size * 0.45)
          : CustomPaint(painter: RoutePainter(points, color ?? cs.primary, strokeWidth)),
    );
  }
}

class RoutePainter extends CustomPainter {
  final List<List<double>> pts;
  final Color color;
  final double strokeWidth;

  RoutePainter(this.pts, this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    var minLat = pts.first[0], maxLat = pts.first[0], minLon = pts.first[1], maxLon = pts.first[1];
    for (final p in pts) {
      minLat = math.min(minLat, p[0]);
      maxLat = math.max(maxLat, p[0]);
      minLon = math.min(minLon, p[1]);
      maxLon = math.max(maxLon, p[1]);
    }
    // Corrige a proporção longitude/latitude pela latitude média.
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * k, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    final pad = size.shortestSide * 0.16;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset map(List<double> p) => Offset(ox + (p[1] - minLon) * k * scale, oy + (maxLat - p[0]) * scale);
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (final p in pts.skip(1)) {
      final o = map(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(map(pts.first), strokeWidth * 1.4, Paint()..color = PaceColors.limeDark);
    canvas.drawCircle(map(pts.last), strokeWidth * 1.4, Paint()..color = PaceColors.red);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.pts != pts || old.color != color;
}

/// Mapa interativo (OpenStreetMap) com o percurso, início e fim.
class RouteMap extends StatelessWidget {
  final List<LatLng> points;
  final bool interactive;
  final LatLng? current;
  final MapController? controller;

  const RouteMap({super.key, required this.points, this.interactive = true, this.current, this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final center = current ?? (points.isNotEmpty ? points.last : const LatLng(-15.78, -47.93));
    final fit = points.length >= 2 && current == null
        ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(28), maxZoom: 17)
        : null;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: points.isEmpty && current == null ? 4 : 16,
        initialCameraFit: fit,
        backgroundColor: dark ? const Color(0xFF1B1F27) : const Color(0xFFE9ECF2),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        if (MapConfig.tilesEnabled)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: MapConfig.userAgent,
            maxNativeZoom: 19,
          ),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 5,
                color: cs.primary,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (points.isNotEmpty && current == null)
              Marker(point: points.first, width: 18, height: 18, child: _dot(PaceColors.limeDark)),
            if (points.length >= 2 && current == null)
              Marker(point: points.last, width: 18, height: 18, child: _dot(PaceColors.red)),
            if (current != null) Marker(point: current!, width: 24, height: 24, child: _dot(cs.primary, big: true)),
          ],
        ),
        if (MapConfig.tilesEnabled)
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Colors.black54)),
            ),
          ),
      ],
    );
  }

  Widget _dot(Color c, {bool big = false}) => Container(
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: big ? 3 : 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      );
}
