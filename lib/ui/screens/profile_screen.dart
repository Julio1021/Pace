import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/exporters.dart';
import '../../domain/coach.dart';
import '../../state/app_state.dart';
import '../widgets/pace_ui.dart';
import '../widgets/common.dart';
import 'achievements_screen.dart';
import 'import_screen.dart';
import 'plans_screen.dart';
import 'records_screen.dart';
import 'reminders_screen.dart';
import '../widgets/goals_card.dart';
import 'voice_picker.dart';
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
    final cs = glassTheme.colorScheme;
    final t = glassTheme.textTheme;
    final first = app.firstRunDate;
    final details = <String>[
      if (p.age != null) '${p.age} anos',
      if (p.heightCm != null) '${p.heightCm!.round()} cm',
      if (p.weightKg != null) '${p.weightKg!.toStringAsFixed(p.weightKg! % 1 == 0 ? 0 : 1).replaceAll('.', ',')} kg',
      p.level,
    ];

    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 560)),
          SafeArea(
            bottom: false,
            child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 130),
        children: [
          const Appear(child: ScreenTitle('Perfil')),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              child: Ink(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [PaceColors.mint, PaceColors.mintDark],
                  ),
                  boxShadow: [BoxShadow(color: PaceColors.mint.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                      child: Text(p.initials, style: numStyle(26, color: PaceColors.mintDark)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: numStyle(22, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(details.join(' · '),
                              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9))),
                          const SizedBox(height: 2),
                          Text('Meta semanal: ${Fmt.integer(p.weeklyGoalKm)} km',
                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          if (p.weightKg == null) ...[
            const SizedBox(height: 8),
            const Text('Sem peso no perfil, as calorias são estimadas com 70 kg.',
                style: TextStyle(fontSize: 12, color: PaceColors.muted)),
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
          const SectionTitle('Treino e motivação'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, e) in [
                  (Icons.flag_outlined, 'Metas', 'Semana ${Fmt.integer(app.profile.weeklyGoalKm)} km'
                      '${app.profile.monthlyGoalKm > 0 ? ' · mês ${Fmt.integer(app.profile.monthlyGoalKm)} km' : ''}'
                      '${app.profile.yearlyGoalKm > 0 ? ' · ano ${Fmt.integer(app.profile.yearlyGoalKm)} km' : ''}', null),
                  (Icons.event_note_outlined, 'Planos de treino', app.plan?.plan?.name ?? 'Nenhum plano em andamento', const PlansScreen()),
                  (Icons.emoji_events_outlined, 'Recordes pessoais', 'Melhores tempos e marcos', const RecordsScreen()),
                  (Icons.military_tech_outlined, 'Conquistas',
                      '${app.badges.where((b) => b.unlocked).length} de ${app.badges.length} medalhas', const AchievementsScreen()),
                  (Icons.notifications_active_outlined, 'Lembretes',
                      app.reminders.reminder ? 'Ligados' : 'Lembrete para correr desligado', const RemindersScreen()),
                ].indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(e.$1),
                    title: Text(e.$2),
                    subtitle: Text(e.$3),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => e.$4 == null
                        ? editGoals(context)
                        : Navigator.push(context, MaterialPageRoute(builder: (_) => e.$4!)),
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
          const SectionTitle('Aparência e mensagens'),
          PaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Animação de abertura'),
                  subtitle: const Text('O Guará dá um recado na primeira abertura do dia'),
                  value: app.introEnabled,
                  onChanged: app.setIntroEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Voz das falas'),
                  subtitle: Text(app.voiceName.isEmpty
                      ? 'Francisca (natural)'
                      : app.voiceName == 'auto'
                          ? 'Feminina do celular'
                          : 'Voz do celular escolhida'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const VoicePickerSheet(),
                  ),
                ),
                const Divider(height: 1),
                for (final s in CoachStyle.values)
                  ListTile(
                    leading: Icon(
                      app.coachStyle == s ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: app.coachStyle == s ? PaceColors.mintBright : null,
                    ),
                    title: Text(s.label),
                    subtitle: Text(s.hint),
                    onTap: () => app.setCoachStyle(s),
                  ),
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
          ),
        ],
      ),
    );
  }
}
