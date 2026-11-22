import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../widgets/guara.dart';

/// Criação e edição do perfil do corredor. Na primeira abertura funciona como boas-vindas.
class ProfileEditScreen extends StatefulWidget {
  final bool onboarding;
  const ProfileEditScreen({super.key, this.onboarding = false});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _goal;
  DateTime? _birth;
  String? _sex;
  late String _level;
  bool _saving = false;

  static const levels = ['Iniciante', 'Intermediário', 'Avançado'];

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile;
    _name = TextEditingController(text: p.name);
    _height = TextEditingController(text: p.heightCm?.round().toString() ?? '');
    _weight = TextEditingController(text: p.weightKg == null ? '' : _num(p.weightKg!));
    _goal = TextEditingController(text: _num(p.weeklyGoalKm));
    _birth = p.birthDate;
    _sex = p.sex;
    _level = levels.contains(p.level) ? p.level : levels.first;
  }

  static String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _weight.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 30),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Data de nascimento',
    );
    if (d != null) setState(() => _birth = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final h = _parse(_height.text);
    final w = _parse(_weight.text);
    final p = UserProfile(
      name: _name.text.trim(),
      birthDate: _birth,
      heightCm: h,
      weightKg: w,
      sex: _sex,
      level: _level,
      weeklyGoalKm: _parse(_goal.text) ?? 15,
    );
    await app.saveProfile(p);
    if (!mounted) return;
    if (!widget.onboarding) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Scaffold(
      appBar: widget.onboarding ? null : AppBar(title: const Text('Meu perfil')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              if (widget.onboarding) ...[
                const SizedBox(height: 8),
                const Center(child: Guara(pose: GuaraPose.wave, size: 170)),
                const SizedBox(height: 8),
                Center(child: Text('PACE', style: t.headlineMedium?.copyWith(letterSpacing: 4, color: cs.primary))),
                const SizedBox(height: 16),
                Text('Oi! Eu sou o Guará. Vamos criar seu perfil de corredor?', style: t.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'O peso é usado para estimar calorias e a meta semanal aparece no início. '
                  'Tudo fica salvo só no seu celular.',
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ],
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome *', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickBirth,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data de nascimento', prefixIcon: Icon(Icons.cake_outlined)),
                  child: Text(_birth == null ? 'Não informada' : Fmt.date(_birth!)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numFmt,
                      decoration: const InputDecoration(labelText: 'Altura', suffixText: 'cm'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final h = _parse(v);
                        return (h == null || h < 100 || h > 250) ? 'Entre 100 e 250' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numFmt,
                      decoration: const InputDecoration(labelText: 'Peso', suffixText: 'kg'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final w = _parse(v);
                        return (w == null || w < 25 || w > 250) ? 'Entre 25 e 250' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _sex,
                decoration: const InputDecoration(labelText: 'Sexo (opcional)'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Prefiro não informar')),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                  DropdownMenuItem(value: 'Masculino', child: Text('Masculino')),
                ],
                onChanged: (v) => setState(() => _sex = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _level,
                decoration: const InputDecoration(labelText: 'Nível de experiência'),
                items: levels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _goal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numFmt,
                decoration: const InputDecoration(
                  labelText: 'Meta semanal',
                  suffixText: 'km',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (v) {
                  final g = _parse(v ?? '');
                  return (g == null || g <= 0 || g > 500) ? 'Informe uma meta entre 1 e 500 km' : null;
                },
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(widget.onboarding ? 'Começar' : 'Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
