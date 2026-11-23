import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Client ID do app "PACE" cadastrado em https://docs.pcloud.com/my_apps/
/// (vazio até a pCloud aprovar). Pode vir do build: --dart-define=PCLOUD_CLIENT_ID=...
const pcloudClientId = String.fromEnvironment('PCLOUD_CLIENT_ID', defaultValue: '');

/// Endereço de retorno cadastrado no app da pCloud (Redirect URI).
const pcloudRedirect = 'pace-pcloud://oauth';

/// Um backup guardado no pCloud.
class CloudBackup {
  final int fileId;
  final String name;
  final int size;
  final DateTime created;
  const CloudBackup(this.fileId, this.name, this.size, this.created);
}

class PCloudException implements Exception {
  final String message;
  const PCloudException(this.message);
  @override
  String toString() => message;
}

/// Conexão com o pCloud: login (OAuth no navegador), envio, lista, download e limpeza.
/// Com acesso "Private", o app só enxerga a própria pasta (Applications/PACE).
class PCloudService {
  static const _ch = MethodChannel('pace/run_notification');

  final String token;
  final String host; // api.pcloud.com (EUA) ou eapi.pcloud.com (Europa)
  const PCloudService(this.token, this.host);

  static bool get configured => pcloudClientId.isNotEmpty;

  /// Abre o login da pCloud no navegador. O retorno chega por [waitForLogin].
  static Future<void> startLogin() async {
    final url = Uri.https('my.pcloud.com', '/oauth2/authorize', {
      'client_id': pcloudClientId,
      'response_type': 'token',
      'redirect_uri': pcloudRedirect,
    });
    await _ch.invokeMethod('openUrl', url.toString());
  }

  static bool _cancel = false;

  /// Desiste de esperar o login (botão Cancelar).
  static void cancelLogin() => _cancel = true;

  /// Espera o navegador voltar para o app com o token (até 5 minutos).
  static Future<PCloudService> waitForLogin() async {
    _cancel = false;
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (_cancel) throw const PCloudException('Conexão cancelada.');
      final String? link = await _ch.invokeMethod<String>('takeOAuthResult');
      if (link != null && link.startsWith(pcloudRedirect)) return parseRedirect(link);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    throw const PCloudException('O login no pCloud não foi concluído.');
  }

  /// Lê "pace-pcloud://oauth#access_token=...&hostname=...&locationid=..".
  static PCloudService parseRedirect(String link) {
    final i = link.indexOf('#');
    final q = i >= 0 ? link.substring(i + 1) : (Uri.tryParse(link)?.query ?? '');
    final p = Uri.splitQueryString(q);
    if (p['error'] != null) throw PCloudException('pCloud recusou o acesso (${p['error']}).');
    final token = p['access_token'];
    if (token == null || token.isEmpty) throw const PCloudException('pCloud não devolveu o acesso.');
    final host = p['hostname'] ?? (p['locationid'] == '2' ? 'eapi.pcloud.com' : 'api.pcloud.com');
    return PCloudService(token, host);
  }

  Future<Map<String, dynamic>> _call(String method, [Map<String, String> params = const {}]) async {
    final uri = Uri.https(host, '/$method', {...params, 'access_token': token});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      _check(j);
      return j;
    } on SocketException {
      throw const PCloudException('Sem conexão com a internet.');
    } on TimeoutException {
      throw const PCloudException('O pCloud demorou para responder.');
    } finally {
      client.close(force: true);
    }
  }

  static void _check(Map<String, dynamic> j) {
    final r = (j['result'] as num?)?.toInt() ?? 0;
    if (r == 0) return;
    if (r == 1000 || r == 2000 || r == 2094 || r == 2095) {
      throw const PCloudException('A conexão com o pCloud expirou. Conecte de novo.');
    }
    throw PCloudException('pCloud: ${j['error'] ?? 'erro $r'}');
  }

  /// Nome da conta (para mostrar "Conectado como …").
  Future<String> email() async => '${(await _call('userinfo'))['email'] ?? ''}';

  /// Envia um arquivo para a pasta do app.
  Future<void> upload(String name, Uint8List bytes) async {
    final uri = Uri.https(host, '/uploadfile', {
      'access_token': token,
      'folderid': '0',
      'filename': name,
      'nopartial': '1',
    });
    final boundary = 'pace${DateTime.now().microsecondsSinceEpoch}';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$name"\r\n'
        'Content-Type: application/zip\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      req.contentLength = head.length + bytes.length + tail.length;
      req.add(head);
      req.add(bytes);
      req.add(tail);
      final res = await req.close().timeout(const Duration(minutes: 3));
      final body = await res.transform(utf8.decoder).join();
      _check(jsonDecode(body) as Map<String, dynamic>);
    } on SocketException {
      throw const PCloudException('Sem conexão com a internet.');
    } on TimeoutException {
      throw const PCloudException('O envio para o pCloud demorou demais.');
    } finally {
      client.close(force: true);
    }
  }

  /// Backups do PACE na pasta do app, do mais novo para o mais antigo.
  Future<List<CloudBackup>> list() async {
    final j = await _call('listfolder', {'folderid': '0'});
    final contents = ((j['metadata'] as Map?)?['contents'] as List?) ?? const [];
    final out = <CloudBackup>[];
    for (final m in contents.cast<Map>()) {
      if (m['isfolder'] == true) continue;
      final name = '${m['name']}';
      if (!name.startsWith('pace_backup') || !name.endsWith('.zip')) continue;
      out.add(CloudBackup(
        (m['fileid'] as num).toInt(),
        name,
        (m['size'] as num?)?.toInt() ?? 0,
        HttpDate.parse('${m['created']}').toLocal(),
      ));
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  Future<Uint8List> download(int fileId) async {
    final j = await _call('getfilelink', {'fileid': '$fileId'});
    final hosts = (j['hosts'] as List).cast<String>();
    final uri = Uri.https(hosts.first, '${j['path']}');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(minutes: 3));
      final b = BytesBuilder(copy: false);
      await for (final c in res) {
        b.add(c);
      }
      return b.takeBytes();
    } on SocketException {
      throw const PCloudException('Sem conexão com a internet.');
    } finally {
      client.close(force: true);
    }
  }

  /// Mantém só os [keep] backups mais recentes.
  Future<void> prune({int keep = 10}) async {
    final all = await list();
    for (final b in all.skip(keep)) {
      await _call('deletefile', {'fileid': '${b.fileId}'});
    }
  }
}
