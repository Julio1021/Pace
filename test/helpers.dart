import 'dart:io';
import 'dart:math' as math;

import 'package:pace/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _dbCounter = 0;

/// Banco SQLite temporário (FFI) para testes.
Future<PaceDatabase> openTestDb() async {
  sqfliteFfiInit();
  final path = '${Directory.systemTemp.path}/pace_test_${pid}_${_dbCounter++}.db';
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  return PaceDatabase.open(factory: databaseFactoryFfi, path: path);
}

List<int> fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// Gera um GPX sintético: voltas num circuito de ~1,2 km, 1 ponto por segundo,
/// com variação de ritmo e de altitude. Usado só em testes e prints.
String syntheticGpx({
  required DateTime startUtc,
  double distanceM = 5200,
  double baseSpeed = 3.4,
  double lat0 = -22.80,
  double lon0 = -42.50,
}) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="teste" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>');
  const r = 190.0; // raio do circuito (m)
  var d = 0.0;
  var t = 0;
  while (d <= distanceM) {
    final ang = d / r;
    final dLat = (r * math.sin(ang)) / 111195.0;
    final dLon = (r * (1 - math.cos(ang))) / (111195.0 * math.cos(lat0 * math.pi / 180));
    final ele = 540 + 6 * math.sin(d / 400);
    final time = startUtc.add(Duration(seconds: t)).toIso8601String().replaceFirst('.000', '');
    buf.writeln('<trkpt lat="${(lat0 + dLat).toStringAsFixed(7)}" lon="${(lon0 + dLon).toStringAsFixed(7)}">'
        '<ele>${ele.toStringAsFixed(1)}</ele><time>$time</time></trkpt>');
    final v = baseSpeed + 0.25 * math.sin(d / 900);
    d += v;
    t++;
  }
  buf.writeln('</trkseg></trk></gpx>');
  return buf.toString();
}
