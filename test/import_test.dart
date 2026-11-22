import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pace/core/format.dart';
import 'package:pace/data/exporters.dart';
import 'package:pace/data/import_service.dart';
import 'package:pace/data/importers.dart';
import 'package:pace/domain/models.dart';

import 'helpers.dart';

void main() {
  group('TCX do Nike Run Club', () {
    test('24/11/2016: totais do resumo, GPS parcial', () {
      final b = ActivityParser.parse('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx'));
      final a = b.activity;
      expect(Fmt.km(a.distanceM), '13,03');
      expect(Fmt.duration(a.movingSec), '1:03:51');
      expect(Fmt.pace(a.paceSecPerKm), '4:54');
      expect(a.calories, 777);
      expect(a.gpsPartial, isTrue);
      expect(a.start, DateTime.utc(2016, 11, 24, 7, 41, 34));
      expect(a.avgHr, isNull); // o arquivo traz FC 0 (sem sensor)
      expect(b.splits, isEmpty);
      expect(b.points.length, 969);
      expect(b.points.last.dist, closeTo(11129, 30));
      expect(a.preview, isNotEmpty);
      expect(a.source, ActivitySource.tcx);
    });

    test('20/11/2016: totais do resumo, GPS parcial', () {
      final b = ActivityParser.parse('nrc_2016-11-20.tcx', fixture('nrc_2016-11-20.tcx'));
      final a = b.activity;
      expect(Fmt.km(a.distanceM), '12,40');
      expect(Fmt.duration(a.movingSec), '1:03:07');
      expect(Fmt.pace(a.paceSecPerKm), '5:06');
      expect(a.calories, 732);
      expect(a.gpsPartial, isTrue);
    });
  });

  group('GPX', () {
    test('trajeto completo gera parciais e pace coerente', () {
      final gpx = syntheticGpx(startUtc: DateTime.utc(2026, 11, 20, 9), distanceM: 5200, baseSpeed: 3.4);
      final b = ActivityParser.parse('treino.gpx', utf8.encode(gpx));
      final a = b.activity;
      expect(a.gpsPartial, isFalse);
      expect(a.distanceM, closeTo(5200, 60));
      expect(b.splits.length, 6);
      expect(b.splits.first.distM, 1000);
      expect(a.paceSecPerKm, closeTo(1000 / 3.4, 12));
      expect(a.bestKmSec, isNotNull);
      expect(a.elevGain, greaterThan(5));
    });

    test('exportar GPX e importar de novo mantém a distância', () {
      final orig = ActivityParser.parse(
        'treino.gpx',
        utf8.encode(syntheticGpx(startUtc: DateTime.utc(2026, 11, 21, 9), distanceM: 3000)),
      );
      final again = ActivityParser.parse('x.gpx', utf8.encode(GpxWriter.write(orig)));
      expect(again.points.length, orig.points.length);
      expect(again.activity.distanceM, closeTo(orig.activity.distanceM, 1));
    });

    test('exportar TCX e importar de novo mantém os totais', () {
      final orig = ActivityParser.parse('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx'));
      final again = ActivityParser.parse('x.tcx', utf8.encode(TcxWriter.write(orig)));
      expect(again.activity.distanceM, closeTo(orig.activity.distanceM, 0.1));
      expect(again.activity.movingSec, orig.activity.movingSec);
      expect(again.activity.calories, orig.activity.calories);
    });
  });

  group('Arquivos inválidos', () {
    test('XML quebrado vira erro legível', () {
      expect(() => ActivityParser.parse('a.tcx', utf8.encode('<nada')), throwsA(isA<ImportException>()));
    });

    test('formato desconhecido', () {
      expect(() => ActivityParser.parse('a.fit', [1, 2, 3]), throwsA(isA<ImportException>()));
    });
  });

  group('Importação com banco', () {
    test('não duplica corridas e lê .zip', () async {
      final db = await openTestDb();
      final r1 = await ImportService.run(db, [
        ImportItem('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx')),
        ImportItem('nrc_2016-11-20.tcx', fixture('nrc_2016-11-20.tcx')),
        ImportItem('foto.jpg', [1, 2, 3]),
      ]);
      expect(r1.imported, 2);
      expect(r1.duplicates, 0);
      expect(r1.errors, isEmpty);

      final zip = Archive()
        ..addFile(ArchiveFile.bytes('NRC/nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx')))
        ..addFile(ArchiveFile.bytes('NRC/quebrado.tcx', utf8.encode('<x')));
      final r2 = await ImportService.run(db, [ImportItem('NRC.zip', ZipEncoder().encodeBytes(zip))]);
      expect(r2.imported, 0);
      expect(r2.duplicates, 1);
      expect(r2.errors.length, 1);

      final list = await db.listActivities();
      expect(list.length, 2);
      expect(list.first.start.isAfter(list.last.start), isTrue);
      await db.close();
    });

    test('backup e restauração', () async {
      final db = await openTestDb();
      await db.saveProfile(const UserProfile(name: 'Júlio', weightKg: 72, weeklyGoalKm: 20));
      await ImportService.run(db, [
        ImportItem('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx')),
        ImportItem('t.gpx', utf8.encode(syntheticGpx(startUtc: DateTime.utc(2026, 11, 20, 9)))),
      ]);
      final zip = await BackupCodec.build(db);

      final fresh = await openTestDb();
      final r = await BackupCodec.restore(fresh, zip);
      expect(r.restored, 2);
      expect((await fresh.getProfile()).name, 'Júlio');
      final acts = await fresh.listActivities();
      expect(acts.length, 2);
      final gpxRun = acts.firstWhere((a) => a.source == ActivitySource.gpx);
      expect((await fresh.getSplits(gpxRun.id!)).length, greaterThan(4));
      expect((await fresh.getPoints(gpxRun.id!)).length, greaterThan(1000));

      // Restaurar de novo não duplica.
      final r2 = await BackupCodec.restore(fresh, zip);
      expect(r2.restored, 0);
      expect(r2.skipped, 2);
      await db.close();
      await fresh.close();
    });
  });
}
