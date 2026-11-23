import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/reminders.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';

/// Lembretes: hora de correr, meta quase batida e resumo da semana.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const _days = [
    (DateTime.monday, 'S'),
    (DateTime.tuesday, 'T'),
    (DateTime.wednesday, 'Q'),
    (DateTime.thursday, 'Q'),
    (DateTime.friday, 'S'),
    (DateTime.saturday, 'S'),
    (DateTime.sunday, 'D'),
  ];
  static const _names = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

  Future<void> _set(BuildContext context, ReminderSettings r) async {
    if (r.reminder || r.goalNudge || r.weeklySummary) {
      try {
        await ph.Permission.notification.request();
      } catch (_) {}
    }
    if (context.mounted) await context.read<AppState>().setReminders(r);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = app.reminders;
    const p = Pal(true);
    final time = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
    final sug = ReminderSettings.suggested(app.activities, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(
            children: [
              const Guara(pose: GuaraPose.wave, size: 70, waves: 2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'O Guará te chama na hora certa. Sem som alto nem exagero: no máximo um lembrete por dia.',
                  style: TextStyle(color: Pal.of(context).muted, height: 1.35),
                ),
              ),
            ],
          ),
          const SectionTitle('Hora de correr'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.alarm_rounded),
                  title: const Text('Lembrete para correr'),
                  subtitle: Text(app.plan != null ? 'Mostra o treino do seu plano' : 'Nos dias e no horário escolhidos'),
                  value: r.reminder,
                  onChanged: (v) => _set(context, r.copyWith(reminder: v)),
                ),
                if (r.reminder) ...[
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Horário'),
                    trailing: Text(time, style: numStyle(20, color: Colors.white)),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: r.hour, minute: r.minute));
                      if (t != null && context.mounted) await _set(context, r.copyWith(hour: t.hour, minute: t.minute));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final (i, (d, l)) in _days.indexed)
                          Semantics(
                            label: _names[i],
                            selected: r.days.contains(d),
                            button: true,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final s = {...r.days};
                                s.contains(d) ? s.remove(d) : s.add(d);
                                _set(context, r.copyWith(days: s));
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: r.days.contains(d) ? PaceColors.mintBright : Colors.white.withValues(alpha: 0.07),
                                ),
                                child: Text(l,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: r.days.contains(d) ? PaceColors.ink : p.muted,
                                    )),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (app.activities.length >= 3 &&
                      (sug.hour != r.hour || sug.minute != r.minute || sug.days.length != r.days.length || !sug.days.containsAll(r.days)))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: TextButton.icon(
                        onPressed: () => _set(context, r.copyWith(hour: sug.hour, minute: sug.minute, days: sug.days)),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text('Usar meu padrão: ${[
                          for (final (i, (d, _)) in _days.indexed)
                            if (sug.days.contains(d)) _names[i].substring(0, 3)
                        ].join(', ')} às ${sug.hour.toString().padLeft(2, '0')}:${sug.minute.toString().padLeft(2, '0')}'),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SectionTitle('Avisos da semana'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.flag_rounded),
                  title: const Text('Meta quase batida'),
                  subtitle: const Text('Sexta às 18h e domingo às 9h, quando faltar pouco'),
                  value: r.goalNudge,
                  onChanged: (v) => _set(context, r.copyWith(goalNudge: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.summarize_rounded),
                  title: const Text('Resumo da semana'),
                  subtitle: const Text('Domingo às 20h: corridas, km, pace e a meta'),
                  value: r.weeklySummary,
                  onChanged: (v) => _set(context, r.copyWith(weeklySummary: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'O Android pode atrasar alguns minutos os lembretes para economizar bateria.',
            style: TextStyle(fontSize: 12, color: Pal.of(context).muted),
          ),
        ],
      ),
    );
  }
}
