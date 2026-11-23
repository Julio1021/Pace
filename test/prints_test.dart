// Gera imagens (prints) das principais telas com dados de exemplo.
// Executado no GitHub Actions com:
//   flutter test --update-goldens --dart-define=PRINTS=true --dart-define=FLUTTER_ROOT=$FLUTTER_ROOT test/prints_test.dart
// Sem PRINTS=true os testes são ignorados.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pace/core/theme.dart';
import 'package:pace/data/import_service.dart';
import 'package:pace/data/importers.dart';
import 'package:pace/domain/models.dart';
import 'package:pace/domain/intro_messages.dart';
import 'package:pace/services/recorder.dart';
import 'package:pace/state/app_state.dart';
import 'package:pace/ui/intro_overlay.dart';
import 'package:pace/ui/screens/activity_detail_screen.dart';
import 'package:pace/domain/achievements.dart';
import 'package:pace/domain/plans.dart';
import 'package:pace/ui/widgets/achievement_widgets.dart';
import 'package:pace/ui/widgets/share_card.dart';
import 'package:pace/services/weather.dart';
import 'package:pace/ui/screens/home_screen.dart';
import 'package:pace/ui/screens/reminders_screen.dart';
import 'package:pace/ui/screens/records_screen.dart';
import 'package:pace/ui/screens/plans_screen.dart';
import 'package:pace/ui/screens/achievements_screen.dart';
import 'package:pace/ui/screens/import_screen.dart';
import 'package:pace/ui/screens/live_run_screen.dart';
import 'package:pace/ui/screens/profile_edit_screen.dart';
import 'package:pace/ui/screens/run_setup_screen.dart';
import 'package:pace/ui/shell.dart';
import 'package:pace/ui/widgets/route_widgets.dart';
import 'package:pace/ui/widgets/sky_scene.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';

const _enabled = bool.fromEnvironment('PRINTS');
const _flutterRoot = String.fromEnvironment('FLUTTER_ROOT');

Future<void> _loadFonts() async {
  final dir = Directory('$_flutterRoot/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  final icons = FontLoader('MaterialIcons');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final data = f.readAsBytes().then((b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf') && !name.contains('Italic')) roboto.addFont(data);
    if (name.startsWith('MaterialIcons')) icons.addFont(data);
  }
  await roboto.load();
  await icons.load();
  final sg = FontLoader('SpaceGrotesk');
  for (final f in ['assets/fonts/SpaceGrotesk-Medium.ttf', 'assets/fonts/SpaceGrotesk-Bold.ttf']) {
    sg.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await sg.load();
}

class _Env {
  final AppState app;
  final Recorder rec;
  _Env(this.app, this.rec);
}

Future<_Env> _makeEnv(WidgetTester tester, {bool withData = true, bool withProfile = true}) async {
  late _Env env;
  await tester.runAsync(() async {
    final db = await openTestDb();
    if (withProfile) {
      await db.saveProfile(UserProfile(
        name: 'Júlio César',
        birthDate: DateTime(1990, 5, 10),
        heightCm: 176,
        weightKg: 74,
        level: 'Intermediário',
        weeklyGoalKm: 20,
      ));
    }
    if (withData) {
      final now = DateTime.now().toUtc();
      final items = <ImportItem>[
        ImportItem('nrc_2016-11-24.tcx', fixture('nrc_2016-11-24.tcx')),
        ImportItem('nrc_2016-11-20.tcx', fixture('nrc_2016-11-20.tcx')),
      ];
      // Corridas de exemplo (só para os prints): últimas três semanas.
      const plan = [
        (days: 1, km: 6.2, v: 3.45),
        (days: 3, km: 5.0, v: 3.3),
        (days: 5, km: 10.4, v: 3.2),
        (days: 8, km: 5.6, v: 3.35),
        (days: 10, km: 7.1, v: 3.25),
        (days: 12, km: 12.0, v: 3.1),
        (days: 16, km: 5.0, v: 3.2),
        (days: 19, km: 8.3, v: 3.15),
        (days: 33, km: 6.0, v: 3.05),
        (days: 40, km: 9.0, v: 3.0),
      ];
      for (final p in plan) {
        final start = DateTime.utc(now.year, now.month, now.day, 9, 15).subtract(Duration(days: p.days));
        items.add(ImportItem('ex_${p.days}.gpx',
            utf8.encode(syntheticGpx(startUtc: start, distanceM: p.km * 1000, baseSpeed: p.v))));
      }
      await ImportService.run(db, items, weightKg: 74);
    }
    final app = AppState()..autoBackground = false;
    await app.init(database: db);
    await app.afterChange();
    final rec = Recorder(db: () => app.db, weightKg: () => app.profile.weightForCalc);
    env = _Env(app, rec);
  });
  return env;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Widget _wrap(_Env env, Widget home, {ThemeMode mode = ThemeMode.light}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: env.app),
        ChangeNotifierProvider.value(value: env.rec),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Prints sem animação (mostra o estado final de cada efeito).
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _shot(WidgetTester tester, String name, {double height = 844}) async {
  tester.view.physicalSize = Size(390 * 2.0, height * 2.0);
  tester.view.devicePixelRatio = 2.0;
  await _settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('prints/$name.png'));
}

Future<void> _tab(WidgetTester tester, String label) async {
  const idx = {'Início': 0, 'Histórico': 1, 'Correr': 2, 'Evolução': 3, 'Perfil': 4};
  await tester.tap(find.byKey(ValueKey('nav-${idx[label]}')));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    MapConfig.tilesEnabled = false;
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    if (_enabled) await _loadFonts();
  });

  testWidgets('01 boas-vindas', (tester) async {
    final env = await _makeEnv(tester, withData: false, withProfile: false);
    await tester.pumpWidget(_wrap(env, const ProfileEditScreen(onboarding: true)));
    await _shot(tester, '01-boas-vindas');
  }, skip: !_enabled);

  testWidgets('02 início', (tester) async {
    final env = await _makeEnv(tester);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _shot(tester, '02-inicio', height: 1700);
  }, skip: !_enabled);

  testWidgets('02b Guará do Início em cada humor', (tester) async {
    final n = DateTime.now();
    final day = DateTime(n.year, n.month, n.day, 10);
    final cases = <String, (DateTime, double)>{
      'a-acenando': (day, 200),
      'b-comemorando': (day, 20),
      'c-chamando': (day.add(const Duration(days: 15)), 20),
      'd-dormindo': (DateTime(n.year, n.month, n.day, 23), 20),
    };
    for (final e in cases.entries) {
      HomeScreen.clock = () => e.value.$1;
      final env = await _makeEnv(tester);
      await tester.runAsync(() => env.app.saveProfile(env.app.profile.copyWith(weeklyGoalKm: e.value.$2)));
      await tester.pumpWidget(_wrap(env, const HomeShell()));
      await _settle(tester);
      await _shot(tester, '02-inicio-${e.key}', height: 420);
    }
    HomeScreen.clock = DateTime.now;
  }, skip: !_enabled);

  testWidgets('04 histórico', (tester) async {
    final env = await _makeEnv(tester);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Histórico');
    await _shot(tester, '04-historico', height: 1300);
  }, skip: !_enabled);

  testWidgets('05 correr', (tester) async {
    final env = await _makeEnv(tester);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Correr');
    await _shot(tester, '05-correr', height: 1000);
  }, skip: !_enabled);

  testWidgets('05b céu da tela Correr em cada momento', (tester) async {
    final sun = SunTimes.of(DateTime.now(), SkyInfo.defaultLat, SkyInfo.defaultLon);
    final moments = <String, DateTime>{
      'a-aurora': sun.sunrise.subtract(const Duration(minutes: 30)),
      'b-nascer': sun.sunrise.add(const Duration(minutes: 25)),
      'c-dia': sun.sunrise.add(const Duration(hours: 4)),
      'd-por': sun.sunset.subtract(const Duration(minutes: 35)),
      'e-anoitecer': sun.sunset.add(const Duration(minutes: 25)),
      'f-noite': sun.sunset.add(const Duration(hours: 3)),
    };
    for (final e in moments.entries) {
      RunSetupScreen.clock = () => e.value;
      final env = await _makeEnv(tester);
      await tester.pumpWidget(_wrap(env, const HomeShell()));
      await _settle(tester);
      await _tab(tester, 'Correr');
      await _shot(tester, '05-correr-${e.key}', height: 900);
    }
    RunSetupScreen.clock = DateTime.now;
  }, skip: !_enabled);

  testWidgets('05c céu com o tempo e meta editável', (tester) async {
    final sun = SunTimes.of(DateTime.now(), SkyInfo.defaultLat, SkyInfo.defaultLon);
    RunSetupScreen.clock = () => sun.sunrise.add(const Duration(hours: 4));
    final cases = <String, WeatherNow>{
      'chuva': WeatherNow(kind: WeatherKind.rain, tempC: 18, windKmh: 14, fetchedAt: DateTime.now()),
      'tempestade': WeatherNow(kind: WeatherKind.storm, tempC: 17, windKmh: 30, fetchedAt: DateTime.now()),
      'neblina': WeatherNow(kind: WeatherKind.fog, tempC: 14, windKmh: 3, fetchedAt: DateTime.now()),
      'nublado': WeatherNow(kind: WeatherKind.cloudy, tempC: 21, windKmh: 8, fetchedAt: DateTime.now()),
    };
    for (final e in cases.entries) {
      final env = await _makeEnv(tester);
      env.app.weather = e.value;
      await tester.pumpWidget(_wrap(env, const HomeShell()));
      await _settle(tester);
      await _tab(tester, 'Correr');
      if (e.key == 'chuva') {
        await tester.tap(find.text('Treino'));
        await _settle(tester);
        await tester.tap(find.text('Distância'));
        await _settle(tester);
      }
      await _shot(tester, '05-correr-clima-${e.key}', height: e.key == 'chuva' ? 1250 : 900);
    }
    RunSetupScreen.clock = DateTime.now;
  }, skip: !_enabled);

  testWidgets('06 evolução', (tester) async {
    final env = await _makeEnv(tester);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Evolução');
    await _shot(tester, '06-evolucao', height: 1500);
  }, skip: !_enabled);

  testWidgets('07 perfil', (tester) async {
    final env = await _makeEnv(tester);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Perfil');
    await _shot(tester, '07-perfil', height: 1300);
  }, skip: !_enabled);

  testWidgets('08 detalhe com GPS', (tester) async {
    final env = await _makeEnv(tester);
    final id = env.app.activities.firstWhere((a) => a.distanceM > 10000 && a.source == ActivitySource.gpx).id!;
    await tester.pumpWidget(_wrap(env, ActivityDetailScreen(activityId: id)));
    await _shot(tester, '08-detalhe', height: 2600);
  }, skip: !_enabled);

  testWidgets('09 detalhe NRC (GPS parcial)', (tester) async {
    final env = await _makeEnv(tester);
    final id = env.app.activities.firstWhere((a) => a.source == ActivitySource.tcx).id!;
    await tester.pumpWidget(_wrap(env, ActivityDetailScreen(activityId: id)));
    await _shot(tester, '09-detalhe-nrc', height: 1400);
  }, skip: !_enabled);

  testWidgets('10 corrida em andamento', (tester) async {
    final env = await _makeEnv(tester);
    late ActivityBundle b;
    await tester.runAsync(() async {
      final id = env.app.activities.firstWhere((a) => a.source == ActivitySource.gpx).id!;
      b = (await env.app.db.getBundle(id))!;
    });
    final rec = env.rec
      ..state = RecState.running
      ..startTime = DateTime.now().toUtc().subtract(const Duration(minutes: 23, seconds: 40))
      ..distance = 4237
      ..moving = 1306;
    rec.points.addAll(b.points.where((p) => p.dist <= 4237));
    await tester.pumpWidget(_wrap(env, const LiveRunScreen()));
    await _shot(tester, '10-corrida');
  }, skip: !_enabled);

  testWidgets('03 corrida salva', (tester) async {
    final env = await _makeEnv(tester);
    final id = env.app.activities.first.id!;
    await tester.pumpWidget(_wrap(env, ActivityDetailScreen(activityId: id, justFinished: true)));
    await _shot(tester, '03-corrida-salva', height: 1200);
  }, skip: !_enabled);

  testWidgets('20 etapa 2', (tester) async {
    final env = await _makeEnv(tester);
    await tester.runAsync(() async {
      await env.app.saveProfile(env.app.profile.copyWith(monthlyGoalKm: 80, yearlyGoalKm: 1000));
      await env.app.startPlan('rumo10k', DateTime.now().subtract(const Duration(days: 9)));
      await env.app.afterChange();
    });
    final shots = <String, (Widget, double)>{
      '20-recordes': (const RecordsScreen(), 1200),
      '21-conquistas': (const AchievementsScreen(), 2300),
      '22-planos': (const PlansScreen(), 1100),
      '23-plano-detalhe': (PlanDetailScreen(plan: TrainingPlan.byId('rumo10k')!), 1500),
      '24-lembretes': (const RemindersScreen(), 1000),
    };
    for (final e in shots.entries) {
      await tester.pumpWidget(_wrap(env, e.value.$1));
      await _settle(tester);
      await _shot(tester, e.key, height: e.value.$2);
    }
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _shot(tester, '25-inicio-com-plano', height: 1300);
    await _tab(tester, 'Evolução');
    await _shot(tester, '26-evolucao-metas', height: 1300);
    await _tab(tester, 'Histórico');
    await tester.tap(find.byTooltip('Ver calendário'));
    await _settle(tester);
    await _shot(tester, '27-calendario', height: 1100);
    await _tab(tester, 'Perfil');
    await _shot(tester, '28-perfil', height: 2200);
  }, skip: !_enabled);

  testWidgets('29 todas as medalhas', (tester) async {
    final env = await _makeEnv(tester);
    final all = [
      for (final b in computeAchievements(const [], const {}))
        Achievement(
          id: b.id,
          group: b.group,
          title: b.title,
          description: b.description,
          icon: b.icon,
          color: b.color,
          tier: b.tier,
          unlockedAt: DateTime.utc(2026),
        ),
    ];
    final locked = computeAchievements(const [], const {}).take(4).toList();
    await tester.pumpWidget(_wrap(
      env,
      Scaffold(
        backgroundColor: const Color(0xFF161B23),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 4,
            runSpacing: 6,
            children: [
              for (final b in [...all, ...locked])
                SizedBox(
                  width: 90,
                  child: Column(children: [
                    BadgeMedal(badge: b, size: 80),
                    Text(b.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    ));
    await _shot(tester, '29-medalhas', height: 1650);
  }, skip: !_enabled);

  testWidgets('30 compartilhar e anos', (tester) async {
    final env = await _makeEnv(tester);
    final a = env.app.activities.firstWhere((x) => x.previewPoints.length > 5);
    for (final st in ShareStyle.values) {
      await tester.pumpWidget(_wrap(env, ShareRunScreen(activity: a, highlight: 'Novo recorde: 5 km')));
      await _settle(tester);
      if (st != ShareStyle.night) {
        await tester.tap(find.text(st.label));
        await _settle(tester);
      }
      await _shot(tester, '30-compartilhar-${st.name}', height: 844);
    }
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Evolução');
    await tester.scrollUntilVisible(find.text('Tudo'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Tudo'));
    await _settle(tester);
    await _shot(tester, '31-evolucao-tudo', height: 1500);
  }, skip: !_enabled);

  testWidgets('12 início vazio', (tester) async {
    final env = await _makeEnv(tester, withData: false);
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _shot(tester, '12-inicio-vazio');
  }, skip: !_enabled);

  testWidgets('13 abertura', (tester) async {
    final env = await _makeEnv(tester);
    const msgs = [
      IntroMessage(
        title: 'Bom dia, Júlio!',
        text: 'Faltam 8,3 km para a meta da semana. Você consegue!',
        tip: 'Aqueça de 5 a 10 minutos antes de acelerar.',
        tipIsAdvice: true,
        pose: GuaraPoseHint.wave,
        entrance: IntroEntrance.runIn,
      ),
      IntroMessage(
        title: 'Boa tarde, Júlio!',
        text: 'Ontem foram 12,00 km de corrida. Mandou bem!',
        tip: 'O treino mais difícil é o de sair de casa. O resto vem.',
        tipIsAdvice: false,
        pose: GuaraPoseHint.celebrate,
        entrance: IntroEntrance.drop,
      ),
      IntroMessage(
        title: 'Boa noite, Júlio!',
        text: 'Hora de descansar. Amanhã a gente treina com energia.',
        tip: 'Dormir bem é parte do treino. É no descanso que o corpo evolui.',
        tipIsAdvice: true,
        pose: GuaraPoseHint.sleep,
        entrance: IntroEntrance.peek,
      ),
    ];
    for (final (i, m) in msgs.indexed) {
      await tester.pumpWidget(_wrap(env, IntroOverlay(key: ValueKey(i), onDone: () {}, message: m)));
      await _shot(tester, i == 0 ? '13-abertura' : '13-abertura-${i + 1}');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  }, skip: !_enabled);

  testWidgets('11 importar', (tester) async {
    final env = await _makeEnv(tester, withData: false);
    await tester.pumpWidget(_wrap(env, const ImportScreen()));
    await _shot(tester, '11-importar');
  }, skip: !_enabled);

  testWidgets('40 pedal', (tester) async {
    final env = await _makeEnv(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      for (final d in [1, 4]) {
        final start = DateTime.utc(now.year, now.month, now.day, 7).subtract(Duration(days: d));
        final gpx = syntheticGpx(startUtc: start, distanceM: d == 1 ? 32400 : 21000, baseSpeed: 7.2)
            .replaceFirst('<trk><trkseg>', '<trk><type>cycling</type><trkseg>');
        await ImportService.run(env.app.db, [ImportItem('pedal_$d.gpx', utf8.encode(gpx))], weightKg: 74);
      }
      await env.app.reload();
      await env.app.setSport(Sport.bike);
    });
    await tester.pumpWidget(_wrap(env, const HomeShell()));
    await _settle(tester);
    await _tab(tester, 'Correr');
    await _shot(tester, '40-pedal-preparar', height: 1000);
    await tester.ensureVisible(find.text('Ajustes do pedal'));
    await tester.tap(find.text('Ajustes do pedal'));
    await _settle(tester);
    await _shot(tester, '41-pedal-ajustes', height: 1400);
    await _tab(tester, 'Histórico');
    await _shot(tester, '42-historico-com-pedal', height: 1100);
    final ride = env.app.rides.first;
    await tester.pumpWidget(_wrap(env, ActivityDetailScreen(activityId: ride.id!)));
    await _shot(tester, '43-pedal-detalhe', height: 2400);
    await tester.pumpWidget(_wrap(env, const RecordsScreen()));
    await _shot(tester, '44-recordes-pedal', height: 1500);
    late ActivityBundle b;
    await tester.runAsync(() async => b = (await env.app.db.getBundle(ride.id!))!);
    final rec = env.rec
      ..config = const RunConfig(sport: Sport.bike, type: 'Pedal longo')
      ..state = RecState.running
      ..startTime = DateTime.now().toUtc().subtract(const Duration(minutes: 49))
      ..distance = 18420
      ..moving = 2830
      ..maxKmh = 38.6;
    rec.points.addAll(b.points.where((p) => p.dist <= 18420));
    await tester.pumpWidget(_wrap(env, const LiveRunScreen()));
    await _shot(tester, '45-pedalando');
    rec.state = RecState.idle;
  }, skip: !_enabled);
}
