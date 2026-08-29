import '../models/pausa.dart';
import '../utils/time_utils.dart';

/// Las reglas de las pausas del día: cuánto suman y cuál de ellas es el
/// almuerzo.
///
/// Todo son funciones puras sobre la lista de pausas, sin base de datos ni
/// widgets de por medio: son las reglas que deciden las horas de una jornada
/// y tienen que poder comprobarse una a una.
class PausasService {
  const PausasService._();

  /// Ventana horaria en la que una pausa cuenta como almuerzo, en minutos
  /// desde medianoche: de 11:30 a 14:00.
  ///
  /// Hace falta porque el descuento fijo de almuerzo es *un almuerzo*, no
  /// cualquier rato fuera: si una diligencia de media hora a las nueve de la
  /// mañana lo diera por cumplido, la app adelantaría la hora de salida
  /// media hora que la empresa va a descontar igual.
  static const int inicioAlmuerzo = 11 * 60 + 30;
  static const int finAlmuerzo = 14 * 60;

  /// La pausa en curso, si hay alguna. Solo puede haber una: no se puede
  /// dejar de trabajar dos veces sin volver en medio.
  static Pausa? abierta(List<Pausa> pausas) {
    for (final pausa in pausas) {
      if (pausa.abierta) return pausa;
    }
    return null;
  }

  /// Minutos fuera del trabajo, cerrando la pausa en curso a [hasta].
  static int minutosPausados(List<Pausa> pausas, {int? hasta}) =>
      pausas.fold(0, (total, pausa) => total + pausa.duracion(hasta: hasta));

  /// De esos minutos, los que caen dentro de la ventana de almuerzo. Es lo
  /// que cuenta contra el descuento fijo que hace la empresa.
  static int minutosDeAlmuerzo(List<Pausa> pausas, {int? hasta}) =>
      pausas.fold(0, (total, pausa) => total + solape(pausa, hasta: hasta));

  /// Minutos de [pausa] que caen dentro de la ventana de almuerzo.
  ///
  /// Se cuenta el solape y no la pausa entera a propósito: quien sale a la
  /// una y media y vuelve a las tres almorzó media hora y estuvo otra hora
  /// fuera por lo que fuera.
  static int solape(Pausa pausa, {int? hasta}) {
    final inicio = pausa.inicioMinutos;
    if (inicio == null) return 0;
    final fin = pausa.finMinutos ?? hasta;
    if (fin == null) return 0;
    final desde = inicio > inicioAlmuerzo ? inicio : inicioAlmuerzo;
    final cierre = fin < finAlmuerzo ? fin : finAlmuerzo;
    final minutos = cierre - desde;
    return minutos > 0 ? minutos : 0;
  }

  /// Las pausas del día en una línea, para el historial y el widget: el
  /// tramo si solo hubo una, y cuántas fueron con su total si hubo varias.
  static String resumen(List<Pausa> pausas, {int? hasta}) {
    if (pausas.isEmpty) return '--:--';
    if (pausas.length == 1) {
      final pausa = pausas.first;
      return '${pausa.inicio}–${pausa.fin ?? '...'}';
    }
    final total = minutosPausados(pausas, hasta: hasta);
    return '${pausas.length} pausas '
        '(${TimeUtils.formatDurationMinutes(total)})';
  }

  /// Cuál de las pausas hace de almuerzo: la que más minutos mete en la
  /// ventana, y a igualdad la primera del día. Null si ninguna la toca.
  ///
  /// Una pausa en curso se mide como si llegara hasta el final de la
  /// ventana; si no, salir a comer a las doce dejaría al día sin almuerzo
  /// identificado justo mientras se está almorzando.
  static Pausa? pausaDeAlmuerzo(List<Pausa> pausas) {
    Pausa? mejor;
    var mayor = 0;
    for (final pausa in Pausa.ordenar(pausas)) {
      final minutos = solape(pausa, hasta: finAlmuerzo);
      if (minutos > mayor) {
        mayor = minutos;
        mejor = pausa;
      }
    }
    return mejor;
  }
}
