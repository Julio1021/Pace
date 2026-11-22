import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/calc.dart';
import '../domain/models.dart';

/// Erro de leitura de um arquivo importado.
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Converte arquivos TCX e GPX em atividades completas.
class ActivityParser {
  /// Se os pontos de GPS cobrirem menos que isso da distância do resumo, o trajeto é parcial.
  static const partialThreshold = 0.9;

  static ActivityBundle parse(String fileName, List<int> bytes, {double weightKg = 70}) {
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tcx')) return parseTcx(text, fileName: fileName, weightKg: weightKg);
    if (lower.endsWith('.gpx')) return parseGpx(text, fileName: fileName, weightKg: weightKg);
    throw ImportException('Formato não suportado');
  }

  static XmlElement? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static Iterable<XmlElement> _children(XmlElement e, String local) =>
      e.childElements.where((c) => c.name.local == local);

  static Iterable<XmlElement> _descendants(XmlNode e, String local) =>
      e.descendants.whereType<XmlElement>().where((c) => c.name.local == local);

  static double? _d(XmlElement? e) => e == null ? null : double.tryParse(e.innerText.trim());

  static DateTime? _time(String? s) {
    if (s == null) return null;
    final t = DateTime.tryParse(s.trim());
    return t?.toUtc();
  }

  // ---------------- TCX ----------------

  static ActivityBundle parseTcx(String xml, {String? fileName, double weightKg = 70}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      throw ImportException('Arquivo TCX inválido');
    }
    final act = _descendants(doc, 'Activity').firstOrNull;
    if (act == null) throw ImportException('Nenhuma atividade no arquivo');

    final laps = _children(act, 'Lap').toList();
    var lapTime = 0.0;
    var lapDist = 0.0;
    double? lapCal;
    for (final l in laps) {
      lapTime += _d(_child(l, 'TotalTimeSeconds')) ?? 0;
      lapDist += _d(_child(l, 'DistanceMeters')) ?? 0;
      final c = _d(_child(l, 'Calories'));
      if (c != null && c > 0) lapCal = (lapCal ?? 0) + c;
    }

    final raw = <TrackPoint>[];
    final hrOnly = <int>[];
    for (final tp in _descendants(act, 'Trackpoint')) {
      final time = _time(_child(tp, 'Time')?.innerText);
      final hrEl = _child(tp, 'HeartRateBpm');
      final hr = hrEl == null ? null : _d(_child(hrEl, 'Value'))?.round();
      final cad = _d(_child(tp, 'Cadence'))?.round() ?? _d(_descendants(tp, 'RunCadence').firstOrNull)?.round();
      final speed = _d(_descendants(tp, 'Speed').firstOrNull);
      final pos = _child(tp, 'Position');
      if (time == null) continue;
      final validHr = (hr != null && hr > 30 && hr < 250) ? hr : null;
      if (pos == null) {
        if (validHr != null) hrOnly.add(validHr);
        continue;
      }
      final lat = _d(_child(pos, 'LatitudeDegrees'));
      final lon = _d(_child(pos, 'LongitudeDegrees'));
      if (lat == null || lon == null) continue;
      raw.add(TrackPoint(
        time: time,
        lat: lat,
        lon: lon,
        alt: _d(_child(tp, 'AltitudeMeters')),
        speed: speed,
        hr: validHr,
        cad: (cad != null && cad > 0) ? cad : null,
      ));
    }
    raw.sort((a, b) => a.time.compareTo(b.time));

    final idText = _child(act, 'Id')?.innerText;
    final lapStart = laps.isEmpty ? null : laps.first.getAttribute('StartTime');
    final start = _time(lapStart) ?? _time(idText) ?? (raw.isNotEmpty ? raw.first.time : null);
    if (start == null) throw ImportException('Arquivo sem data de início');

    return _build(
      start: start,
      points: raw,
      summaryTime: lapTime,
      summaryDist: lapDist,
      summaryCal: lapCal,
      extraHr: hrOnly,
      source: ActivitySource.tcx,
      fileName: fileName,
      weightKg: weightKg,
    );
  }

  // ---------------- GPX ----------------

  static ActivityBundle parseGpx(String xml, {String? fileName, double weightKg = 70}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      throw ImportException('Arquivo GPX inválido');
    }
    final raw = <TrackPoint>[];
    for (final pt in _descendants(doc, 'trkpt')) {
      final lat = double.tryParse(pt.getAttribute('lat') ?? '');
      final lon = double.tryParse(pt.getAttribute('lon') ?? '');
      final time = _time(_child(pt, 'time')?.innerText);
      if (lat == null || lon == null || time == null) continue;
      final hr = _d(_descendants(pt, 'hr').firstOrNull)?.round();
      final cad = _d(_descendants(pt, 'cad').firstOrNull)?.round();
      raw.add(TrackPoint(
        time: time,
        lat: lat,
        lon: lon,
        alt: _d(_child(pt, 'ele')),
        hr: (hr != null && hr > 30 && hr < 250) ? hr : null,
        cad: (cad != null && cad > 0) ? cad : null,
      ));
    }
    if (raw.length < 2) throw ImportException('O arquivo GPX não tem trajeto com horários');
    raw.sort((a, b) => a.time.compareTo(b.time));
    final meta = _descendants(doc, 'metadata').firstOrNull;
    final metaTime = meta == null ? null : _time(_child(meta, 'time')?.innerText);
    final start = raw.first.time;
    return _build(
      start: metaTime != null && metaTime.isBefore(start) && start.difference(metaTime).inMinutes < 30 ? metaTime : start,
      points: raw,
      summaryTime: 0,
      summaryDist: 0,
      summaryCal: null,
      extraHr: const [],
      source: ActivitySource.gpx,
      fileName: fileName,
      weightKg: weightKg,
    );
  }

  // ---------------- Montagem ----------------

  static ActivityBundle _build({
    required DateTime start,
    required List<TrackPoint> points,
    required double summaryTime,
    required double summaryDist,
    required double? summaryCal,
    required List<int> extraHr,
    required ActivitySource source,
    required String? fileName,
    required double weightKg,
  }) {
    final pts = Calc.accumulate(points);
    final ptsDist = pts.isEmpty ? 0.0 : pts.last.dist;
    final ptsMov = pts.isEmpty ? 0.0 : pts.last.mov;

    // Os totais vêm do resumo (Lap) quando existe: no NRC o GPS pode cobrir só parte da corrida.
    final dist = summaryDist > 0 ? summaryDist : ptsDist;
    final moving = summaryTime > 0 ? summaryTime : ptsMov;
    if (dist <= 0 && moving <= 0) throw ImportException('Atividade sem distância nem duração');
    final partial = dist > 0 && ptsDist < dist * partialThreshold;

    final elev = Calc.elevation(pts.map((p) => p.alt).toList());
    final hr = Calc.heartRate(pts);
    int? avgHr = hr.avg;
    int? maxHr = hr.max;
    if (avgHr == null && extraHr.isNotEmpty) {
      avgHr = (extraHr.reduce((a, b) => a + b) / extraHr.length).round();
      maxHr = extraHr.reduce((a, b) => a > b ? a : b);
    }
    final splits = partial ? <Split>[] : Calc.splits(pts);
    final elapsed = pts.length >= 2 ? pts.last.time.difference(start).inSeconds : moving.round();

    final activity = Activity(
      start: start,
      end: start.add(Duration(seconds: elapsed > moving ? elapsed : moving.round())),
      movingSec: moving.round(),
      elapsedSec: elapsed > moving ? elapsed : moving.round(),
      distanceM: dist,
      calories: summaryCal ?? Calc.calories(weightKg, dist),
      elevGain: elev.gain,
      elevLoss: elev.loss,
      avgHr: avgHr,
      maxHr: maxHr,
      avgCad: Calc.avgCadence(pts),
      type: 'Corrida livre',
      source: source,
      sourceFile: fileName,
      gpsPartial: partial,
      status: ActivityStatus.done,
      bestKmSec: Calc.bestKm(splits),
      preview: Calc.preview(pts),
    );
    return ActivityBundle(activity: activity, points: pts, splits: splits);
  }
}

/// Um arquivo a importar (nome + conteúdo).
class ImportItem {
  final String name;
  final List<int> bytes;
  ImportItem(this.name, this.bytes);
}

/// Abre .zip e devolve só os .tcx/.gpx; arquivos soltos passam direto.
List<ImportItem> expandImportFiles(List<ImportItem> files) {
  final out = <ImportItem>[];
  for (final f in files) {
    final n = f.name.toLowerCase();
    if (n.endsWith('.zip')) {
      final Archive arc;
      try {
        arc = ZipDecoder().decodeBytes(f.bytes);
      } catch (_) {
        out.add(ImportItem(f.name, const []));
        continue;
      }
      for (final e in arc) {
        if (!e.isFile) continue;
        final en = e.name.toLowerCase();
        if (en.contains('__macosx')) continue;
        if (en.endsWith('.tcx') || en.endsWith('.gpx')) {
          out.add(ImportItem(e.name.split('/').last, e.content));
        }
      }
    } else if (n.endsWith('.tcx') || n.endsWith('.gpx')) {
      out.add(f);
    }
  }
  return out;
}
