import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pace/data/database.dart';
import 'package:pace/data/exporters.dart';
import 'package:pace/data/importers.dart';
import 'package:pace/data/point_codec.dart';
import 'package:pace/domain/bike_records.dart';
import 'package:pace/domain/calc.dart';
import 'package:pace/domain/models.dart';
import 'package:pace/services/speech.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// GPX de pedal: ~25 km/h, 1 ponto por segundo.
String bikeGpx({required DateTime start, double km = 21, String type = 'cycling'}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><type>$type</type><trkseg>');
  final n = (km * 1000 / 7).round();
  for (var i = 0; i <= n; i++) {
    final t = start.add(Duration(seconds: i)).toIso8601String().replaceFirst('.000', '');
    b.writeln('<trkpt lat="${(-22.8 + i * 7 / 111195).toStringAsFixed(7)}" lon="-45.2000000"><ele>${540 + (i % 600) / 20}</ele><time>$t</time></trkpt>');
  }
  b.writeln('</trkseg></trk></gpx>');
  return b.toString();
}

void main() {
  test('importa GPX de ciclismo como pedal, sem cortar a velocidade de 25 km/h', () {
    final b = ActivityParser.parse('pedal.gpx', utf8.encode(bikeGpx(start: DateTime.utc(2026, 11, 22, 7))));
    expect(b.activity.sport, Sport.bike);
    expect(b.activity.type, 'Pedal livre');
    expect(b.activity.km, closeTo(21, 0.1));
    expect(b.activity.kmh, closeTo(25.2, 0.3));
    // Calorias pelo MET do pedal (25 km/h → 12 MET), não pela regra da corrida.
    expect(b.activity.calories, closeTo(12 * 70 * b.activity.movingSec / 3600, 1));
  });

  test('TCX Biking vira pedal; Running continua corrida', () {
    expect(ActivityParser.sportFromText('Biking'), Sport.bike);
    expect(ActivityParser.sportFromText('Running'), Sport.run);
    expect(ActivityParser.sportFromText('running'), Sport.run);
    expect(ActivityParser.sportFromText('Morning Ride'), Sport.bike);
  });

  test('exporta e reimporta mantendo a modalidade', () {
    final b = ActivityParser.parse('pedal.gpx', utf8.encode(bikeGpx(start: DateTime.utc(2026, 11, 22, 7), km: 5)));
    expect(ActivityParser.parse('x.gpx', utf8.encode(GpxWriter.write(b))).activity.sport, Sport.bike);
    expect(ActivityParser.parse('x.tcx', utf8.encode(TcxWriter.write(b))).activity.sport, Sport.bike);
  });

  test('pontos de pedal importado são compactados (recalculáveis) e voltam idênticos', () {
    final b = ActivityParser.parse('pedal.gpx', utf8.encode(bikeGpx(start: DateTime.utc(2026, 11, 22, 7), km: 3)));
    final m = PointCodec.encode(b.points);
    expect(m['dist'], 'calc30');
    final back = PointCodec.decode(jsonDecode(jsonEncode(m)) as Map<String, Object?>);
    for (var i = 0; i < b.points.length; i++) {
      expect(back[i].toMap(0, i), b.points[i].toMap(0, i));
    }
  });

  test('banco antigo (versão 1) ganha a coluna sport e tudo vira corrida', () async {
    sqfliteFfiInit();
    final path = '${inMemoryDatabasePath}_v1_${DateTime.now().microsecondsSinceEpoch}';
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE activities (id INTEGER PRIMARY KEY AUTOINCREMENT, start INTEGER NOT NULL, end_time INTEGER, '
                'moving_sec INTEGER NOT NULL DEFAULT 0, elapsed_sec INTEGER NOT NULL DEFAULT 0, distance_m REAL NOT NULL DEFAULT 0, '
                'calories REAL, elev_gain REAL NOT NULL DEFAULT 0, elev_loss REAL NOT NULL DEFAULT 0, avg_hr INTEGER, max_hr INTEGER, '
                "avg_cad INTEGER, type TEXT NOT NULL DEFAULT 'Corrida livre', notes TEXT NOT NULL DEFAULT '', source TEXT NOT NULL, "
                'source_file TEXT, gps_partial INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, best_km_sec INTEGER, '
                "lap_count INTEGER NOT NULL DEFAULT 0, preview TEXT NOT NULL DEFAULT '')");
            await db.insert('activities', {'start': 1700000000000, 'distance_m': 5000, 'moving_sec': 1500, 'source': 'gravada', 'status': 'concluida'});
          },
        ));
    await old.close();
    final db = await PaceDatabase.open(factory: databaseFactoryFfi, path: path);
    final a = (await db.db.query('activities')).single;
    expect(a['sport'], 'corrida');
    expect(Activity.fromMap(a).sport, Sport.run);
    await db.db.close();
  });

  test('pedal salvo no banco continua pedal', () async {
    final db = await openTestDb();
    final b = ActivityParser.parse('pedal.gpx', utf8.encode(bikeGpx(start: DateTime.utc(2026, 11, 22, 7), km: 2)));
    await db.insertBundle(b);
    expect((await db.listActivities()).single.sport, Sport.bike);
    await db.close();
  });

  test('pausa automática do pedal: só pausa abaixo de ~5 km/h', () {
    final ap = AutoPause()..setSport(Sport.bike);
    final t0 = DateTime.utc(2026);
    for (var i = 0; i <= 6; i++) {
      ap.update(t0.add(Duration(seconds: i)), 2.0); // 7 km/h: pedalando devagar
    }
    expect(ap.paused, isFalse);
    for (var i = 7; i <= 14; i++) {
      ap.update(t0.add(Duration(seconds: i)), 0.5);
    }
    expect(ap.paused, isTrue);
  });

  test('GPS do pedal aceita 50 km/h (descida) e a corrida não', () {
    final last = TrackPoint(time: DateTime.utc(2026), lat: -22.8, lon: -45.2);
    final lat2 = -22.8 + 14 / 111195; // 14 m em 1 s ≈ 50 km/h
    final t = DateTime.utc(2026).add(const Duration(seconds: 1));
    expect(GpsFilter.check(accuracy: 5, lat: lat2, lon: -45.2, time: t, lastAccepted: last), GpsVerdict.impossibleJump);
    expect(GpsFilter.check(accuracy: 5, lat: lat2, lon: -45.2, time: t, lastAccepted: last, maxSpeed: Sport.bike.maxSpeedMps),
        GpsVerdict.accept);
  });

  test('fala da velocidade', () {
    expect(Speech.kmh(24.4), '24 quilômetros por hora.');
    expect(Speech.kmh(1.2), '1 quilômetro por hora.');
    expect(Speech.kmCount(150), '150 quilômetros.');
  });

  test('recordes do pedal', () {
    Activity r(double km, int sec, {double up = 0}) =>
        Activity(id: km.round(), start: DateTime.utc(2026, 1, km.round()), distanceM: km * 1000, movingSec: sec, elevGain: up, sport: Sport.bike);
    final recs = BikeRecords.compute([r(25, 3600, up: 300), r(45, 6000), r(10, 1200)]);
    expect(recs[0].activity!.km, 45);
    expect(recs[2].activity!.km, 45); // 27 km/h > 25 km/h
    expect(recs[3].activity!.km, 45);
    expect(recs[4].value, 300);
  });
}
