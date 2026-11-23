import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/pcloud.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';

/// Backup automático no pCloud: conectar, enviar agora, restaurar e desconectar.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  List<CloudBackup>? _list;
  bool _loadingList = false;
  String? _listError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

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
      message: 'Backup de ${Fmt.dateTime(b.created.toUtc())}. As corridas que já estão no celular não são duplicadas.',
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mut = Pal.of(context).muted;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup no pCloud')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              Guara(pose: app.pcloudConnected ? GuaraPose.celebrate : GuaraPose.wave, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Suas corridas ficam guardadas na sua conta pCloud, numa pasta só do PACE. '
                  'O envio é automático depois de cada corrida e uma vez por semana.',
                  style: TextStyle(color: mut, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!PCloudService.configured)
            GlassCard(
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: PaceColors.mintBright),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aguardando a pCloud aprovar o app PACE. Assim que aprovarem, esta opção é liberada numa atualização.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), height: 1.35),
                    ),
                  ),
                ],
              ),
            )
          else if (!app.pcloudConnected) ...[
            FilledButton.icon(
              onPressed: app.cloudBusy ? null : () => context.read<AppState>().connectPCloud(),
              icon: const Icon(Icons.cloud_outlined),
              label: Text(app.cloudBusy ? 'Aguardando o login no navegador…' : 'Conectar pCloud'),
            ),
            if (app.cloudBusy)
              TextButton(onPressed: PCloudService.cancelLogin, child: const Text('Cancelar')),
            const SizedBox(height: 8),
            Text(
              'Abre a página da pCloud para você entrar e autorizar. O PACE não vê sua senha e só tem acesso à própria pasta.',
              style: TextStyle(fontSize: 12.5, color: mut),
            ),
          ] else ...[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done_rounded, color: PaceColors.mintBright),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          app.pcloudEmail?.isNotEmpty == true ? 'Conectado como ${app.pcloudEmail}' : 'pCloud conectado',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.lastCloudBackup == null
                        ? 'Nenhum backup enviado ainda.'
                        : 'Último backup: ${Fmt.dateTime(app.lastCloudBackup!.toUtc())}',
                    style: TextStyle(color: const Pal(true).muted),
                  ),
                  if (app.cloudBusy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: app.cloudBusy
                        ? null
                        : () async {
                            final ok = await context.read<AppState>().backupToCloud();
                            if (!context.mounted) return;
                            showSnack(context, ok ? 'Backup enviado para o pCloud.' : 'Não foi possível enviar.');
                            _refresh();
                          },
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Fazer backup agora'),
                  ),
                ],
              ),
            ),
            const SectionTitle('Backups guardados'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _loadingList
                  ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                  : _listError != null
                      ? ListTile(title: Text(_listError!), trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)))
                      : (_list == null || _list!.isEmpty)
                          ? const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum backup no pCloud ainda.'))
                          : Column(
                              children: [
                                for (final (i, b) in _list!.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(Icons.inventory_2_outlined),
                                    title: Text(Fmt.dateTime(b.created.toUtc())),
                                    subtitle: Text('${(b.size / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB'),
                                    trailing: TextButton(
                                      onPressed: app.cloudBusy ? null : () => _restore(b),
                                      child: const Text('Restaurar'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.read<AppState>().disconnectPCloud(),
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Desconectar'),
            ),
            const SizedBox(height: 6),
            Text('Os backups continuam no seu pCloud, na pasta Applications/PACE.',
                style: TextStyle(fontSize: 12, color: mut)),
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
