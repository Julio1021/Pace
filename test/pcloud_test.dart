import 'package:flutter_test/flutter_test.dart';
import 'package:pace/services/pcloud.dart';

void main() {
  test('lê o retorno do login (token no fragmento)', () {
    final c = PCloudService.parseRedirect('pace-pcloud://oauth#access_token=ABC123&token_type=bearer&uid=1&locationid=2&hostname=eapi.pcloud.com');
    expect(c.token, 'ABC123');
    expect(c.host, 'eapi.pcloud.com');
  });

  test('sem hostname usa o local pelo locationid', () {
    expect(PCloudService.parseRedirect('pace-pcloud://oauth#access_token=X&locationid=1').host, 'api.pcloud.com');
  });

  test('recusa vira erro claro', () {
    expect(() => PCloudService.parseRedirect('pace-pcloud://oauth#error=access_denied'), throwsA(isA<PCloudException>()));
  });
}
