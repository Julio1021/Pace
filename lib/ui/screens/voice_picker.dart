import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/voice.dart';
import '../../state/app_state.dart';

/// Lista as vozes em português do aparelho, com botão para ouvir cada uma.
class VoicePickerSheet extends StatefulWidget {
  const VoicePickerSheet({super.key});

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  static const _sample = 'Bora! Mais um quilômetro. Você está mandando bem.';
  final _tts = FlutterTts();
  List<PaceVoice>? _voices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _tts.setLanguage('pt-BR');
    final v = await VoiceService.portugueseVoices(_tts);
    if (mounted) setState(() => _voices = v);
  }

  Future<void> _play(String name) async {
    await _tts.stop();
    await VoiceService.apply(_tts, name);
    await _tts.speak(_sample);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final voices = _voices;
    Widget tile(String value, String title, String subtitle) {
      final sel = app.voiceName == value;
      return ListTile(
        leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: sel ? PaceColors.mintBright : null),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: IconButton(
          tooltip: 'Ouvir',
          icon: const Icon(Icons.play_circle_outline),
          onPressed: () => _play(value),
        ),
        onTap: () => app.setVoiceName(value),
      );
    }

    var f = 0, m = 0, o = 0;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Voz das falas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            tile(VoiceService.auto, 'Feminina (automática)', 'O PACE escolhe uma voz feminina do aparelho'),
            const Divider(height: 1),
            if (voices == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (voices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nenhuma voz em português encontrada. Instale em Configurações › '
                    'Gerenciamento geral › Conversão de texto em voz.'),
              )
            else
              for (final v in voices)
                tile(
                  v.name,
                  v.likelyFemale
                      ? 'Feminina ${++f}'
                      : v.likelyMale
                          ? 'Masculina ${++m}'
                          : 'Voz ${++o}',
                  '${v.online ? 'Online · ' : ''}${v.name}',
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text('Toque no ▶ para ouvir. Os nomes vêm do motor de voz do celular; '
                  'se uma "feminina" soar masculina, escolha outra ouvindo.'),
            ),
          ],
        ),
      ),
    );
  }
}
