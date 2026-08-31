import 'package:flutter/foundation.dart';

import '../models/registro.dart';
import '../utils/time_utils.dart';
import 'reports_service.dart';

/// Una jornada de un día anterior que se quedó sin salida confirmada.
@immutable
class JornadaAbierta {
  final Registro registro;

  /// Minuto del día que se propone como hora de salida.
  final int minutoSugerido;

  /// True si la propuesta sale de una pausa que quedó sin cerrar, y no de la
  /// hora estimada de salida. Cambia lo que se le dice al usuario: en un caso
  /// se le propone la hora en la que dejó de contar, en el otro la hora a la
  /// que le tocaba salir.
  final bool desdePausa;

  const JornadaAbierta({
    required this.registro,
    required this.minutoSugerido,
    required this.desdePausa,
  });

  String get fecha => registro.fecha;

  /// La propuesta en "HH:mm", lista para escribirla en el registro.
  String get horaSugerida =>
      TimeUtils.formatTimeOfDay(TimeUtils.fromMinutes(minutoSugerido));

  /// Cuántos minutos de trabajo devuelve al banco cerrar el día con la hora
  /// propuesta.
  ///
  /// Es la razón de ser de todo esto, así que se dice: mientras el día siga
  /// abierto cuenta lo último que se alcanzó a guardar, casi siempre la
  /// última marca, y todo lo trabajado después está perdido.
  int get minutosRecuperados =>
      ReportsService.minutosTrabajados(
        registro.copyWith(salidaReal: horaSugerida),
      ) -
      ReportsService.minutosTrabajados(registro);
}

/// Encuentra los días que se quedaron con la entrada marcada y sin salida.
///
/// Es el agujero más caro de la app: sin salida real no hay jornada que
/// medir, así que [ReportsService.minutosTrabajados] cae al último valor que
/// se alcanzó a guardar —normalmente el de la última marca del día— y las
/// horas que se trabajaron después de esa marca desaparecen del banco. Quien
/// olvidó confirmar la salida un martes ve un déficit de horas que sí hizo.
///
/// Todo es puro a propósito: es aritmética sobre lo que ya está guardado, y
/// se prueba sin Android de por medio.
class JornadasAbiertasService {
  const JornadasAbiertasService._();

  /// El último minuto del día, que es hasta donde puede llegar una salida.
  static const int finDelDia = 24 * 60 - 1;

  /// Los días anteriores a [hoy] que quedaron abiertos, del más reciente al
  /// más antiguo.
  ///
  /// El día en curso no entra: todavía se está trabajando y el dashboard ya
  /// tiene su botón de confirmar salida. Tampoco entran los días sin entrada,
  /// que no son una jornada a medias sino un día en blanco.
  static List<JornadaAbierta> detectar(
    List<Registro> registros, {
    required String hoy,
  }) {
    final abiertas = <JornadaAbierta>[];
    for (final registro in registros) {
      if (!estaAbierta(registro, hoy: hoy)) continue;
      final (minuto, desdePausa) = _sugerir(registro);
      abiertas.add(JornadaAbierta(
        registro: registro,
        minutoSugerido: minuto,
        desdePausa: desdePausa,
      ));
    }
    abiertas.sort((a, b) => b.fecha.compareTo(a.fecha));
    return abiertas;
  }

  /// True si [registro] es una jornada pasada sin cerrar.
  ///
  /// Los días justificados también cuentan: si hay entrada es que se trabajó
  /// el festivo, y esas horas son tiempo extra que se pierde igual.
  static bool estaAbierta(Registro registro, {required String hoy}) {
    // Las fechas son "yyyy-MM-dd", así que comparar el texto es comparar el
    // día sin pasar por DateTime.
    if (registro.fecha.compareTo(hoy) >= 0) return false;
    if (TimeUtils.parseTimeOfDay(registro.entrada1) == null) return false;
    return TimeUtils.parseTimeOfDay(registro.salidaReal) == null;
  }

  /// La hora que se propone para cerrar el día, y de dónde sale.
  static (int, bool) _sugerir(Registro registro) {
    // Quien se fue de pausa y no volvió dejó de contar ahí: es hasta ese
    // punto donde se sabe que estuvo trabajando, y es la lectura que ya hace
    // el resto de la app para un día con la pausa abierta.
    final pausa = TimeUtils.parseTimeOfDay(registro.pausaAbierta?.inicio);
    if (pausa != null) return (TimeUtils.toMinutes(pausa), true);

    final estimado = ReportsService.minutoEstimadoSalida(
      registro,
      minutosAhora: finDelDia,
      // Un día justificado no exige meta, pero si tiene entrada es que se
      // trabajó, y una jornada trabajada dura lo que dura. Sin esto la
      // propuesta sería la propia hora de entrada.
      metaMinutos: registro.tipoDia.exigeMeta ? null : registro.metaMinutos,
    );
    return ((estimado ?? finDelDia).clamp(0, finDelDia), false);
  }
}
