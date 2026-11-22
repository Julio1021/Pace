import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/import_service.dart';
import '../../data/importers.dart';
import '../../state/app_state.dart';
import '../widgets/pace_ui.dart';
import '../widgets/common.dart';

/// Importação de histórico: vários .tcx/.gpx de uma vez ou um .zip com eles.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _stage = '';
  ImportReport? _report;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    setState(() {
      _running = true;
      _report = null;
      _done = 0;
      _total = 0;
      _stage = 'Lendo ${files.length} ${files.length == 1 ? 'arquivo' : 'arquivos'}…';
    });
    final app = context.read<AppState>();
    final items = <ImportItem>[];
    for (final f in files) {
      try {
        items.add(ImportItem(f.name, await f.readAsBytes()));
      } catch (_) {
        items.add(ImportItem(f.name, const []));
      }
    }
    if (!mounted) return;
    setState(() => _stage = 'Importando corridas…');
    final report = await ImportService.run(
      app.db,
      items,
      weightKg: app.profile.weightForCalc,
      onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      },
    );
    await app.reload();
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = glassTheme.colorScheme;
    final t = glassTheme.textTheme;
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar histórico')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Traga suas corridas de outros apps', style: t.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Selecione arquivos .tcx ou .gpx (pode escolher vários de uma vez) ou um .zip com eles. '
                  'Corridas que já estão no PACE são ignoradas automaticamente.',
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Text(
                  'Dica: no gerenciador de arquivos, compacte a pasta com as corridas (ex.: NRC) em .zip '
                  'e selecione só o .zip.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _running ? null : _pick,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Escolher arquivos'),
                  ),
                ),
              ],
            ),
          ),
          if (_running) ...[
            const SizedBox(height: 16),
            PaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stage, style: t.titleSmall),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8),
                  const SizedBox(height: 8),
                  if (_total > 0) Text('$_done de $_total', style: t.bodySmall),
                ],
              ),
            ),
          ],
          if (r != null) ...[
            const SizedBox(height: 16),
            PaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.total == 0 ? 'Nenhum arquivo .tcx ou .gpx encontrado' : 'Importação concluída',
                      style: t.titleMedium),
                  const SizedBox(height: 12),
                  _line(Icons.check_circle, cs.secondary, 'Importadas', r.imported),
                  _line(Icons.content_copy, cs.onSurfaceVariant, 'Duplicadas ignoradas', r.duplicates),
                  _line(Icons.error_outline, cs.error, 'Com erro', r.errors.length),
                  if (r.errors.isNotEmpty) ...[
                    const Divider(height: 24),
                    for (final e in r.errors.take(50))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• ${e.file}: ${e.reason}', style: t.bodySmall),
                      ),
                    if (r.errors.length > 50) Text('… e mais ${r.errors.length - 50}', style: t.bodySmall),
                  ],
                  if (r.imported > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Ver no histórico')),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, Color color, String label, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      );
}
