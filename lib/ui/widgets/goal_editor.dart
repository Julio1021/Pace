import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'pace_ui.dart';

/// Editor da meta: número grande editável (toque para digitar), botões − e +
/// redondos (segurar repete) e atalhos rápidos.
class GoalEditor extends StatelessWidget {
  final bool byTime;
  final double value; // km ou minutos
  final ValueChanged<double> onChanged;

  const GoalEditor({super.key, required this.byTime, required this.value, required this.onChanged});

  double get _min => byTime ? 5 : 0.5;
  double get _max => byTime ? 600 : 100;

  String _fmt(double v) => byTime
      ? '${v.round()}'
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)).replaceAll('.', ',');

  void _step(int dir) {
    double next;
    if (byTime) {
      next = ((value / 5).round() * 5 + dir * 5).toDouble();
    } else {
      // De 1 em 1 km; se estiver quebrado (7,5), vai para o inteiro mais próximo na direção.
      next = dir > 0 ? (value.floorToDouble() + 1) : (value.ceilToDouble() - 1);
    }
    next = next.clamp(_min, _max);
    if (next != value) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }
  }

  Future<void> _type(BuildContext context) async {
    final ctrl = TextEditingController(text: _fmt(value));
    String? error;
    final v = await showDialog<double>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          void submit() {
            final n = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
            if (n == null || n < _min || n > _max) {
              set(() => error = byTime ? 'Digite de 5 a 600 minutos' : 'Digite de 0,5 a 100 km');
              return;
            }
            Navigator.pop(c, byTime ? n.roundToDouble() : (n * 10).round() / 10);
          }

          return AlertDialog(
            title: Text(byTime ? 'Meta de tempo' : 'Meta de distância'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: !byTime),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              textAlign: TextAlign.center,
              style: numStyle(34, color: Theme.of(c).colorScheme.onSurface),
              decoration: InputDecoration(
                suffixText: byTime ? 'min' : 'km',
                errorText: error,
                hintText: byTime ? '45' : '7,5',
              ),
              onChanged: (_) {
                if (error != null) set(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
              FilledButton(onPressed: submit, child: const Text('Definir')),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (v != null) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final quick = byTime ? const [20.0, 30.0, 45.0, 60.0, 90.0] : const [3.0, 5.0, 8.0, 10.0, 15.0, 21.1, 42.2];
    return Column(
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(icon: Icons.remove_rounded, label: 'Menos', onStep: value > _min ? () => _step(-1) : null),
            const SizedBox(width: 14),
            Semantics(
              button: true,
              label: 'Meta ${_fmt(value)} ${byTime ? 'minutos' : 'quilômetros'}, toque para digitar',
              child: GestureDetector(
                onTap: () => _type(context),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: PaceColors.mintBright.withValues(alpha: 0.55), width: 1.4),
                  ),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: _fmt(value), style: numStyle(36, color: Colors.white)),
                          TextSpan(text: byTime ? ' min' : ' km', style: numStyle(16, color: const Pal(true).muted)),
                        ])),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, size: 12, color: PaceColors.mintBright.withValues(alpha: 0.9)),
                          const SizedBox(width: 4),
                          Text('toque para digitar',
                              style: TextStyle(fontSize: 10.5, color: PaceColors.mintBright.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            _RoundButton(icon: Icons.add_rounded, label: 'Mais', onStep: value < _max ? () => _step(1) : null),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in quick)
              _QuickChip(
                text: byTime ? '${q.round()} min' : '${_fmt(q)} km',
                selected: (q - value).abs() < 0.01,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(q);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Botão redondo de vidro com anel menta; segurar repete o passo.
class _RoundButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onStep;
  const _RoundButton({required this.icon, required this.label, this.onStep});

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  Timer? _repeat;
  bool _down = false;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    if (_down) setState(() => _down = false);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onStep != null;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.label,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapUp: on ? (_) => _stop() : null,
        onTapCancel: _stop,
        onTap: widget.onStep,
        onLongPressStart: on
            ? (_) {
                setState(() => _down = true);
                _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) => widget.onStep?.call());
              }
            : null,
        onLongPressEnd: (_) => _stop(),
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on
                    ? [const Color(0xFF3A4454), const Color(0xFF1B212B)]
                    : [const Color(0xFF2A303A), const Color(0xFF20252E)],
              ),
              border: Border.all(color: on ? PaceColors.mintBright.withValues(alpha: _down ? 0.9 : 0.45) : Colors.white10, width: 1.5),
              boxShadow: on
                  ? [BoxShadow(color: PaceColors.mintBright.withValues(alpha: _down ? 0.35 : 0.15), blurRadius: _down ? 14 : 8)]
                  : null,
            ),
            child: Icon(widget.icon, color: on ? PaceColors.mintBright : Colors.white24, size: 28),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _QuickChip({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PaceColors.mintBright : Colors.white.withValues(alpha: 0.07),
      shape: StadiumBorder(side: BorderSide(color: selected ? PaceColors.mintBright : Colors.white.withValues(alpha: 0.12))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? PaceColors.ink : Colors.white.withValues(alpha: 0.85),
              )),
        ),
      ),
    );
  }
}

/// Seletor de meta (Livre / Distância / Tempo) em pílulas de vidro.
class GoalModePicker<T> extends StatelessWidget {
  final List<(T, String, IconData)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const GoalModePicker({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (final (v, label, icon) in options)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (v != value) HapticFeedback.selectionClick();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: v == value
                        ? const LinearGradient(colors: [PaceColors.mintBright, PaceColors.mint])
                        : null,
                    boxShadow: v == value
                        ? [BoxShadow(color: PaceColors.mintBright.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 17, color: v == value ? PaceColors.ink : Colors.white70),
                      const SizedBox(width: 6),
                      Text(label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: v == value ? PaceColors.ink : Colors.white.withValues(alpha: 0.85),
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
