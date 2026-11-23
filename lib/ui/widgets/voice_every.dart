import 'package:flutter/material.dart';

/// Escolha de "a cada quantos km" os avisos de voz acontecem.
class VoiceEveryPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const VoiceEveryPicker({super.key, required this.value, required this.onChanged});

  static const options = [1, 2, 3, 5];

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: options.contains(value) ? value : 1,
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(14),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text('$o km'))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
