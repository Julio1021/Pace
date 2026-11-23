import 'models.dart';

/// Um recorde do pedal (calculado pelos totais de cada treino).
class BikeRecord {
  final String label;
  final String hint;
  final Activity? activity;
  final double value;
  const BikeRecord(this.label, this.hint, this.activity, this.value);
}

/// Recordes do pedal: maior distância, maior duração, melhor média em
/// pedais de pelo menos 20 e 40 km e maior subida.
class BikeRecords {
  static List<BikeRecord> compute(List<Activity> rides) {
    Activity? best(Iterable<Activity> l, double Function(Activity) v) {
      Activity? out;
      for (final a in l) {
        if (out == null || v(a) > v(out)) out = a;
      }
      return out;
    }

    double speed(Activity a) => a.kmh ?? 0;
    final done = rides.where((a) => a.distanceM > 0 && a.movingSec > 0).toList();
    final longest = best(done, (a) => a.distanceM);
    final longestT = best(done, (a) => a.movingSec.toDouble());
    final fast20 = best(done.where((a) => a.distanceM >= 20000), speed);
    final fast40 = best(done.where((a) => a.distanceM >= 40000), speed);
    final climb = best(done.where((a) => a.elevGain >= 1), (a) => a.elevGain);
    return [
      BikeRecord('Maior distância', 'km', longest, longest?.distanceM ?? 0),
      BikeRecord('Maior duração', 'tempo', longestT, (longestT?.movingSec ?? 0).toDouble()),
      BikeRecord('Melhor média (20 km ou mais)', 'km/h', fast20, fast20 == null ? 0 : speed(fast20)),
      BikeRecord('Melhor média (40 km ou mais)', 'km/h', fast40, fast40 == null ? 0 : speed(fast40)),
      BikeRecord('Maior subida', 'm', climb, climb?.elevGain ?? 0),
    ];
  }
}
