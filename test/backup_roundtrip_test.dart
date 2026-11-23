import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pace/data/exporters.dart';
import 'package:pace/data/import_service.dart';
import 'package:pace/data/importers.dart';
import 'package:pace/domain/models.dart';

import 'helpers.dart';

/// Garante que o backup do pCloud (sem .gpx) devolve TUDO, campo por campo.
void main() {
  test('backup sem GPX restaura corridas, pontos, parciais, voltas, perfil e ajustes idênticos', () async {
    final db = await openTestDb();
    await db.saveProfile(const UserProfile(name: 'Júlio', weightKg: 72, weeklyGoalKm: 20));
    await db.setKv('voice_every_km', '2');
    await db.setKv('pcloud', '{"token":"segredo"}');
    await ImportService.run(db, [
      ImportItem('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx')),
      ImportItem('a.gpx', utf8.encode(syntheticGpx(startUtc: DateTime.utc(2026, 11, 20, 9)))),
      ImportItem('b.gpx', utf8.encode(syntheticGpx(startUtc: DateTime.utc(2026, 11, 21, 7), distanceM: 10300))),
    ]);

    final full = await BackupCodec.build(db);
    final cloud = await BackupCodec.build(db, gpx: false);
    final names = ZipDecoder().decodeBytes(cloud).files.map((f) => f.name).toList();
    expect(names, ['backup.json']);
    expect(cloud.length, lessThan(full.length));

    final fresh = await openTestDb();
    final r = await BackupCodec.restore(fresh, cloud);
    expect(r.restored, 3);

    // Perfil e ajustes (o acesso ao pCloud nunca vai no backup).
    expect((await fresh.getProfile()).toJson(), (await db.getProfile()).toJson());
    expect(await fresh.getKv('voice_every_km'), '2');
    expect(await fresh.getKv('pcloud'), isNull);

    final a = await db.listActivities();
    final b = await fresh.listActivities();
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      final x = (await db.getBundle(a[i].id!))!;
      final y = (await fresh.getBundle(b[i].id!))!;
      expect(y.activity.toMap()..remove('id'), x.activity.toMap()..remove('id'));
      expect(y.points.length, x.points.length);
      for (var k = 0; k < x.points.length; k++) {
        expect(y.points[k].toMap(0, k), x.points[k].toMap(0, k), reason: 'ponto $k da corrida $i');
      }
      expect([for (final s in y.splits) s.toMap(0)], [for (final s in x.splits) s.toMap(0)]);
      expect([for (final l in y.laps) l.toMap(0)], [for (final l in x.laps) l.toMap(0)]);
    }
    await db.close();
    await fresh.close();
  });
}
