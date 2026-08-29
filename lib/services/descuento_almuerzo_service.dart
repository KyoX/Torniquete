import '../models/registro.dart';
import 'db_service.dart';
import 'reports_service.dart';

/// Un día ya guardado y cuánto cambiaría su total al recalcularlo con el
/// descuento de almuerzo vigente.
class CambioDescuento {
  final Registro registro;
  final int minutosAntes;
  final int minutosDespues;

  const CambioDescuento({
    required this.registro,
    required this.minutosAntes,
    required this.minutosDespues,
  });

  /// Negativa si el día pasa a contar menos horas, que es lo normal al
  /// empezar a descontar un almuerzo que antes no se descontaba.
  int get diferencia => minutosDespues - minutosAntes;
}

/// Lo que le pasaría al historial si se le aplicara el descuento vigente.
class RevisionDescuento {
  /// Descuento que se aplicaría, en minutos.
  final int descuento;

  /// Días cuya regla guardada no es la vigente, ya con la nueva puesta.
  final List<Registro> aSellar;

  /// Los de [aSellar] cuyo total de horas cambia de verdad. Es un subconjunto
  /// pequeño: un día en blanco, uno justificado o uno con un almuerzo más
  /// largo que el descuento cambian de regla sin cambiar de números.
  final List<CambioDescuento> cambios;

  const RevisionDescuento({
    required this.descuento,
    required this.aSellar,
    required this.cambios,
  });

  static const vacia =
      RevisionDescuento(descuento: 0, aSellar: [], cambios: []);

  bool get sinTrabajo => aSellar.isEmpty;

  /// Cuánto se movería el banco de horas en total.
  int get diferenciaMinutos =>
      cambios.fold(0, (total, cambio) => total + cambio.diferencia);
}

/// Aplica el descuento fijo de almuerzo a los días que ya están guardados.
///
/// Normalmente no hace falta: cada día se sella con la regla que estaba
/// vigente cuando se trabajó, igual que se sella con su meta, y cambiar el
/// ajuste no reescribe el pasado. Esto es para el caso contrario, el de quien
/// descubre el ajuste después de meses usando la app: su empresa llevaba
/// descontando el almuerzo todo ese tiempo y el banco de horas guardado está
/// de más. Es una decisión del usuario, no de la app, así que vive detrás de
/// un botón y de una confirmación que dice cuánto se va a mover.
class DescuentoAlmuerzoService {
  const DescuentoAlmuerzoService._();

  /// Qué días cambiarían y en cuánto, sin tocar nada todavía.
  ///
  /// [hoy] queda fuera a propósito: el día en curso ya sigue el ajuste
  /// vigente —se lo aplica el propio dashboard al cargarlo— y reescribirlo
  /// desde aquí chocaría con la copia que el provider tiene en memoria.
  static RevisionDescuento revisar(
    List<Registro> registros, {
    required int descuento,
    required String hoy,
  }) {
    final aSellar = <Registro>[];
    final cambios = <CambioDescuento>[];

    for (final registro in registros) {
      if (registro.fecha == hoy) continue;
      if (registro.descuentoAlmuerzoMinutos == descuento) continue;

      final actualizado =
          registro.copyWith(descuentoAlmuerzoMinutos: descuento);
      aSellar.add(actualizado);

      final antes = ReportsService.minutosTrabajados(registro);
      final despues = ReportsService.minutosTrabajados(actualizado);
      if (antes == despues) continue;
      cambios.add(CambioDescuento(
        registro: actualizado,
        minutosAntes: antes,
        minutosDespues: despues,
      ));
    }

    cambios.sort((a, b) => b.registro.fecha.compareTo(a.registro.fecha));
    return RevisionDescuento(
      descuento: descuento,
      aSellar: aSellar,
      cambios: cambios,
    );
  }

  /// Guarda la revisión. Devuelve cuántos días quedaron con la regla nueva.
  ///
  /// Se sella también el total recalculado: `minutosCumplidos` es el valor al
  /// que caen los días a los que les falta alguna marca, y dejarlo con el de
  /// la regla anterior haría que el mismo día dijera dos cosas distintas
  /// según por dónde se le mirara.
  static Future<int> aplicar(RevisionDescuento revision) async {
    for (final registro in revision.aSellar) {
      await DbService.instance.guardarRegistro(
        registro.copyWith(
          minutosCumplidos: ReportsService.minutosTrabajados(registro),
        ),
      );
    }
    return revision.aSellar.length;
  }
}
