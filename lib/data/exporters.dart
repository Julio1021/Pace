import 'dart:convert';

import 'package:archive/archive.dart';

import '../domain/models.dart';
import 'database.dart';

String _iso(DateTime t) => t.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Nome de arquivo padrão: pace_2026-11-22_0741.gpx
String exportFileName(Activity a, String ext) {
  final l = a.start.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'pace_${l.year}-${two(l.month)}-${two(l.day)}_${two(l.hour)}${two(l.minute)}.$ext';
}

class GpxWriter {
  static String write(ActivityBundle b) {
    final a = b.activity;
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="PACE" xmlns="http://www.topografix.com/GPX/1/1" '
          'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">')
      ..writeln('  <metadata><time>${_iso(a.start)}</time></metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_esc(a.type)}</name>')
      ..writeln('    <type>running</type>');
    if (a.notes.isNotEmpty) buf.writeln('    <desc>${_esc(a.notes)}</desc>');
    buf.writeln('    <trkseg>');
    for (final p in b.points) {
      buf.write('      <trkpt lat="${p.lat.toStringAsFixed(7)}" lon="${p.lon.toStringAsFixed(7)}">');
      if (p.alt != null) buf.write('<ele>${p.alt!.toStringAsFixed(1)}</ele>');
      buf.write('<time>${_iso(p.time)}</time>');
      if (p.hr != null || p.cad != null) {
        buf.write('<extensions><gpxtpx:TrackPointExtension>');
        if (p.hr != null) buf.write('<gpxtpx:hr>${p.hr}</gpxtpx:hr>');
        if (p.cad != null) buf.write('<gpxtpx:cad>${p.cad}</gpxtpx:cad>');
        buf.write('</gpxtpx:TrackPointExtension></extensions>');
      }
      buf.writeln('</trkpt>');
    }
    buf
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buf.toString();
  }
}

class TcxWriter {
  static String write(ActivityBundle b) {
    final a = b.activity;
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
          'xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">')
      ..writeln('  <Activities>')
      ..writeln('    <Activity Sport="Running">')
      ..writeln('      <Id>${_iso(a.start)}</Id>')
      ..writeln('      <Lap StartTime="${_iso(a.start)}">')
      ..writeln('        <TotalTimeSeconds>${a.movingSec}</TotalTimeSeconds>')
      ..writeln('        <DistanceMeters>${a.distanceM.toStringAsFixed(1)}</DistanceMeters>')
      ..writeln('        <Calories>${(a.calories ?? 0).round()}</Calories>');
    if (a.avgHr != null) {
      buf.writeln('        <AverageHeartRateBpm><Value>${a.avgHr}</Value></AverageHeartRateBpm>');
    }
    if (a.maxHr != null) {
      buf.writeln('        <MaximumHeartRateBpm><Value>${a.maxHr}</Value></MaximumHeartRateBpm>');
    }
    buf
      ..writeln('        <Intensity>Active</Intensity>')
      ..writeln('        <TriggerMethod>Manual</TriggerMethod>')
      ..writeln('        <Track>');
    for (final p in b.points) {
      buf.write('          <Trackpoint><Time>${_iso(p.time)}</Time>'
          '<Position><LatitudeDegrees>${p.lat.toStringAsFixed(7)}</LatitudeDegrees>'
          '<LongitudeDegrees>${p.lon.toStringAsFixed(7)}</LongitudeDegrees></Position>');
      if (p.alt != null) buf.write('<AltitudeMeters>${p.alt!.toStringAsFixed(1)}</AltitudeMeters>');
      buf.write('<DistanceMeters>${p.dist.toStringAsFixed(1)}</DistanceMeters>');
      if (p.hr != null) buf.write('<HeartRateBpm><Value>${p.hr}</Value></HeartRateBpm>');
      if (p.speed != null || p.cad != null) {
        buf.write('<Extensions><ns3:TPX>');
        if (p.speed != null) buf.write('<ns3:Speed>${p.speed!.toStringAsFixed(2)}</ns3:Speed>');
        if (p.cad != null) buf.write('<ns3:RunCadence>${p.cad}</ns3:RunCadence>');
        buf.write('</ns3:TPX></Extensions>');
      }
      buf.writeln('</Trackpoint>');
    }
    buf
      ..writeln('        </Track>')
      ..writeln('      </Lap>');
    if (a.notes.isNotEmpty) buf.writeln('      <Notes>${_esc(a.notes)}</Notes>');
    buf
      ..writeln('    </Activity>')
      ..writeln('  </Activities>')
      ..writeln('</TrainingCenterDatabase>');
    return buf.toString();
  }
}

/// Backup completo: um .zip com backup.json (tudo: corridas, pontos, perfil e configurações).
/// Opcionalmente inclui um .gpx por corrida, só para abrir em outros apps (a restauração não usa).
class BackupCodec {
  /// Chaves que não vão no backup: perfil (já vai à parte), acesso ao pCloud e caches.
  static const _skipKv = {'profile', 'pcloud', 'weather', 'efforts_v1'};

  static const format = 'pace-backup';
  static const formatVersion = 1;

  static Future<List<int>> build(PaceDatabase db, {bool gpx = true}) async {
    final profile = await db.getProfile();
    final acts = await db.listActivities();
    final arc = Archive();
    final list = <Map<String, Object?>>[];
    for (final a in acts) {
      final b = await db.getBundle(a.id!);
      if (b == null) continue;
      list.add({
        'activity': b.activity.toMap()..remove('id'),
        'points': [for (var i = 0; i < b.points.length; i++) b.points[i].toMap(0, i)..remove('activity_id')],
        'splits': [for (final s in b.splits) s.toMap(0)..remove('activity_id')],
        'laps': [for (final l in b.laps) l.toMap(0)..remove('activity_id')],
      });
      if (gpx && b.points.isNotEmpty) {
        arc.addFile(ArchiveFile.string('gpx/${exportFileName(a, 'gpx')}', GpxWriter.write(b)));
      }
    }
    final json = jsonEncode({
      'format': format,
      'version': formatVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'profile': profile.toJson(),
      'settings': {
        for (final e in (await db.allKv()).entries)
          if (!_skipKv.contains(e.key)) e.key: e.value,
      },
      'activities': list,
    });
    arc.addFile(ArchiveFile.string('backup.json', json));
    return ZipEncoder().encodeBytes(arc, level: 9);
  }

  /// Restaura um backup. Corridas que já existem (mesmo início e distância) são ignoradas.
  /// Devolve (restauradas, ignoradas).
  static Future<({int restored, int skipped})> restore(PaceDatabase db, List<int> zipBytes) async {
    final Archive arc;
    try {
      arc = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const FormatException('O arquivo escolhido não é um backup do PACE (.zip).');
    }
    final entry = arc.files.where((f) => f.isFile && f.name.endsWith('backup.json')).firstOrNull;
    if (entry == null) throw const FormatException('backup.json não encontrado no arquivo.');
    final data = jsonDecode(utf8.decode(entry.content)) as Map<String, Object?>;
    if (data['format'] != format) throw const FormatException('Arquivo não reconhecido como backup do PACE.');
    final profile = data['profile'];
    if (profile is Map<String, Object?>) {
      final current = await db.getProfile();
      if (!current.isComplete) await db.saveProfile(UserProfile.fromJson(profile));
    }
    // Configurações: só preenche o que ainda não existe no celular.
    final settings = data['settings'];
    if (settings is Map) {
      final current = await db.allKv();
      for (final e in settings.entries) {
        final k = '${e.key}';
        if (_skipKv.contains(k) || current.containsKey(k)) continue;
        await db.setKv(k, '${e.value}');
      }
    }
    var restored = 0;
    var skipped = 0;
    for (final raw in (data['activities'] as List? ?? const [])) {
      final m = raw as Map<String, Object?>;
      final a = Activity.fromMap(Map<String, Object?>.from(m['activity'] as Map));
      if (await db.findDuplicate(a.start, a.distanceM) != null) {
        skipped++;
        continue;
      }
      List<Map<String, Object?>> rows(String k) =>
          (m[k] as List? ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
      await db.insertBundle(ActivityBundle(
        activity: a,
        points: rows('points').map(TrackPoint.fromMap).toList(),
        splits: rows('splits').map(Split.fromMap).toList(),
        laps: rows('laps').map(Lap.fromMap).toList(),
      ));
      restored++;
    }
    return (restored: restored, skipped: skipped);
  }
}
