import 'dart:io';

import 'package:flutter/material.dart' hide Split;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/exporters.dart';
import '../../domain/calc.dart';
import '../../domain/records.dart';
import '../widgets/achievement_widgets.dart';
import 'achievements_screen.dart';
import '../widgets/share_card.dart';
import 'records_screen.dart';
import '../../domain/coach.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../widgets/pace_ui.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/route_widgets.dart';

class ActivityDetailScreen extends StatefulWidget {
  final int activityId;
  final bool justFinished;

  const ActivityDetailScreen({super.key, required this.activityId, this.justFinished = false});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  ActivityBundle? _b;
  bool _loading = true;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await context.read<AppState>().db.getBundle(widget.activityId);
    if (!mounted) return;
    setState(() {
      _b = b;
      _loading = false;
      _notes.text = b?.activity.notes ?? '';
    });
  }

  Future<void> _save(Activity a) async {
    await context.read<AppState>().updateActivity(a);
    if (!mounted) return;
    setState(() => _b = ActivityBundle(activity: a, points: _b!.points, splits: _b!.splits, laps: _b!.laps));
  }

  Future<void> _pickType() async {
    final a = _b!.activity;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Tipo de treino', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final t in a.sport.types)
              ListTile(
                title: Text(t),
                trailing: t == a.type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, t),
              ),
          ],
        ),
      ),
    );
    if (v != null && v != a.type) await _save(a.copyWith(type: v));
  }

  Future<void> _saveNotes() async {
    final a = _b!.activity;
    if (_notes.text.trim() == a.notes) return;
    await _save(a.copyWith(notes: _notes.text.trim()));
    if (mounted) showSnack(context, 'Observações salvas');
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: _b!.activity.isBike ? 'Excluir pedal?' : 'Excluir corrida?',
      message: '${_b!.activity.isBike ? 'O pedal' : 'A corrida'} de ${Fmt.date(_b!.activity.start)} (${Fmt.kmUnit(_b!.activity.distanceM)}) será apagada. '
          '${_b!.activity.isBike ? 'Ele será apagado' : 'Isso não pode ser desfeito'}.',
      confirm: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteActivity(widget.activityId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _export(String ext) async {
    final b = _b!;
    final text = ext == 'gpx' ? GpxWriter.write(b) : TcxWriter.write(b);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${exportFileName(b.activity, ext)}');
    await f.writeAsString(text);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: ext == 'gpx' ? 'application/gpx+xml' : 'application/vnd.garmin.tcx+xml')],
      text: '${b.activity.sport.label} de ${Fmt.date(b.activity.start)} — ${Fmt.kmUnit(b.activity.distanceM)}',
    ));
  }

  void _shareImage() {
    final app = context.read<AppState>();
    String? highlight;
    if (!_b!.activity.isBike && app.efforts.containsKey(widget.activityId)) {
      for (final b in Records.brokenBy(widget.activityId, app.activities, app.efforts)) {
        if (b.before != null) {
          highlight = 'Novo recorde: ${b.now.label}';
          break;
        }
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ShareRunScreen(activity: _b!.activity, highlight: highlight)));
  }

  /// Corrigir a modalidade (ex.: arquivo de pedal importado como corrida).
  Future<void> _switchSport() async {
    final a = _b!.activity;
    final to = a.isBike ? Sport.run : Sport.bike;
    final ok = await confirmDialog(
      context,
      title: 'Mudar para ${to.label.toLowerCase()}?',
      message: to == Sport.bike
          ? 'Este treino passa a contar como pedal: sai dos recordes, medalhas e metas de corrida.'
          : 'Este treino passa a contar como corrida, inclusive em recordes, medalhas e metas.',
      confirm: 'Mudar',
    );
    if (!ok || !mounted) return;
    final w = context.read<AppState>().profile.weightForCalc;
    await _save(a.copyWith(
      sport: to,
      type: to.types.contains(a.type) ? a.type : to.types.first,
      calories: Calc.caloriesFor(to, w, a.distanceM, a.movingSec.toDouble()),
    ));
  }

  Future<void> _editNotes() async {
    final a = _b!.activity;
    _notes.text = a.notes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Observações'),
        content: TextField(
          controller: _notes,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Como se sentiu, clima, tênis, percurso…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) await _saveNotes();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final b = _b;
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Treino não encontrado.')));
    }
    final a = b.activity;
    final route = b.points.where((p) => !p.paused).map((p) => LatLng(p.lat, p.lon)).toList();
    final bike = a.isBike;
    final paceData = Calc.paceSeries(b.points, minPace: bike ? 40 : 120);
    final maxKmh = bike && paceData.isNotEmpty ? 3600 / paceData.map((p) => p.pace).reduce((x, y) => x < y ? x : y) : null;
    final altData = Calc.altitudeSeries(b.points);
    final best = a.bestKmSec;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(widget.justFinished ? (bike ? 'Pedal salvo' : 'Corrida salva') : a.sport.label),
        actions: [
          IconButton(tooltip: 'Compartilhar imagem', icon: const Icon(Icons.ios_share), onPressed: _shareImage),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'gpx':
                  _export('gpx');
                case 'tcx':
                  _export('tcx');
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (_) => [
              if (b.points.isNotEmpty) const PopupMenuItem(value: 'gpx', child: Text('Exportar .gpx')),
              const PopupMenuItem(value: 'tcx', child: Text('Exportar .tcx')),
              PopupMenuItem(value: 'delete', child: Text(bike ? 'Excluir pedal' : 'Excluir corrida')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 640)),
          ListView(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight + 4, 16, 40),
        children: [
          if (widget.justFinished)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaceCard(
                color: Pal.of(context).mintSoft,
                child: Row(
                  children: [
                    const Guara(pose: GuaraPose.celebrate, size: 92),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(CoachPhrases.resultTitles[a.id! % CoachPhrases.resultTitles.length],
                              style: numStyle(20, color: Pal.of(context).ink)),
                          const SizedBox(height: 2),
                          Text('${CoachPhrases.resultLines[a.id! % CoachPhrases.resultLines.length]} '
                              '${bike ? 'Seu pedal foi salvo' : 'Sua corrida foi salva'} no histórico.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _Hero(activity: a, route: route),
          const SizedBox(height: 12),
          if (!bike) _Highlights(activityId: a.id!, fresh: widget.justFinished),
          if (a.gpsPartial) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.gps_off,
              text: 'Trajeto de GPS incompleto: o arquivo original cobre só parte do treino. '
                  'Distância e tempo vêm do resumo da atividade; parciais por km não são exibidas.',
            ),
          ],
          if (route.length < 2 && !a.gpsPartial) ...[
            const SizedBox(height: 4),
            _Notice(icon: Icons.map_outlined, text: 'Este treino não tem trajeto de GPS.'),
          ],
          const SizedBox(height: 12),
          PaceCard(
            child: StatGrid(columns: 3, spacing: 18, children: [
              StatTile(label: 'Tempo', value: Fmt.duration(a.movingSec), color: const Pal(true).violet),
              if (bike) ...[
                StatTile(label: 'Velocidade média', value: Fmt.kmh(a.kmh), unit: 'km/h', color: const Pal(true).orange),
                StatTile(label: 'Velocidade máx.', value: Fmt.kmh(maxKmh), unit: 'km/h'),
                StatTile(label: 'Descida', value: '−${Fmt.integer(a.elevLoss)}', unit: 'm'),
              ] else ...[
                StatTile(label: 'Pace médio', value: Fmt.pace(a.paceSecPerKm), unit: '/km', color: const Pal(true).orange),
                StatTile(label: 'Velocidade', value: Fmt.speed(a.avgSpeed), unit: 'km/h'),
                StatTile(label: 'Melhor km', value: best == null ? '—' : Fmt.duration(best)),
              ],
              StatTile(label: 'Calorias (estim.)', value: a.calories == null ? '—' : Fmt.integer(a.calories!), unit: 'kcal', color: const Pal(true).pink),
              StatTile(label: 'Elevação', value: '+${Fmt.integer(a.elevGain)}', unit: 'm'),
              if (a.elapsedSec > a.movingSec + 30) StatTile(label: 'Tempo total', value: Fmt.duration(a.elapsedSec)),
              if (a.avgHr != null) StatTile(label: 'FC média', value: '${a.avgHr}', unit: 'bpm'),
              if (a.maxHr != null) StatTile(label: 'FC máxima', value: '${a.maxHr}', unit: 'bpm'),
              if (a.avgCad != null) StatTile(label: 'Cadência', value: '${a.avgCad}', unit: bike ? 'rpm' : 'ppm'),
              if (b.laps.isNotEmpty) StatTile(label: 'Voltas', value: '${b.laps.length}'),
            ]),
          ),
          if (b.splits.isNotEmpty) ...[
            const SectionTitle('Parciais por km'),
            PaceCard(padding: const EdgeInsets.symmetric(vertical: 8), child: _SplitsTable(splits: b.splits, bike: bike)),
          ],
          if (paceData.length >= 5 && bike) ...[
            const SectionTitle('Velocidade ao longo do pedal'),
            PaceCard(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
              child: DistanceLineChart(
                data: [for (final p in paceData) (x: p.km, y: 3600 / p.pace)],
                color: const Pal(true).orange,
                formatY: (v) => '${v.round()} km/h',
              ),
            ),
          ],
          if (paceData.length >= 5 && !bike) ...[
            const SectionTitle('Pace ao longo da corrida'),
            PaceCard(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
              child: DistanceLineChart(
                data: [for (final p in paceData) (x: p.km, y: p.pace)],
                color: const Pal(true).orange,
                formatY: Fmt.pace,
                invert: true,
              ),
            ),
          ],
          if (altData.length >= 5) ...[
            const SectionTitle('Altimetria'),
            PaceCard(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
              child: DistanceLineChart(
                data: [for (final p in altData) (x: p.km, y: p.alt)],
                color: PaceColors.teal,
                formatY: (v) => '${v.round()} m',
                height: 140,
              ),
            ),
          ],
          if (b.laps.isNotEmpty) ...[
            const SectionTitle('Voltas'),
            PaceCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final l in b.laps)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 14, child: Text('${l.index}', style: const TextStyle(fontSize: 12))),
                      title: Text('${Fmt.kmUnit(l.distM)} · ${Fmt.duration(l.sec)}'),
                      subtitle: Text(l.manual ? 'Volta manual' : 'Volta automática'),
                      trailing: Text(Fmt.effort(l.paceSecPerKm, bike: bike), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ],
          const SectionTitle('Detalhes'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(bike ? Icons.directions_bike_rounded : Icons.directions_run_rounded),
                  title: const Text('Modalidade'),
                  subtitle: Text(a.sport.label),
                  trailing: const Icon(Icons.swap_horiz_rounded),
                  onTap: _switchSport,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Tipo de treino'),
                  subtitle: Text(a.type),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _pickType,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Observações'),
                  subtitle: Text(a.notes.isEmpty ? 'Toque para anotar como foi' : a.notes),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editNotes,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(a.source.label),
                  subtitle: a.sourceFile == null ? null : Text(a.sourceFile!, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
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

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: PaceColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PaceColors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: cs.onSurface, fontSize: 13))),
        ],
      ),
    );
  }
}

class _SplitsTable extends StatelessWidget {
  final List<Split> splits;
  final bool bike;
  const _SplitsTable({required this.splits, this.bike = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final full = splits.where((s) => s.distM >= 999).map((s) => s.paceSecPerKm).toList();
    final fastest = full.isEmpty ? 0.0 : full.reduce((a, b) => a < b ? a : b);
    final slowest = full.isEmpty ? 1.0 : full.reduce((a, b) => a > b ? a : b);
    Widget header(String s, {TextAlign align = TextAlign.left}) =>
        Text(s, textAlign: align, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            SizedBox(width: 44, child: header('Km')),
            Expanded(child: header(bike ? 'km/h' : 'Pace')),
            SizedBox(width: 64, child: header('Tempo', align: TextAlign.right)),
            SizedBox(width: 64, child: header('Dif.', align: TextAlign.right)),
          ]),
        ),
        for (var i = 0; i < splits.length; i++)
          Builder(builder: (context) {
            final s = splits[i];
            final pace = s.paceSecPerKm;
            final range = (slowest - fastest).abs() < 1 ? 1.0 : slowest - fastest;
            final frac = (1 - (pace - fastest) / range).clamp(0.15, 1.0);
            final prev = i > 0 ? splits[i - 1].paceSecPerKm : null;
            final diff = prev == null ? null : pace - prev;
            final isFastest = s.distM >= 999 && (pace - fastest).abs() < 0.5;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(s.distM >= 999 ? '${s.km}' : Fmt.km(s.distM),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(bike ? Fmt.kmh(3600 / pace) : Fmt.pace(pace),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isFastest ? Pal.of(context).mintText : null,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: frac,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: isFastest ? Pal.of(context).mint : Pal.of(context).mintMid,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 64, child: Text(Fmt.duration(s.sec), textAlign: TextAlign.right)),
                  SizedBox(
                    width: 64,
                    child: Text(
                      diff == null ? '—' : '${diff > 0 ? '+' : diff < 0 ? '−' : '±'}${diff.abs().round()} s',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: diff == null || diff.abs() < 1
                            ? cs.onSurfaceVariant
                            : (diff < 0 ? Pal.of(context).mintText : const Color(0xFFDC2626)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Recordes e conquistas desta corrida (com destaque quando acabou de terminar).
class _Highlights extends StatelessWidget {
  final int activityId;
  final bool fresh;
  const _Highlights({required this.activityId, required this.fresh});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.efforts.containsKey(activityId)) {
      return fresh && app.effortsBusy
          ? const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator(minHeight: 2))
          : const SizedBox.shrink();
    }
    final broken = Records.brokenBy(activityId, app.activities, app.efforts);
    final brokenKeys = {for (final b in broken) b.now.key};
    final held = [
      for (final r in app.records.list)
        if (r.activityId == activityId && !brokenKeys.contains(r.key)) r
    ];
    final medals = [for (final b in app.badges) if (b.activityId == activityId) b];
    final hasOthers = app.activities.length > 1;
    final rows = <Widget>[];
    for (final b in broken) {
      if (b.before == null && !hasOthers) continue;
      final r = b.now;
      final before = b.before;
      rows.add(_line(
        context,
        icon: recordIcon(r),
        title: before == null ? 'Primeira vez: ${r.label}' : 'Novo recorde: ${r.label}',
        value: recordValue(r),
        sub: before == null ? null : 'Antes: ${recordValue(before)} (${recordWhen(before)})',
        highlight: true,
      ));
    }
    for (final r in held) {
      rows.add(_line(context, icon: recordIcon(r), title: 'Recorde atual: ${r.label}', value: recordValue(r)));
    }
    if (rows.isEmpty && medals.isEmpty) return const SizedBox.shrink();
    final newRecords = broken.where((b) => b.before != null).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFC53D), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fresh && newRecords > 0
                        ? (newRecords == 1 ? 'Você bateu um recorde!' : 'Você bateu $newRecords recordes!')
                        : 'Destaques desta corrida',
                    style: numStyle(17, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...rows,
            if (rows.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordsScreen())),
                  child: const Text('Ver todos os recordes'),
                ),
              ),
            if (medals.isNotEmpty) ...[
              if (rows.isNotEmpty) const Divider(height: 10),
              Text(medals.length == 1 ? 'Conquista desbloqueada' : 'Conquistas desbloqueadas',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Pal(true).muted)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (k, m) in medals.indexed)
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
                        child: SizedBox(
                          width: 84,
                          child: Column(
                            children: [
                              fresh
                                  ? MedalDrop(delayMs: k * 180, child: BadgeMedal(badge: m, size: 66, shine: true))
                                  : BadgeMedal(badge: m, size: 66),
                              const SizedBox(height: 4),
                              Text(m.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context,
      {required IconData icon, required String title, required String value, String? sub, bool highlight = false}) {
    const p = Pal(true);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (highlight ? const Color(0xFFFFC53D) : PaceColors.mintBright).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: highlight ? const Color(0xFFFFC53D) : PaceColors.mintBright),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13.5)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
          Text(value, style: numStyle(16, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Topo do detalhe: mapa (ou o Guará), tipo, data e a distância em destaque.
class _Hero extends StatelessWidget {
  final Activity activity;
  final List<LatLng> route;
  const _Hero({required this.activity, required this.route});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    const p = Pal(true);
    final hasMap = route.length >= 2;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMap)
            SizedBox(
              height: 250,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RouteMap(points: route),
                  // Degradê para o mapa "entrar" no vidro.
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 60,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00121720), Color(0xE6121720)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, hasMap ? 4 : 18, 18, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(
                            text: a.type,
                            bg: PaceColors.mintBright.withValues(alpha: 0.16),
                            fg: PaceColors.mintBright,
                            icon: a.isBike ? Icons.directions_bike_rounded : Icons.directions_run_rounded,
                          ),
                          if (a.source != ActivitySource.recorded)
                            Pill(
                              text: 'Importada',
                              bg: Colors.white.withValues(alpha: 0.08),
                              fg: p.muted,
                              icon: Icons.file_download_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('${Fmt.weekdayDate(a.start)} · ${Fmt.time(a.start)}',
                          style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: Fmt.km(a.distanceM), style: numStyle(52, color: Colors.white)),
                          TextSpan(text: ' km', style: numStyle(22, color: p.muted)),
                        ])),
                      ),
                    ],
                  ),
                ),
                if (!hasMap) const Guara(pose: GuaraPose.run, size: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
