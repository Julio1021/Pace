import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../data/exporters.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'import_screen.dart';
import 'profile_edit_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final app = context.read<AppState>();
      final bytes = await BackupCodec.build(app.db);
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final f = File('${dir.path}/pace_backup_${now.year}-${two(now.month)}-${two(now.day)}.zip');
      await f.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'application/zip')],
        text: 'Backup do PACE (${app.activities.length} corridas). Guarde no Google Drive ou em outro local seguro.',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível gerar o backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final app = context.read<AppState>();
      final r = await BackupCodec.restore(app.db, await file.readAsBytes());
      app.profile = await app.db.getProfile();
      await app.reload();
      if (mounted) {
        showSnack(context, 'Backup restaurado: ${r.restored} corridas (${r.skipped} já existiam).');
      }
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível restaurar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.profile;
    final life = app.lifetime;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final first = app.firstRunDate;
    final details = <String>[
      if (p.age != null) '${p.age} anos',
      if (p.heightCm != null) '${p.heightCm!.round()} cm',
      if (p.weightKg != null) '${p.weightKg!.toStringAsFixed(p.weightKg! % 1 == 0 ? 0 : 1).replaceAll('.', ',')} kg',
      p.level,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          PaceCard(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: cs.primary,
                  child: Text(p.initials,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: t.titleLarge),
                      const SizedBox(height: 2),
                      Text(details.join(' · '), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('Meta semanal: ${Fmt.integer(p.weeklyGoalKm)} km',
                          style: t.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined),
              ],
            ),
          ),
          if (p.weightKg == null) ...[
            const SizedBox(height: 8),
            Text('Sem peso no perfil, as calorias são estimadas com 70 kg.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SectionTitle('Seus números'),
          PaceCard(
            child: Column(
              children: [
                StatGrid(columns: 3, children: [
                  StatTile(label: 'Quilômetros', value: Fmt.integer(life.distanceM / 1000)),
                  StatTile(label: 'Corridas', value: Fmt.integer(life.count)),
                  StatTile(label: 'Tempo', value: Fmt.durationLong(life.movingSec)),
                  StatTile(label: 'Maior distância', value: Fmt.km(life.longestM), unit: 'km'),
                  StatTile(label: 'Melhor pace médio', value: Fmt.pace(life.bestPace), unit: '/km'),
                  StatTile(label: 'Pace médio', value: Fmt.pace(life.avgPace), unit: '/km'),
                ]),
                if (first != null) ...[
                  const Divider(height: 28),
                  Row(
                    children: [
                      Icon(Icons.event, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('Primeira corrida: ${Fmt.date(first)}', style: t.bodyMedium),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Dados'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Importar histórico'),
                  subtitle: const Text('Arquivos .tcx, .gpx ou .zip'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Exportar backup'),
                  subtitle: const Text('Todas as corridas e o perfil em um arquivo .zip'),
                  enabled: !_busy,
                  onTap: _backup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restaurar backup'),
                  subtitle: const Text('Não duplica corridas que já existem'),
                  enabled: !_busy,
                  onTap: _restore,
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
          const SectionTitle('Sobre'),
          PaceCard(
            child: Text(
              'PACE — monitoramento de corrida de rua. Seus dados ficam só neste celular; '
              'faça backups com frequência. Mapas © colaboradores do OpenStreetMap. '
              'Calorias são estimativas e não substituem avaliação profissional.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
