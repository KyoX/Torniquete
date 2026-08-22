import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../utils/festivos_sv.dart';
import 'db_service.dart';
import 'reports_service.dart';

/// Un día ya guardado que resultó ser asueto de ley.
class CandidatoAsueto {
  final Registro registro;
  final Asueto asueto;

  const CandidatoAsueto({required this.registro, required this.asueto});
}

/// Revisa el historial ya guardado contra el calendario de asuetos.
///
/// Sirve para el usuario que instaló la app antes de que reconociera los
/// asuetos: sus festivos quedaron guardados como días normales en blanco y
/// el historial los muestra como "día sin horas registradas".
class AsuetosService {
  const AsuetosService._();

  /// Días del historial que son asueto y todavía figuran como día normal.
  ///
  /// Se dejan fuera a propósito los días en los que sí se trabajó. Marcar uno
  /// de esos como festivo convertiría toda su jornada en tiempo extra —que es
  /// lo que legalmente corresponde—, pero es un cambio grande para hacerlo en
  /// bloque y sin preguntar. Esos se marcan a mano desde el historial.
  static List<CandidatoAsueto> candidatos(
    List<Registro> registros,
    SectorLaboral sector,
  ) {
    final resultado = <CandidatoAsueto>[];
    for (final registro in registros) {
      if (registro.tipoDia != TipoDia.normal) continue;
      if (ReportsService.minutosTrabajados(registro) > 0) continue;
      final asueto = FestivosSV.enClave(registro.fecha, sector: sector);
      if (asueto == null) continue;
      resultado.add(CandidatoAsueto(registro: registro, asueto: asueto));
    }
    resultado.sort((a, b) => b.registro.fecha.compareTo(a.registro.fecha));
    return resultado;
  }

  /// Marca los [candidatos] como festivos, dejando el nombre del asueto como
  /// nota. Devuelve cuántos días se cambiaron.
  static Future<int> marcar(List<CandidatoAsueto> candidatos) async {
    for (final candidato in candidatos) {
      await DbService.instance.guardarRegistro(
        candidato.registro.copyWith(
          tipoDia: TipoDia.festivo,
          nota: candidato.asueto.nombre,
        ),
      );
    }
    return candidatos.length;
  }
}
