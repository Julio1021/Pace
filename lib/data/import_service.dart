import 'database.dart';
import 'importers.dart';

class ImportReport {
  int imported = 0;
  int duplicates = 0;
  final errors = <({String file, String reason})>[];

  int get total => imported + duplicates + errors.length;
}

/// Importa vários arquivos .tcx/.gpx (ou .zip com eles) sem duplicar corridas.
class ImportService {
  static Future<ImportReport> run(
    PaceDatabase db,
    List<ImportItem> files, {
    double weightKg = 70,
    void Function(int done, int total)? onProgress,
  }) async {
    final report = ImportReport();
    final items = expandImportFiles(files);
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      try {
        if (it.bytes.isEmpty) throw ImportException('Arquivo vazio ou .zip inválido');
        final b = ActivityParser.parse(it.name, it.bytes, weightKg: weightKg);
        final dup = await db.findDuplicate(b.activity.start, b.activity.distanceM);
        if (dup != null) {
          report.duplicates++;
        } else {
          await db.insertBundle(b);
          report.imported++;
        }
      } catch (e) {
        report.errors.add((file: it.name, reason: e is ImportException ? e.message : 'Erro ao ler: $e'));
      }
      onProgress?.call(i + 1, items.length);
      // Deixa a interface respirar durante importações grandes.
      if (i % 5 == 4) await Future<void>.delayed(Duration.zero);
    }
    return report;
  }
}
