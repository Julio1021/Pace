import 'package:flutter_test/flutter_test.dart';
import 'package:pace/services/voice.dart';

void main() {
  test('reconhece vozes femininas e masculinas pelos nomes', () {
    expect(const PaceVoice('pt-br-x-afs-local', 'pt-BR').likelyFemale, isTrue);
    expect(const PaceVoice('pt-BR-SMTf00', 'pt-BR').likelyFemale, isTrue);
    expect(const PaceVoice('pt-BR-SMTm00', 'pt-BR').likelyMale, isTrue);
    expect(const PaceVoice('pt-br-x-ptd-network', 'pt-BR').likelyMale, isTrue);
    expect(const PaceVoice('pt-br-x-ptd-network', 'pt-BR').likelyFemale, isFalse);
  });
}
