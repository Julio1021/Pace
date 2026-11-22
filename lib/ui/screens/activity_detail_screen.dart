import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Split;
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/exporters.dart';
import '../../domain/calc.dart';
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
  final _shareKey = GlobalKey();
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
            for (final t in trainingTypes)
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
      title: 'Excluir corrida?',
      message: 'A corrida de ${Fmt.date(_b!.activity.start)} (${Fmt.kmUnit(_b!.activity.distanceM)}) será apagada. '
          'Isso não pode ser desfeito.',
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
      text: 'Corrida de ${Fmt.date(b.activity.start)} — ${Fmt.kmUnit(b.activity.distanceM)}',
    ));
  }

  Future<void> _shareImage() async {
    final b = _b!;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(key: _shareKey, child: ShareCard(activity: b.activity)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Compartilhar'),
                      onPressed: () async {
                        final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                        if (boundary == null) return;
                        final img = await boundary.toImage(pixelRatio: 3);
                        final data = await img.toByteData(format: ui.ImageByteFormat.png);
                        if (data == null) return;
                        final dir = await getTemporaryDirectory();
                        final f = File('${dir.path}/${exportFileName(b.activity, 'png')}');
                        await f.writeAsBytes(data.buffer.asUint8List());
                        await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')]));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final b = _b;
    if (b == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Corrida não encontrada.')));
    }
    final a = b.activity;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final route = b.points.where((p) => !p.paused).map((p) => LatLng(p.lat, p.lon)).toList();
    final paceData = Calc.paceSeries(b.points);
    final altData = Calc.altitudeSeries(b.points);
    final best = a.bestKmSec;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.justFinished ? 'Corrida salva' : a.type),
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
              const PopupMenuItem(value: 'delete', child: Text('Excluir corrida')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
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
                          Text('Mandou bem!', style: numStyle(20, color: Pal.of(context).ink)),
                          const SizedBox(height: 2),
                          const Text('Sua corrida foi salva no histórico.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text('${Fmt.weekdayDate(a.start)} · ${Fmt.time(a.start)}',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(Fmt.kmUnit(a.distanceM), style: numStyle(46, color: cs.onSurface)),
          const SizedBox(height: 12),
          if (route.length >= 2)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(height: 300, child: RouteMap(points: route)),
            ),
          if (a.gpsPartial) ...[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.gps_off,
              text: 'Trajeto de GPS incompleto: o arquivo original cobre só parte da corrida. '
                  'Distância e tempo vêm do resumo da atividade; parciais por km não são exibidas.',
            ),
          ],
          if (route.length < 2 && !a.gpsPartial) ...[
            const SizedBox(height: 4),
            _Notice(icon: Icons.map_outlined, text: 'Esta corrida não tem trajeto de GPS.'),
          ],
          const SizedBox(height: 12),
          PaceCard(
            child: StatGrid(columns: 3, spacing: 18, children: [
              StatTile(label: 'Tempo', value: Fmt.duration(a.movingSec), color: const Pal(true).violet),
              StatTile(label: 'Pace médio', value: Fmt.pace(a.paceSecPerKm), unit: '/km', color: const Pal(true).orange),
              StatTile(label: 'Velocidade', value: Fmt.speed(a.avgSpeed), unit: 'km/h'),
              StatTile(label: 'Melhor km', value: best == null ? '—' : Fmt.duration(best)),
              StatTile(label: 'Calorias (estim.)', value: a.calories == null ? '—' : Fmt.integer(a.calories!), unit: 'kcal', color: const Pal(true).pink),
              StatTile(label: 'Elevação', value: '+${Fmt.integer(a.elevGain)}', unit: 'm'),
              if (a.elapsedSec > a.movingSec + 30) StatTile(label: 'Tempo total', value: Fmt.duration(a.elapsedSec)),
              if (a.avgHr != null) StatTile(label: 'FC média', value: '${a.avgHr}', unit: 'bpm'),
              if (a.maxHr != null) StatTile(label: 'FC máxima', value: '${a.maxHr}', unit: 'bpm'),
              if (a.avgCad != null) StatTile(label: 'Cadência', value: '${a.avgCad}', unit: 'ppm'),
              if (b.laps.isNotEmpty) StatTile(label: 'Voltas', value: '${b.laps.length}'),
            ]),
          ),
          if (b.splits.isNotEmpty) ...[
            const SectionTitle('Parciais por km'),
            PaceCard(padding: const EdgeInsets.symmetric(vertical: 8), child: _SplitsTable(splits: b.splits)),
          ],
          if (paceData.length >= 5) ...[
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
                      trailing: Text(Fmt.paceUnit(l.paceSecPerKm), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Tipo de treino'),
                  subtitle: Text(a.type),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _pickType,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Observações',
                      hintText: 'Como se sentiu, clima, tênis…',
                      suffixIcon: IconButton(icon: const Icon(Icons.check), tooltip: 'Salvar', onPressed: _saveNotes),
                    ),
                    onEditingComplete: _saveNotes,
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                      _saveNotes();
                    },
                  ),
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
  const _SplitsTable({required this.splits});

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
            Expanded(child: header('Pace')),
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
                        Text(Fmt.pace(pace),
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

/// Resumo visual para compartilhar (distância, tempo, pace e trajeto).
class ShareCard extends StatelessWidget {
  final Activity activity;
  const ShareCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    const white = Colors.white;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PaceColors.blue, PaceColors.blueDark],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run, color: PaceColors.lime),
              const SizedBox(width: 6),
              const Text('PACE', style: TextStyle(color: white, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const Spacer(),
              Text(Fmt.date(a.start), style: TextStyle(color: white.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (a.previewPoints.length >= 2)
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CustomPaint(painter: RoutePainter(a.previewPoints, PaceColors.lime, 4)),
            ),
          const SizedBox(height: 10),
          Text('${Fmt.km(a.distanceM)} km',
              style: const TextStyle(color: white, fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _item('Tempo', Fmt.duration(a.movingSec)),
              _item('Pace', '${Fmt.pace(a.paceSecPerKm)} /km'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
          ],
        ),
      );
}
