import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/pcloud.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';

const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/// "hoje às 16:28", "ontem às 07:12" ou "20 nov · 07:12".
String cloudWhen(DateTime local, {DateTime? now, bool sentence = false}) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(local.hour)}:${two(local.minute)}';
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days == 0) return 'hoje às $hm';
  if (days == 1) return 'ontem às $hm';
  final y = local.year == n.year ? '' : ' ${local.year}';
  return '${local.day} ${_months[local.month - 1]}$y${sentence ? ' às ' : ' · '}$hm';
}

String cloudSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Backup automático no pCloud: conectar, enviar agora, opções, restaurar e desconectar.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  List<CloudBackup>? _list;
  bool _loadingList = false;
  String? _listError;
  Object? _seen = const Object();

  Future<void> _refresh() async {
    final c = context.read<AppState>().pcloud;
    if (c == null) return;
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final l = await c.list();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _listError = '$e');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _restore(CloudBackup b) async {
    final ok = await confirmDialog(
      context,
      title: 'Restaurar este backup?',
      message: 'Backup de ${cloudWhen(b.created, sentence: true)}. '
          'Corridas que já estão no celular não são duplicadas.',
      confirm: 'Restaurar',
    );
    if (!ok || !mounted) return;
    try {
      final r = await context.read<AppState>().restoreFromCloud(b.fileId);
      if (mounted) showSnack(context, 'Backup restaurado: ${r.restored} corridas (${r.skipped} já existiam).');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível restaurar: $e');
    }
  }

  Future<void> _delete(CloudBackup b) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir este backup?',
      message: 'O backup de ${cloudWhen(b.created, sentence: true)} será apagado do seu pCloud.',
      confirm: 'Excluir',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppState>().pcloud!.delete(b.fileId);
      if (mounted) showSnack(context, 'Backup excluído.');
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível excluir: $e');
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmDialog(
      context,
      title: 'Desconectar o pCloud?',
      message: 'O backup automático para. Os backups já enviados continuam na pasta “PACE Backups”.',
      confirm: 'Desconectar',
    );
    if (ok && mounted) await context.read<AppState>().disconnectPCloud();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mut = Pal.of(context).muted;
    final key = app.pcloudConnected ? app.lastCloudBackup : null;
    if (key != _seen && !app.cloudBusy) {
      _seen = key;
      if (app.pcloudConnected) WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.62);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup no pCloud')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              Guara(pose: app.pcloudConnected ? GuaraPose.celebrate : GuaraPose.wave, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Suas corridas guardadas no seu pCloud, na pasta “PACE Backups”.',
                  style: TextStyle(color: mut, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!PCloudService.configured)
            GlassCard(
              child: Text('Aguardando a pCloud aprovar o app PACE.', style: TextStyle(color: dim)),
            )
          else if (!app.pcloudConnected) ...[
            FilledButton.icon(
              onPressed: app.cloudBusy ? null : () => context.read<AppState>().connectPCloud(),
              icon: const Icon(Icons.cloud_outlined),
              label: Text(app.cloudBusy ? 'Aguardando o login no navegador…' : 'Conectar pCloud'),
            ),
            if (app.cloudBusy) TextButton(onPressed: PCloudService.cancelLogin, child: const Text('Cancelar')),
            const SizedBox(height: 8),
            Text(
              'Abre a página da pCloud para você entrar e autorizar. O PACE não vê sua senha e só mexe na pasta “PACE Backups”.',
              style: TextStyle(fontSize: 12.5, color: mut),
            ),
          ] else ...[
            // Status
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done_rounded, color: PaceColors.mintBright, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('pCloud conectado',
                                style: TextStyle(fontWeight: FontWeight.w800, color: white, fontSize: 16)),
                            if (app.pcloudEmail?.isNotEmpty == true)
                              Text(app.pcloudEmail!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    app.cloudBusy
                        ? 'Enviando backup…'
                        : app.cloudWaitingWifi
                            ? 'Corrida nova aguardando Wi-Fi para o backup.'
                            : app.lastCloudBackup == null
                                ? 'Nenhum backup enviado ainda.'
                                : 'Último backup ${cloudWhen(app.lastCloudBackup!, sentence: true)}'
                                    '${app.lastCloudSize == null ? '' : ' · ${cloudSize(app.lastCloudSize!)}'}',
                    style: TextStyle(color: app.cloudWaitingWifi && !app.cloudBusy ? PaceColors.mintBright : dim),
                  ),
                  if (app.cloudBusy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: app.cloudBusy
                          ? null
                          : () async {
                              final ok = await context.read<AppState>().backupToCloud();
                              if (context.mounted) {
                                showSnack(context, ok ? 'Backup enviado para o pCloud.' : 'Não foi possível enviar.');
                              }
                            },
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Fazer backup agora'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Opções
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    value: app.cloudAuto,
                    onChanged: (v) => context.read<AppState>().setCloudOptions(auto: v),
                    title: const Text('Backup automático', style: TextStyle(color: white, fontWeight: FontWeight.w600)),
                    subtitle: Text('Depois de cada corrida e uma vez por semana', style: TextStyle(color: dim)),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  SwitchListTile(
                    value: app.cloudWifiOnly,
                    onChanged: app.cloudAuto ? (v) => context.read<AppState>().setCloudOptions(wifiOnly: v) : null,
                    title: const Text('Só no Wi-Fi', style: TextStyle(color: white, fontWeight: FontWeight.w600)),
                    subtitle: Text('Não usa seus dados móveis', style: TextStyle(color: dim)),
                  ),
                ],
              ),
            ),
            SectionTitle('Backups guardados',
                trailing: Text('3 mais recentes', style: TextStyle(color: mut, fontSize: 12.5))),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _loadingList && _list == null
                  ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                  : _listError != null
                      ? ListTile(
                          title: Text(_listError!, style: const TextStyle(color: white)),
                          trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, color: white)),
                        )
                      : (_list == null || _list!.isEmpty)
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Nenhum backup no pCloud ainda.', style: TextStyle(color: dim)),
                            )
                          : Column(
                              children: [
                                for (final (i, b) in _list!.indexed) ...[
                                  if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                                  _BackupRow(
                                    b: b,
                                    latest: i == 0,
                                    busy: app.cloudBusy,
                                    onRestore: () => _restore(b),
                                    onDelete: () => _delete(b),
                                  ),
                                ],
                              ],
                            ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: app.cloudBusy ? null : _disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Desconectar'),
                style: TextButton.styleFrom(foregroundColor: PaceColors.orange),
              ),
            ),
          ],
          if (app.cloudError != null) ...[
            const SizedBox(height: 12),
            Text(app.cloudError!, style: const TextStyle(color: PaceColors.orange, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  final CloudBackup b;
  final bool latest;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  const _BackupRow({required this.b, required this.latest, required this.busy, required this.onRestore, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.62);
    final runs = b.runs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: dim, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(cloudWhen(b.created),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    if (latest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: PaceColors.mintBright.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Mais recente',
                            style: TextStyle(color: PaceColors.mintBright, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('${cloudSize(b.size)}${runs == null ? '' : ' · $runs ${runs == 1 ? 'corrida' : 'corridas'}'}',
                    style: TextStyle(color: dim, fontSize: 12.5)),
              ],
            ),
          ),
          PopupMenuButton<int>(
            enabled: !busy,
            icon: Icon(Icons.more_vert_rounded, color: dim),
            onSelected: (v) => v == 0 ? onRestore() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: ListTile(leading: Icon(Icons.restore_rounded), title: Text('Restaurar'))),
              PopupMenuItem(value: 1, child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Excluir'))),
            ],
          ),
        ],
      ),
    );
  }
}
