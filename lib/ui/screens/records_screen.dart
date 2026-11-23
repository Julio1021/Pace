import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/records.dart';
import '../../state/app_state.dart';
import '../widgets/achievement_widgets.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';
import 'activity_detail_screen.dart';

/// Recordes pessoais: melhores tempos por distância e outros marcos.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recs = app.records;
    final others = recs.list.where((r) => r.kind != RecordKind.effort).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Recordes pessoais')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              const Guara(pose: GuaraPose.celebrate, size: 76),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Seus melhores resultados, contando também as corridas importadas. '
                  'O melhor tempo vale para qualquer trecho dentro de uma corrida.',
                  style: TextStyle(color: Pal.of(context).muted, height: 1.35),
                ),
              ),
            ],
          ),
          if (app.effortsBusy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 6),
            Text('Analisando o histórico para achar seus melhores trechos…',
                style: TextStyle(fontSize: 12, color: Pal.of(context).muted)),
          ],
          const SectionTitle('Melhores tempos'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, e) in EffortDistance.all.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _RecordRow(record: recs.byKey('effort_${e.meters}'), label: e.label, short: e.short),
                ],
              ],
            ),
          ),
          const SectionTitle('Outros recordes'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: others.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Corra para começar a colecionar recordes.'))
                : Column(
                    children: [
                      for (final (i, r) in others.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _RecordRow(record: r, label: r.label),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final PersonalRecord? record;
  final String label;
  final String? short;
  const _RecordRow({required this.record, required this.label, this.short});

  @override
  Widget build(BuildContext context) {
    const p = Pal(true);
    final r = record;
    final pace = r == null ? null : recordPace(r);
    return ListTile(
      onTap: r?.activityId == null
          ? null
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: r!.activityId!))),
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (r == null ? p.faint : PaceColors.mintBright.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: short != null
            ? Text(short!, style: numStyle(14, color: r == null ? p.muted : PaceColors.mintBright))
            : Icon(recordIcon(r!), color: PaceColors.mintBright, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        r == null ? 'Ainda sem um trecho completo dessa distância' : [recordWhen(r), if (pace != null) pace].join(' · '),
        style: TextStyle(color: p.muted, fontSize: 12.5),
      ),
      trailing: r == null
          ? Text('—', style: numStyle(18, color: p.muted))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(recordValue(r), style: numStyle(18, color: Colors.white)),
                if (r.activityId != null) Icon(Icons.chevron_right, color: p.muted),
              ],
            ),
    );
  }
}
