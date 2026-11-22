import 'package:flutter_test/flutter_test.dart';
import 'package:pace/ui/widgets/sky_scene.dart';

void main() {
  test('nascer e pôr do sol em Guaratinguetá (22/11)', () {
    final s = SunTimes.of(DateTime(2026, 11, 22, 12), -22.81, -45.19);
    // Referência: nascer ~05:13 e pôr ~18:28 (UTC-3).
    expect(s.sunrise.toUtc().difference(DateTime.utc(2026, 11, 22, 8, 13)).inMinutes.abs(), lessThan(8));
    expect(s.sunset.toUtc().difference(DateTime.utc(2026, 11, 22, 21, 28)).inMinutes.abs(), lessThan(8));
  });

  test('momentos seguem o sol', () {
    final s = SunTimes.of(DateTime(2026, 6, 21, 12), -22.81, -45.19);
    SkyMoment at(DateTime t) => SkyInfo.at(t).moment;
    expect(at(s.sunrise.subtract(const Duration(minutes: 30))), SkyMoment.aurora);
    expect(at(s.sunrise.add(const Duration(minutes: 20))), SkyMoment.sunrise);
    expect(at(s.sunrise.add(const Duration(hours: 4))), SkyMoment.day);
    expect(at(s.sunset.subtract(const Duration(minutes: 30))), SkyMoment.sunset);
    expect(at(s.sunset.add(const Duration(minutes: 20))), SkyMoment.dusk);
    expect(at(s.sunset.add(const Duration(hours: 3))), SkyMoment.night);
  });

  test('texto claro à noite e escuro de dia', () {
    final s = SunTimes.of(DateTime(2026, 11, 22, 12), -22.81, -45.19);
    expect(SkyInfo.at(s.sunset.add(const Duration(hours: 3))).onSky.computeLuminance(), greaterThan(0.9));
    expect(SkyInfo.at(s.sunrise.add(const Duration(hours: 4))).onSky.computeLuminance(), lessThan(0.1));
  });
}
