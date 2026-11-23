import 'package:flutter_test/flutter_test.dart';
import 'package:pace/services/weather.dart';

void main() {
  test('códigos do tempo viram o tipo certo', () {
    expect(WeatherNow.kindOf(0), WeatherKind.clear);
    expect(WeatherNow.kindOf(3), WeatherKind.cloudy);
    expect(WeatherNow.kindOf(45), WeatherKind.fog);
    expect(WeatherNow.kindOf(53), WeatherKind.drizzle);
    expect(WeatherNow.kindOf(63), WeatherKind.rain);
    expect(WeatherNow.kindOf(81), WeatherKind.rain);
    expect(WeatherNow.kindOf(95), WeatherKind.storm);
  });

  test('lê a resposta e acha a chuva das próximas horas', () {
    final now = DateTime(2026, 11, 23, 10, 30);
    final w = WeatherNow.parse({
      'current': {'temperature_2m': 24.6, 'weather_code': 2, 'wind_speed_10m': 12.0},
      'hourly': {
        'time': ['2026-11-23T10:00', '2026-11-23T11:00', '2026-11-23T14:00', '2026-11-23T15:00'],
        'precipitation_probability': [10, 20, 75, 80],
        'weather_code': [2, 2, 61, 63],
      },
    }, now)!;
    expect(w.kind, WeatherKind.partly);
    expect(w.tempC, 24.6);
    expect(w.rainAt, DateTime(2026, 11, 23, 14));
    expect(w.phrase, contains('14h'));
  });

  test('frases por condição', () {
    WeatherNow mk(WeatherKind k, {double t = 22, double wind = 5}) =>
        WeatherNow(kind: k, tempC: t, windKmh: wind, fetchedAt: DateTime(2026));
    expect(mk(WeatherKind.storm).phrase, contains('Tempestade'));
    expect(mk(WeatherKind.clear, t: 33).phrase, contains('água'));
    expect(mk(WeatherKind.clear, wind: 35).phrase, contains('Vento'));
    expect(mk(WeatherKind.clear).phrase, isNull);
  });
}
