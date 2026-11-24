import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'ui/widgets/guara_art.dart';
import 'services/recorder.dart';
import 'state/app_state.dart';
import 'ui/intro_overlay.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/shell.dart';

class PaceApp extends StatelessWidget {
  const PaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PACE',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// Abertura → perfil (primeiro uso) → app.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Voltou ao app depois de um tempo fora: o Guará aparece de novo (modo "sempre").
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left == null) return;
      context.read<AppState>().appResumed(DateTime.now().difference(left), recording: context.read<Recorder>().isActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) return const SplashScreen();
    if (app.error != null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(app.error!))));
    }
    if (!app.profile.isComplete) return const OnboardingScreen();
    return Stack(
      children: [
        const HomeShell(),
        if (app.showIntroNow) IntroOverlay(onDone: app.introShown),
      ],
    );
  }
}

/// Abertura enquanto o app carrega: fundo claro em degradê (igual ao Início),
/// o Guará balançando, "PACE" e três pontinhos.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF3FF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC9F2E2), Color(0xFFEEF3FF), Color(0xFFE7DCFF)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, -6 * math.sin(t * 2 * math.pi).abs()),
                        child: SvgPicture.string(GuaraArt.head, width: 120, height: 120),
                      ),
                      const SizedBox(height: 14),
                      Text('PACE', style: numStyle(34, color: PaceColors.ink).copyWith(letterSpacing: 8)),
                      const SizedBox(height: 4),
                      const Text('Bora correr?', style: TextStyle(color: PaceColors.muted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 72,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: PaceColors.mint.withValues(alpha: 0.25 + 0.75 * (0.5 + 0.5 * math.sin((t - i * 0.18) * 2 * math.pi))),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
