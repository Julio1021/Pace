import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../domain/models.dart';
import '../services/recorder.dart';
import '../state/app_state.dart';
import 'screens/activity_detail_screen.dart';
import 'screens/evolution_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_run_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/run_setup_screen.dart';

/// Barra inferior com cinco seções; "Correr" fica em destaque no centro.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();

  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();
}

class HomeShellState extends State<HomeShell> {
  int index = 0;
  bool _checkedRecovery = false;

  void go(int i) => setState(() => index = i);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedRecovery) {
      _checkedRecovery = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkInterrupted());
    }
  }

  /// Se o app fechou no meio de uma corrida, oferece retomar ou salvar.
  Future<void> _checkInterrupted() async {
    final app = context.read<AppState>();
    final rec = context.read<Recorder>();
    if (rec.isActive) return;
    final open = await app.db.listActivities(status: ActivityStatus.inProgress);
    if (open.isEmpty || !mounted) return;
    final a = open.first;
    final pts = await app.db.getPoints(a.id!);
    if (!mounted) return;
    final dist = pts.isEmpty ? 0.0 : pts.last.dist;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Corrida interrompida'),
        content: Text(
          'Uma corrida iniciada em ${Fmt.dateTime(a.start)} não foi encerrada '
          '(${Fmt.kmUnit(dist)} gravados). O que deseja fazer?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Descartar')),
          TextButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Salvar como está')),
          FilledButton(onPressed: () => Navigator.pop(c, 'resume'), child: const Text('Retomar')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'resume':
        await rec.resumeInterrupted(a);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRunScreen()));
      case 'save':
        await Recorder.finalizeActivity(app.db, a.id!, weightKg: app.profile.weightForCalc);
        await app.reload();
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id!)));
      case 'discard':
        await app.db.deleteActivity(a.id!);
        await app.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rec = context.watch<Recorder>();
    final pages = [
      const HomeScreen(),
      const HistoryScreen(),
      RunSetupScreen(active: index == 2),
      const EvolutionScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: rec.isActive && index != 2
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRunScreen())),
              icon: const Icon(Icons.directions_run),
              label: Text('Corrida em andamento · ${Fmt.kmUnit(rec.distance)}'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          const NavigationDestination(
              icon: Icon(Icons.format_list_bulleted), selectedIcon: Icon(Icons.list_alt), label: 'Histórico'),
          NavigationDestination(
            icon: _RunIcon(color: cs.primary, active: false),
            selectedIcon: _RunIcon(color: cs.primary, active: true),
            label: 'Correr',
          ),
          const NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Evolução'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _RunIcon extends StatelessWidget {
  final Color color;
  final bool active;
  const _RunIcon({required this.color, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(17),
        boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10)] : null,
      ),
      child: const Icon(Icons.directions_run, color: Colors.white, size: 22),
    );
  }
}
