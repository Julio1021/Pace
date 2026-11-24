import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/exporters.dart';
import '../../domain/models.dart';
import '../../services/pcloud.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/goal_editor.dart';
import '../widgets/guara.dart';
import '../widgets/pace_ui.dart';

/// Primeira abertura: boas-vindas com o Guará e cadastro em passos curtos
/// (nome → sobre você → experiência → meta → pronto). Também permite restaurar
/// um backup (pCloud ou arquivo) para quem está trocando de celular.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Level {
  final String name;
  final String desc;
  final IconData icon;
  final double goal;
  const _Level(this.name, this.desc, this.icon, this.goal);
}

const _levels = [
  _Level('Iniciante', 'Estou começando ou voltando a correr', Icons.directions_walk_rounded, 10),
  _Level('Intermediário', 'Corro com frequência, até uns 10 km', Icons.directions_run_rounded, 20),
  _Level('Avançado', 'Treino forte e faço provas de 21 km ou mais', Icons.bolt_rounded, 35),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  static const _steps = 5; // 0 boas-vindas · 1 nome · 2 você · 3 experiência · 4 meta · 5 pronto

  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  DateTime? _birth;
  double? _height;
  double? _weight;
  String? _sex;
  String _level = 'Iniciante';
  double _goal = 10;
  bool _goalTouched = false;
  bool _busy = false;

  String get _first => _name.text.trim().split(RegExp(r'\s+')).first;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _go(int p) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _page = p);
    _pages.animateToPage(p, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    if (p == 1) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _page == 1) _nameFocus.requestFocus();
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final app = context.read<AppState>();
    await app.saveProfile(UserProfile(
      name: _name.text.trim(),
      birthDate: _birth,
      heightCm: _height,
      weightKg: _weight,
      sex: _sex,
      level: _level,
      weeklyGoalKm: _goal,
    ));
    // A RootGate troca para o app assim que o perfil fica completo.
  }

  // ---------------- Restaurar backup ----------------

  Future<void> _restoreSheet() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: PaceColors.bgLight,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Trazer meus treinos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: PaceColors.ink)),
              ),
              if (PCloudService.configured)
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined, color: PaceColors.mint),
                  title: const Text('Do pCloud', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Conecta e restaura o backup mais recente'),
                  onTap: () => Navigator.pop(ctx, 0),
                ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined, color: PaceColors.mint),
                title: const Text('De um arquivo de backup', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('O .zip exportado pelo PACE'),
                onTap: () => Navigator.pop(ctx, 1),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      ({int restored, int skipped}) r;
      if (choice == 0) {
        await app.connectPCloud(backupNow: false);
        final c = app.pcloud;
        if (c == null) throw PCloudException(app.cloudError ?? 'A conexão com o pCloud não foi concluída.');
        final list = await c.list();
        if (list.isEmpty) throw const PCloudException('Nenhum backup do PACE encontrado no seu pCloud.');
        r = await app.restoreFromCloud(list.first.fileId);
      } else {
        final file = await FilePicker.pickFile(type: FileType.any);
        if (file == null) return;
        r = await BackupCodec.restore(app.db, await file.readAsBytes());
        app.profile = await app.db.getProfile();
        await app.reload();
      }
      if (!mounted) return;
      showSnack(context, 'Bem-vindo de volta! ${r.restored} treinos restaurados.');
      if (!app.profile.isComplete) _go(1); // backup sem perfil: segue o cadastro
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível restaurar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Interface ----------------

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0 && _page < 5) _go(_page - 1);
      },
      child: Scaffold(
        backgroundColor: PaceColors.bgLight,
        body: Stack(
          children: [
            const Positioned(top: 0, left: 0, right: 0, child: MeshBackground(height: 760)),
            Column(
              children: [
                SizedBox(height: pad.top),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _page == 0 || _page == 5
                      ? const SizedBox(height: 8)
                      : _TopBar(step: _page, total: _steps - 1, onBack: () => _go(_page - 1)),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _welcome(),
                      _nameStep(),
                      _aboutStep(),
                      _levelStep(),
                      _goalStep(),
                      _doneStep(),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator())),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scaffold({
    required GuaraPose pose,
    required String title,
    String? subtitle,
    required Widget child,
    required Widget bottom,
    double guara = 104,
  }) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 4, 22, 16 + MediaQuery.paddingOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 20 - MediaQuery.paddingOf(context).bottom),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Guara(pose: pose, size: guara, waves: pose == GuaraPose.wave ? 2 : 0),
                    const SizedBox(width: 8),
                    Expanded(child: _SpeechBubble(title: title, subtitle: subtitle)),
                  ],
                ),
                const SizedBox(height: 22),
                child,
                const Spacer(),
                const SizedBox(height: 20),
                bottom,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.paddingOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 16 - MediaQuery.paddingOf(context).bottom),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                const Appear(child: Center(child: _Bobbing(child: Guara(pose: GuaraPose.wave, size: 190, waves: 3)))),
                const SizedBox(height: 6),
                Appear(
                  delayMs: 120,
                  child: Text('PACE',
                      textAlign: TextAlign.center,
                      style: numStyle(44, color: PaceColors.mint).copyWith(letterSpacing: 10, height: 1)),
                ),
                const SizedBox(height: 10),
                Appear(
                  delayMs: 200,
                  child: Text(
                    'Seu parceiro de corrida',
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: PaceColors.ink),
                  ),
                ),
                const SizedBox(height: 6),
                const Appear(
                  delayMs: 260,
                  child: Text(
                    'Eu sou o Guará e vou correr do seu lado: gravo, incentivo e comemoro cada quilômetro com você.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.45, color: PaceColors.muted),
                  ),
                ),
                const SizedBox(height: 24),
                const Appear(
                  delayMs: 340,
                  child: _Features(items: [
                    (Icons.my_location_rounded, 'GPS preciso', 'Mapa, parciais e pace em tempo real'),
                    (Icons.record_voice_over_rounded, 'Voz que motiva', 'Avisos sem pausar sua música'),
                    (Icons.emoji_events_rounded, 'Recordes e medalhas', 'Veja sua evolução semana a semana'),
                    (Icons.lock_outline_rounded, 'Seus dados são seus', 'Tudo no celular, backup se quiser'),
                  ]),
                ),
                const Spacer(),
                const SizedBox(height: 24),
                Appear(
                  delayMs: 420,
                  child: _PrimaryButton(label: 'Vamos começar', icon: Icons.arrow_forward_rounded, onTap: () => _go(1)),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton.icon(
                    onPressed: _busy ? null : _restoreSheet,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Já uso o PACE · restaurar backup'),
                    style: TextButton.styleFrom(foregroundColor: PaceColors.mintDark, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameStep() {
    final ok = _name.text.trim().isNotEmpty;
    return _scaffold(
      pose: GuaraPose.wave,
      title: 'Como posso te chamar?',
      subtitle: 'É assim que vou falar com você nos treinos.',
      child: _Field(
        child: TextField(
          controller: _name,
          focusNode: _nameFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => ok ? _go(2) : null,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PaceColors.ink),
          decoration: const InputDecoration(
            hintText: 'Seu nome',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            prefixIcon: Icon(Icons.person_outline_rounded, color: PaceColors.mint),
          ),
        ),
      ),
      bottom: _PrimaryButton(label: 'Continuar', onTap: ok ? () => _go(2) : null),
    );
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 30),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Data de nascimento',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d != null) setState(() => _birth = d);
  }

  Future<void> _typeNumber({required String title, required String unit, double? value, required double min, required double max, required ValueChanged<double> onOk}) async {
    final c = TextEditingController(text: value == null ? '' : Fmt.km(value * 1000, decimals: value % 1 == 0 ? 0 : 1));
    String? error;
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(suffixText: unit, errorText: error),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final n = double.tryParse(c.text.trim().replaceAll(',', '.'));
                if (n == null || n < min || n > max) {
                  set(() => error = 'Entre ${min.round()} e ${max.round()} $unit');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (v != null) onOk(v);
  }

  Widget _aboutStep() {
    final hello = _first.isEmpty ? 'Prazer!' : 'Prazer, $_first!';
    String num(double v) => (v % 1 == 0 ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('.', ',');
    return _scaffold(
      pose: GuaraPose.celebrate,
      title: hello,
      subtitle: 'Me conta um pouco de você. Uso só para estimar as calorias, e dá para pular.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Tile(
            icon: Icons.cake_outlined,
            label: 'Nascimento',
            value: _birth == null ? null : Fmt.date(_birth!),
            onTap: _pickBirth,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.height_rounded,
                  label: 'Altura',
                  value: _height == null ? null : '${_height!.round()} cm',
                  onTap: () => _typeNumber(
                      title: 'Altura', unit: 'cm', value: _height, min: 100, max: 250, onOk: (v) => setState(() => _height = v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Peso',
                  value: _weight == null ? null : '${num(_weight!)} kg',
                  onTap: () => _typeNumber(
                      title: 'Peso', unit: 'kg', value: _weight, min: 25, max: 250, onOk: (v) => setState(() => _weight = v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Sexo (opcional)', style: TextStyle(fontWeight: FontWeight.w800, color: PaceColors.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (v, l) in const [('Feminino', 'Feminino'), ('Masculino', 'Masculino'), (null, 'Prefiro não dizer')])
                _Choice(label: l, selected: _sex == v, onTap: () => setState(() => _sex = v)),
            ],
          ),
        ],
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrimaryButton(label: 'Continuar', onTap: () => _go(3)),
          if (_birth == null && _height == null && _weight == null)
            TextButton(
              onPressed: () => _go(3),
              style: TextButton.styleFrom(foregroundColor: PaceColors.muted),
              child: const Text('Pular por enquanto'),
            ),
        ],
      ),
    );
  }

  Widget _levelStep() {
    return _scaffold(
      pose: GuaraPose.run,
      title: 'Como estão suas corridas?',
      subtitle: 'Assim eu sugiro uma meta do seu tamanho.',
      child: Column(
        children: [
          for (final l in _levels) ...[
            _LevelCard(
              level: l,
              selected: _level == l.name,
              onTap: () => setState(() {
                _level = l.name;
                if (!_goalTouched) _goal = l.goal;
              }),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      bottom: _PrimaryButton(label: 'Continuar', onTap: () => _go(4)),
    );
  }

  Widget _goalStep() {
    final runs = _goal <= 10 ? 2 : (_goal <= 25 ? 3 : 4);
    final each = _goal / runs;
    return _scaffold(
      pose: GuaraPose.run,
      title: 'Qual a sua meta por semana?',
      subtitle: 'Ela aparece no Início e no botão de correr. Dá para mudar quando quiser.',
      child: Theme(
        data: glassTheme,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            children: [
              GoalEditor(
                byTime: false,
                value: _goal,
                onChanged: (v) => setState(() {
                  _goal = v;
                  _goalTouched = true;
                }),
              ),
              const SizedBox(height: 12),
              Text(
                'Por exemplo: $runs corridas de ${Fmt.km(each * 1000, decimals: each % 1 == 0 ? 0 : 1)} km',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB8C1D1), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      bottom: _PrimaryButton(label: 'Concluir', onTap: () => _go(5)),
    );
  }

  Widget _doneStep() {
    final t = Theme.of(context).textTheme;
    final g = Fmt.km(_goal * 1000, decimals: _goal % 1 == 0 ? 0 : 1);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.paddingOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 16 - MediaQuery.paddingOf(context).bottom),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                if (_page == 5) const Center(child: _Bobbing(child: Guara(pose: GuaraPose.celebrate, size: 200))),
                const SizedBox(height: 14),
                Text(
                  _first.isEmpty ? 'Tudo pronto!' : 'Tudo pronto, $_first!',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: PaceColors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Meta de $g km por semana. Eu vou estar do seu lado em cada treino.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.45, color: PaceColors.muted),
                ),
                const SizedBox(height: 18),
                const _Features(items: [
                  (Icons.ios_share_rounded, 'Já corre com outro app?', 'Importe seus treinos em Perfil › Importar'),
                  (Icons.directions_bike_rounded, 'Também pedala?', 'Troque para Pedal na tela de treino'),
                ]),
                const Spacer(),
                const SizedBox(height: 20),
                _PrimaryButton(label: 'Bora correr!', icon: Icons.directions_run_rounded, onTap: _busy ? null : _finish),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Peças ----------------

class _TopBar extends StatelessWidget {
  final int step; // 1..total
  final int total;
  final VoidCallback onBack;
  const _TopBar({required this.step, required this.total, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 20, 4),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: PaceColors.ink), tooltip: 'Voltar'),
          const SizedBox(width: 4),
          for (var i = 1; i <= total; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                decoration: BoxDecoration(
                  color: i <= step ? PaceColors.mint : PaceColors.ink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (i < total) const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          Text('$step de $total', style: const TextStyle(fontWeight: FontWeight.w700, color: PaceColors.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SpeechBubble({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
        ),
        boxShadow: [BoxShadow(color: PaceColors.ink.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: PaceColors.ink, height: 1.2)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 13.5, height: 1.4, color: PaceColors.muted)),
          ],
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  final List<(IconData, String, String)> items;
  const _Features({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        children: [
          for (final (icon, title, sub) in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: PaceColors.mintSoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: PaceColors.mintDark, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: PaceColors.ink, fontSize: 14.5)),
                        Text(sub, style: const TextStyle(color: PaceColors.muted, fontSize: 12.8)),
                      ],
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: PaceColors.mint,
          disabledBackgroundColor: PaceColors.mint.withValues(alpha: 0.3),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          elevation: onTap == null ? 0 : 3,
          shadowColor: PaceColors.mint.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 22)],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final Widget child;
  const _Field({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PaceColors.mint.withValues(alpha: 0.5), width: 1.5),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = value != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: filled ? PaceColors.mint : PaceColors.ink.withValues(alpha: 0.08), width: 1.4),
          ),
          child: Row(
            children: [
              Icon(icon, color: filled ? PaceColors.mint : PaceColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PaceColors.muted)),
                    Text(
                      value ?? 'Tocar para informar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: filled ? 17 : 14,
                        fontWeight: filled ? FontWeight.w800 : FontWeight.w600,
                        color: filled ? PaceColors.ink : PaceColors.muted.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Choice({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? PaceColors.mint : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? PaceColors.mint : PaceColors.ink.withValues(alpha: 0.1)),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : PaceColors.ink)),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final _Level level;
  final bool selected;
  final VoidCallback onTap;
  const _LevelCard({required this.level, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? PaceColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? PaceColors.mintBright : PaceColors.ink.withValues(alpha: 0.08), width: 1.6),
            boxShadow: selected
                ? [BoxShadow(color: PaceColors.mint.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? PaceColors.mintBright.withValues(alpha: 0.18) : PaceColors.mintSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(level.icon, color: selected ? PaceColors.mintBright : PaceColors.mintDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: selected ? Colors.white : PaceColors.ink)),
                    const SizedBox(height: 2),
                    Text(level.desc,
                        style: TextStyle(fontSize: 13, color: selected ? const Color(0xFFB8C1D1) : PaceColors.muted)),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected ? 1 : 0,
                child: const Icon(Icons.check_circle_rounded, color: PaceColors.mintBright),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sobe e desce devagar (Guará "respirando").
class _Bobbing extends StatefulWidget {
  final Widget child;
  const _Bobbing({required this.child});

  @override
  State<_Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<_Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context)) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, -6 * Curves.easeInOut.transform(_c.value)), child: child),
      );
}
