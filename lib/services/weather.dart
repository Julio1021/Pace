import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Tipos de tempo que mudam o céu da tela Correr.
enum WeatherKind { clear, partly, cloudy, fog, drizzle, rain, storm, snow }

/// Condição atual e o que vem nas próximas horas (Open-Meteo, sem cadastro).
class WeatherNow {
  final WeatherKind kind;
  final double tempC;
  final double windKmh;
  final DateTime fetchedAt;

  /// Hora local em que deve começar a chover (nas próximas 6 h), se houver.
  final DateTime? rainAt;

  const WeatherNow({required this.kind, required this.tempC, required this.windKmh, required this.fetchedAt, this.rainAt});

  bool get windy => windKmh >= 28;
  bool get hot => tempC >= 31;
  bool get cold => tempC <= 10;
  bool get wet => kind == WeatherKind.drizzle || kind == WeatherKind.rain || kind == WeatherKind.storm;

  static WeatherKind kindOf(int code) => switch (code) {
        0 || 1 => WeatherKind.clear,
        2 => WeatherKind.partly,
        3 => WeatherKind.cloudy,
        45 || 48 => WeatherKind.fog,
        >= 51 && <= 57 => WeatherKind.drizzle,
        >= 61 && <= 67 || >= 80 && <= 82 => WeatherKind.rain,
        >= 71 && <= 77 || 85 || 86 => WeatherKind.snow,
        >= 95 => WeatherKind.storm,
        _ => WeatherKind.partly,
      };

  String get label => switch (kind) {
        WeatherKind.clear => hot ? 'Muito calor' : 'Céu limpo',
        WeatherKind.partly => 'Poucas nuvens',
        WeatherKind.cloudy => 'Nublado',
        WeatherKind.fog => 'Neblina',
        WeatherKind.drizzle => 'Garoa',
        WeatherKind.rain => 'Chuva',
        WeatherKind.storm => 'Tempestade',
        WeatherKind.snow => 'Frio intenso',
      };

  /// Frase para a tela Correr (null = usar a frase do horário).
  String? get phrase {
    switch (kind) {
      case WeatherKind.storm:
        return 'Tempestade: melhor esperar passar';
      case WeatherKind.rain:
        return 'Chuva agora: cuidado com o piso';
      case WeatherKind.drizzle:
        return 'Garoa fina: um boné ajuda';
      case WeatherKind.fog:
        return 'Neblina: use roupa clara';
      default:
        break;
    }
    if (hot) return 'Calor forte: leve água';
    if (windy) return 'Vento forte: comece contra ele';
    final r = rainAt;
    if (r != null) return 'Chuva prevista às ${r.hour}h. Bora antes?';
    if (cold) return 'Friozinho: aqueça bem antes';
    if (kind == WeatherKind.cloudy) return 'Céu fechado, ótimo para correr';
    return null;
  }

  Map<String, Object?> toJson() => {
        'k': kind.index,
        't': tempC,
        'w': windKmh,
        'f': fetchedAt.millisecondsSinceEpoch,
        'r': rainAt?.millisecondsSinceEpoch,
      };

  static WeatherNow? fromJson(Map<String, dynamic> j) {
    try {
      return WeatherNow(
        kind: WeatherKind.values[(j['k'] as num).toInt()],
        tempC: (j['t'] as num).toDouble(),
        windKmh: (j['w'] as num).toDouble(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch((j['f'] as num).toInt()),
        rainAt: j['r'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['r'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  /// Lê a resposta do Open-Meteo.
  static WeatherNow? parse(Map<String, dynamic> j, DateTime now) {
    try {
      final cur = j['current'] as Map<String, dynamic>;
      final code = (cur['weather_code'] as num).toInt();
      DateTime? rainAt;
      final h = j['hourly'] as Map<String, dynamic>?;
      if (h != null) {
        final times = (h['time'] as List).cast<String>();
        final prob = (h['precipitation_probability'] as List?) ?? const [];
        final codes = (h['weather_code'] as List?) ?? const [];
        for (var i = 0; i < times.length; i++) {
          final t = DateTime.tryParse(times[i]);
          if (t == null || !t.isAfter(now) || t.difference(now).inHours > 6) continue;
          final p = i < prob.length ? (prob[i] as num?)?.toInt() ?? 0 : 0;
          final c = i < codes.length ? (codes[i] as num?)?.toInt() ?? 0 : 0;
          if (p >= 60 && kindOf(c).index >= WeatherKind.drizzle.index) {
            rainAt = t;
            break;
          }
        }
      }
      return WeatherNow(
        kind: kindOf(code),
        tempC: (cur['temperature_2m'] as num).toDouble(),
        windKmh: (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        fetchedAt: now,
        rainAt: rainAt,
      );
    } catch (_) {
      return null;
    }
  }
}

class WeatherService {
  /// Busca a condição atual. Sem internet ou com erro, devolve null (o céu fica só pelo horário).
  static Future<WeatherNow?> fetch(double lat, double lon) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      // Localização arredondada (~1 km): o suficiente para o clima.
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(2),
        'longitude': lon.toStringAsFixed(2),
        'current': 'temperature_2m,weather_code,wind_speed_10m',
        'hourly': 'precipitation_probability,weather_code',
        'forecast_hours': '7',
        'timezone': 'auto',
      });
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      return WeatherNow.parse(jsonDecode(body) as Map<String, dynamic>, DateTime.now());
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
