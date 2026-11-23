import 'package:flutter/material.dart';

/// Escolha de "a cada quantos km" os avisos de voz acontecem.
class VoiceEveryPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final List<int> options;
  const VoiceEveryPicker({super.key, required this.value, required this.onChanged, this.options = runOptions});

  static const runOptions = [1, 2, 3, 5];
  static const bikeOptions = [1, 2, 5, 10];

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: options.contains(value) ? value : options.first,
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(14),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text('$o km'))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
