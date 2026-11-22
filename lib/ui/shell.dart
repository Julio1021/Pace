import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
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
              backgroundColor: PaceColors.ink,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRunScreen())),
              icon: const Icon(Icons.directions_run),
              label: Text('Corrida em andamento · ${Fmt.kmUnit(rec.distance)}'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      extendBody: true,
      bottomNavigationBar: PaceNavBar(index: index, onSelect: go),
    );
  }
}

/// Barra inferior flutuante, com o botão "Correr" em destaque no centro.
class PaceNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const PaceNavBar({super.key, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const p = Pal(true);
    final bg = Pal.of(context).bg;
    Widget item(int i, IconData icon, IconData sel, String label) {
      final on = index == i;
      final c = on ? p.mintText : p.muted;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkWell(
            key: ValueKey('nav-$i'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelect(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: on ? 1.1 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(on ? sel : icon, color: c, size: 23),
                  ),
                  const SizedBox(height: 3),
                  ExcludeSemantics(
                    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: SizedBox(
          height: 86,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xE0222934), Color(0xF0121720)],
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                    ),
                    child: Row(
                      children: [
                        item(0, Icons.home_outlined, Icons.home_rounded, 'Início'),
                        item(1, Icons.format_list_bulleted_rounded, Icons.view_list_rounded, 'Histórico'),
                        const Expanded(child: SizedBox()),
                        item(3, Icons.insights_outlined, Icons.insights_rounded, 'Evolução'),
                        item(4, Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: Semantics(
                  button: true,
                  label: 'Correr',
                  child: GestureDetector(
                    key: const ValueKey('nav-2'),
                    onTap: () => onSelect(2),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: PaceColors.mint,
                        shape: BoxShape.circle,
                        border: Border.all(color: bg, width: 5),
                        boxShadow: [BoxShadow(color: PaceColors.mint.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Icon(
                        index == 2 ? Icons.directions_run_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
