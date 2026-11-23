import 'package:intl/intl.dart';

/// Formatação padrão do app: pt-BR, sistema métrico, 24 h.
class Fmt {
  static final _d0 = NumberFormat('#,##0', 'pt_BR');
  static final _d1 = NumberFormat('#,##0.0', 'pt_BR');
  static final _d2 = NumberFormat('#,##0.00', 'pt_BR');
  static final _int = NumberFormat.decimalPattern('pt_BR');

  /// Distância em km com duas casas: "13,03".
  static String km(double meters, {int decimals = 2}) {
    final v = meters / 1000;
    return switch (decimals) { 0 => _d0.format(v), 1 => _d1.format(v), _ => _d2.format(v) };
  }

  static String kmUnit(double meters, {int decimals = 2}) => '${km(meters, decimals: decimals)} km';

  static String integer(num v) => _int.format(v.round());

  /// Duração "1:03:51" ou "54:12".
  static String duration(num seconds) {
    final s = seconds.round();
    if (s < 0) return '0:00';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  /// Duração longa para totais: "12 h 05 min".
  static String durationLong(num seconds) {
    final s = seconds.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h == 0) return '$m min';
    return '$h h ${m.toString().padLeft(2, '0')} min';
  }

  /// Pace m:ss, arredondado ao segundo mais próximo. "—" quando não há dado.
  static String pace(double? secPerKm) {
    if (secPerKm == null || !secPerKm.isFinite || secPerKm <= 0 || secPerKm > 3600) return '—';
    final total = secPerKm.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String paceUnit(double? secPerKm) {
    final p = pace(secPerKm);
    return p == '—' ? p : '$p /km';
  }

  /// Velocidade em km/h com uma casa.
  static String speed(double? mps) {
    if (mps == null || !mps.isFinite || mps <= 0) return '—';
    return _d1.format(mps * 3.6);
  }

  static String date(DateTime utc) => DateFormat('dd/MM/yyyy').format(utc.toLocal());
  static String time(DateTime utc) => DateFormat('HH:mm').format(utc.toLocal());
  static String dateTime(DateTime utc) => DateFormat("dd/MM/yyyy 'às' HH:mm").format(utc.toLocal());
  static String weekdayDate(DateTime utc) => _cap(DateFormat("EEEE, d 'de' MMMM").format(utc.toLocal()));
  static String monthYear(DateTime local) => _cap(DateFormat('MMMM yyyy').format(local));
  static String monthShort(DateTime local) => _cap(DateFormat('MMM').format(local)).replaceAll('.', '');
  static String dayMonth(DateTime local) => DateFormat('dd/MM').format(local);
  static String weekdayShort(DateTime local) => _cap(DateFormat('E').format(local)).replaceAll('.', '');

  static String percent(double ratio) {
    final v = (ratio * 100).round();
    return '$v%';
  }

  static String signedPercent(double ratio) {
    final v = (ratio * 100).round();
    return v > 0 ? '+$v%' : '$v%';
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
