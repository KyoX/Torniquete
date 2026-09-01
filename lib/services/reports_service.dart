import '../models/movimiento_banco.dart';
import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../providers/app_provider.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import 'pausas_service.dart';

class DailyStat {
  final Registro registro;
  final int minutosTrabajados;

  DailyStat({required this.registro, required this.minutosTrabajados});

  TipoDia get tipoDia => registro.tipoDia;

  /// Festivo, vacaciones, incapacidad o permiso: la ausencia está justificada
  /// y el día no exige meta.
  bool get justificado => registro.tipoDia.esJustificado;

  /// Día laboral sin horas registradas: no cuenta ni a favor ni en contra.
  /// Un día justificado nunca es "sin registro": no falta nada por marcar.
  bool get sinRegistro => !justificado && minutosTrabajados <= 0;

  bool get cumplida =>
      justificado || (!sinRegistro && minutosTrabajados >= registro.metaMinutos);

  /// Diferencia contra la meta. Los días sin horas registradas no restan y en
  /// los días justificados todo lo trabajado es tiempo extra.
  int get diferenciaMinutos {
    if (justificado) return minutosTrabajados;
    return sinRegistro ? 0 : minutosTrabajados - registro.metaMinutos;
  }
}

class WeeklyStat {
  final String semanaInicio; // "2026-08-11" (lunes de la semana)
  final int totalTrabajado;
  final int totalMeta;
  final int diasCumplidos;
  final int totalDias; // días con horas registradas
  final int diasSinRegistro;

  /// Festivos, vacaciones, incapacidades y permisos de la semana.
  final int diasJustificados;

  WeeklyStat({
    required this.semanaInicio,
    required this.totalTrabajado,
    required this.totalMeta,
    required this.diasCumplidos,
    required this.totalDias,
    this.diasSinRegistro = 0,
    this.diasJustificados = 0,
  });

  double get porcentaje =>
      totalMeta == 0 ? 0 : (totalTrabajado / totalMeta * 100);

  String get nombreSemana {
    final inicio = DateTime.parse(semanaInicio);
    final fin = inicio.add(const Duration(days: 6));
    const nombresMes = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul',
      'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    final inicioTexto = '${inicio.day} ${nombresMes[inicio.month - 1]}';
    final finTexto = '${fin.day} ${nombresMes[fin.month - 1]} ${fin.year}';
    return '$inicioTexto - $finTexto';
  }
}

class MonthlyStat {
  final String yearMonth; // "2026-08"
  final int totalTrabajado;
  final int totalMeta;
  final int diasCumplidos;
  final int totalDias; // días con horas registradas
  final int diasSinRegistro;

  /// Festivos, vacaciones, incapacidades y permisos del mes.
  final int diasJustificados;

  MonthlyStat({
    required this.yearMonth,
    required this.totalTrabajado,
    required this.totalMeta,
    required this.diasCumplidos,
    required this.totalDias,
    this.diasSinRegistro = 0,
    this.diasJustificados = 0,
  });

  double get porcentaje =>
      totalMeta == 0 ? 0 : (totalTrabajado / totalMeta * 100);

  String get nombreMes {
    final partes = yearMonth.split('-');
    final mes = int.parse(partes[1]);
    const nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
      'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return '${nombres[mes - 1]} ${partes[0]}';
  }
}

class ProjectionStat {
  final int metaMesMinutos;
  final int trabajadoHastaHoyMinutos;
  final int semanaActual;
  final int totalSemanasMes;
  final int proyeccionTotalMinutos;

  ProjectionStat({
    required this.metaMesMinutos,
    required this.trabajadoHastaHoyMinutos,
    required this.semanaActual,
    required this.totalSemanasMes,
    required this.proyeccionTotalMinutos,
  });

  int get diferenciaMinutos => proyeccionTotalMinutos - metaMesMinutos;
  bool get vaACumplir => diferenciaMinutos >= 0;
}

class BalanceDay {
  final String fecha;
  final int diferenciaMinutos;
  final int balanceAcumuladoMinutos;
  final bool sinRegistro;
  final TipoDia tipoDia;

  BalanceDay({
    required this.fecha,
    required this.diferenciaMinutos,
    required this.balanceAcumuladoMinutos,
    this.sinRegistro = false,
    this.tipoDia = TipoDia.normal,
  });

  bool get justificado => tipoDia.esJustificado;
}

/// Foto del banco de horas lista para actuar: cuánto se debe o se tiene a
/// favor, de dónde sale ese saldo y a cuántos días de trabajo equivale.
class EstadoBanco {
  /// Aportado por los días registrados (extras menos déficits).
  final int minutosDeDias;

  /// Ajustes y canjes anotados a mano.
  final int minutosDeMovimientos;

  /// Meta de un día laboral típico; sirve para traducir el saldo a días.
  final int metaDiariaMinutos;

  const EstadoBanco({
    required this.minutosDeDias,
    required this.minutosDeMovimientos,
    required this.metaDiariaMinutos,
  });

  int get saldoMinutos => minutosDeDias + minutosDeMovimientos;

  bool get aFavor => saldoMinutos >= 0;

  /// Minutos que faltan por reponer. 0 si el saldo está a favor.
  int get deficitMinutos => saldoMinutos < 0 ? -saldoMinutos : 0;

  /// A cuántos días completos de trabajo equivale el saldo. Con meta 0 no
  /// hay conversión posible y se devuelve 0.
  double get diasEquivalentes =>
      metaDiariaMinutos > 0 ? saldoMinutos / metaDiariaMinutos : 0;
}

/// Cuánto hay que trabajar de más cada día para dejar el banco en cero
/// dentro de un plazo, o cuánto se puede gastar si el saldo está a favor.
class PlanBanco {
  /// Días laborales de plazo elegidos por el usuario.
  final int diasHabiles;

  /// Último día laboral del plazo.
  final DateTime fechaLimite;

  /// Minutos extra por día para saldar el déficit. 0 si no hay déficit.
  final int minutosExtraPorDia;

  /// Minutos disponibles para gastar. 0 si el saldo está en rojo.
  final int minutosDisponibles;

  const PlanBanco({
    required this.diasHabiles,
    required this.fechaLimite,
    required this.minutosExtraPorDia,
    required this.minutosDisponibles,
  });

  bool get hayDeficit => minutosExtraPorDia > 0;
}

/// Totales de un periodo concreto: es lo que hay que poner delante cuando
/// toca comprobar que el horario se cumplió. Los días laborales en blanco no
/// suman meta (igual que en el resto de la app) y los justificados se
/// cuentan aparte.
class ResumenPeriodo {
  final int totalTrabajado;
  final int totalMeta;

  /// Días con horas registradas.
  final int diasConHoras;

  final int diasCumplidos;

  /// Días con horas registradas que no llegaron a su meta.
  final int diasIncumplidos;

  /// Días laborales sin ninguna marca.
  final int diasSinRegistro;

  /// Festivos, vacaciones, incapacidades y permisos del periodo.
  final int diasJustificados;

  /// Ajustes y canjes anotados a mano dentro del periodo.
  final int minutosMovimientos;

  const ResumenPeriodo({
    required this.totalTrabajado,
    required this.totalMeta,
    required this.diasConHoras,
    required this.diasCumplidos,
    required this.diasIncumplidos,
    required this.diasSinRegistro,
    required this.diasJustificados,
    required this.minutosMovimientos,
  });

  /// Sin meta que cumplir el porcentaje no significa nada: se devuelve 0
  /// en vez de inventar un 100%.
  double get porcentaje =>
      totalMeta == 0 ? 0 : (totalTrabajado / totalMeta * 100);

  int get diferenciaMinutos => totalTrabajado - totalMeta;

  /// Lo que el periodo deja en el banco de horas, ya con los movimientos
  /// anotados a mano.
  int get saldoMinutos => diferenciaMinutos + minutosMovimientos;

  bool get metaCumplida => diferenciaMinutos >= 0;
}

/// Patrones que solo se ven mirando el historial completo, no un día, una
/// semana o un mes por separado.
class EstadisticasPersonales {
  /// Minuto del día promedio de entrada. Null sin ningún día con entrada.
  final int? minutosEntradaPromedio;

  /// Minuto del día promedio de salida real. Null sin ningún día cerrado.
  final int? minutosSalidaPromedio;

  /// Día de la semana (1=lunes … 7=domingo) con más minutos trabajados en
  /// promedio. Null sin días con horas registradas.
  final int? diaMasProductivo;

  /// Minutos promedio trabajados en [diaMasProductivo].
  final int minutosDiaMasProductivo;

  /// Días laborales consecutivos, contando desde el más reciente hacia
  /// atrás, que cumplieron su meta.
  final int rachaActual;

  /// La racha más larga de cumplimiento de todo el historial.
  final int mejorRacha;

  /// Días con horas registradas en todo el historial: el tamaño de la
  /// muestra sobre la que se calculó todo lo demás.
  final int diasConHoras;

  const EstadisticasPersonales({
    this.minutosEntradaPromedio,
    this.minutosSalidaPromedio,
    this.diaMasProductivo,
    this.minutosDiaMasProductivo = 0,
    this.rachaActual = 0,
    this.mejorRacha = 0,
    this.diasConHoras = 0,
  });
}

/// Funciones puras de agregación para las pantallas de reportes.
/// No dependen de widgets ni de la base de datos directamente: reciben
/// la lista de registros ya cargada.
class ReportsService {
  /// Minutos de almuerzo que hay que descontar aunque no se hayan tomado.
  ///
  /// Hay empresas que descuentan un almuerzo fijo se salga o no a comer. Ese
  /// descuento es un *mínimo*: si se almorzó más de la cuenta ya se descuenta
  /// solo —el tramo de pausa nunca contó como trabajado— y aquí no queda nada
  /// pendiente. Si se almorzó menos, o no se salió, esta función devuelve lo
  /// que falta para completarlo.
  ///
  /// Solo cuentan los minutos de pausa que caen en la ventana de almuerzo
  /// ([PausasService.inicioAlmuerzo]-[PausasService.finAlmuerzo]): una
  /// diligencia a media mañana es tiempo fuera, pero no es el almuerzo que
  /// la empresa va a descontar igual.
  ///
  /// [minutosAhora] es el minuto del día hasta el que se cuenta una pausa
  /// todavía abierta. Con él, el almuerzo en curso se va acreditando minuto a
  /// minuto; sin él, al empezar la pausa se restaría el descuento entero de
  /// golpe para devolverlo al volver, y el progreso del día pegaría un salto
  /// en cada marca.
  static int descuentoPendiente(Registro r, {int? minutosAhora}) {
    if (r.descuentoAlmuerzoMinutos <= 0) return 0;
    // Un día sin entrada no ha empezado: no hay jornada de la que descontar.
    if (TimeUtils.parseTimeOfDay(r.entrada1) == null) return 0;

    final tomado = PausasService.minutosDeAlmuerzo(
      r.pausas,
      hasta: minutosAhora ?? _minutos(r.salidaReal),
    );
    final pendiente = r.descuentoAlmuerzoMinutos - tomado;
    return pendiente > 0 ? pendiente : 0;
  }

  /// El minuto del día en que toca salir: la entrada, más la meta del día,
  /// más todo lo que se ha estado de pausa, más el almuerzo que la empresa
  /// descuenta y todavía no se ha tomado. Cada pausa empuja la salida hacia
  /// adelante justo lo que duró.
  ///
  /// Es la única definición de la hora estimada de salida: la usan el banner
  /// del dashboard, el recordatorio de salida, la pregunta al salir de la
  /// sede y la propuesta para cerrar un día que quedó abierto.
  ///
  /// [minutosAhora] es hasta dónde se cuenta una pausa todavía abierta, así
  /// que mientras se está fuera la hora se va corriendo minuto a minuto: es
  /// una estimación de "si vuelves ya y no paras más".
  ///
  /// [metaMinutos] permite pedir la estimación con otra meta que la del día.
  /// Sirve para los días justificados, que no exigen horas pero sí se pueden
  /// haber trabajado.
  ///
  /// Null si el día no tiene entrada: sin ella no hay nada desde donde
  /// contar.
  static int? minutoEstimadoSalida(
    Registro r, {
    required int minutosAhora,
    int? metaMinutos,
  }) {
    final entrada = _minutos(r.entrada1);
    if (entrada == null) return null;
    return entrada +
        (metaMinutos ?? r.metaEfectivaMinutos) +
        PausasService.minutosPausados(r.pausas, hasta: minutosAhora) +
        descuentoPendiente(r, minutosAhora: minutosAhora);
  }

  /// Nunca menos de cero: un descuento mayor que lo trabajado no puede
  /// convertir el día en horas negativas.
  static int _sinNegativos(int minutos) => minutos < 0 ? 0 : minutos;

  static int? _minutos(String? hora) {
    final t = TimeUtils.parseTimeOfDay(hora);
    return t == null ? null : TimeUtils.toMinutes(t);
  }

  /// El cálculo de un día, y el único: desde la entrada hasta [cierre], menos
  /// lo que se estuvo de pausa, menos el almuerzo que la empresa descuenta y
  /// no se llegó a tomar.
  ///
  /// Una pausa abierta se cierra siempre en [cierre]. Quien se fue y no
  /// volvió no estuvo trabajando mientras tanto, tanto si el día sigue
  /// corriendo como si se cerró después sin marcar el regreso.
  ///
  /// Null cuando falta la entrada o el cierre: no hay día que medir, y
  /// devolver cero se confundiría con un día de cero horas.
  static int? _jornada(Registro r, {required int? cierre}) {
    final entrada = _minutos(r.entrada1);
    if (entrada == null || cierre == null) return null;
    return _sinNegativos(
      cierre -
          entrada -
          PausasService.minutosPausados(r.pausas, hasta: cierre) -
          descuentoPendiente(r, minutosAhora: cierre),
    );
  }

  /// Minutos trabajados de un día ya cerrado. Sin salida real no hay nada
  /// que calcular y se cae al último valor guardado, que es lo que la app
  /// dejó escrito la última vez que supo del día.
  static int minutosTrabajados(Registro r) =>
      _jornada(r, cierre: _minutos(r.salidaReal)) ?? r.minutosCumplidos;

  /// Minutos trabajados calculados únicamente a partir de las marcas
  /// presentes (sin caer al valor guardado). Se usa al editar un día
  /// manualmente desde el Historial, donde el usuario define los valores
  /// definitivos de ese día.
  ///
  /// Sin salida real el día se cierra donde empezó la pausa que quedó
  /// abierta: es hasta ahí donde se sabe que se estuvo trabajando.
  static int minutosDesdeMarcas(Registro r) =>
      _jornada(r, cierre: _minutos(r.salidaReal) ?? _minutos(r.pausaAbierta?.inicio)) ??
      0;

  /// Minutos trabajados con el día todavía en marcha, contando contra
  /// [minutosAhora] (minutos desde medianoche). Es la versión pura de lo que
  /// muestra el dashboard del día en curso: mientras no haya salida real el
  /// reloj sigue corriendo, salvo que se esté en una pausa.
  static int minutosEnVivo(Registro r, int minutosAhora) =>
      _jornada(r, cierre: _minutos(r.salidaReal) ?? minutosAhora) ?? 0;

  /// Un día "cuenta" solo si tiene horas registradas. Los días en blanco
  /// no restan contra la meta: el balance es únicamente aditivo.
  static bool tieneHoras(Registro r) => minutosTrabajados(r) > 0;

  /// Meta que el día exige de verdad: cero en festivos, vacaciones,
  /// incapacidades y permisos.
  static int metaEfectiva(Registro r) => r.metaEfectivaMinutos;

  /// Diferencia del día contra su meta. Un día laboral sin horas registradas
  /// da 0 (no genera déficit); en un día justificado la meta es cero, así que
  /// todo lo que se haya trabajado cuenta como tiempo extra.
  static int diferenciaMinutos(Registro r) {
    if (r.tipoDia.esJustificado) return minutosTrabajados(r);
    return tieneHoras(r) ? minutosTrabajados(r) - r.metaMinutos : 0;
  }

  static List<DailyStat> dailyStats(List<Registro> registros) {
    final ordenados = [...registros]..sort((a, b) => b.fecha.compareTo(a.fecha));
    return ordenados
        .map((r) => DailyStat(registro: r, minutosTrabajados: minutosTrabajados(r)))
        .toList();
  }

  /// Patrones del historial completo: hora habitual de entrada y salida,
  /// el día de la semana que más rinde y la racha de cumplimiento.
  ///
  /// [ahora] es el día que cuenta como "hoy" para no romper la racha por un
  /// día en curso que todavía no tiene salida. Solo se pide para poder
  /// probar la función con una fecha fija.
  static EstadisticasPersonales estadisticasPersonales(
    List<Registro> registros, {
    DateTime? ahora,
  }) {
    final ordenados = [...registros]..sort((a, b) => a.fecha.compareTo(b.fecha));
    final hoy = _fechaKey(ahora ?? DateTime.now());

    final conEntrada = <int>[
      for (final r in ordenados)
        if (_minutos(r.entrada1) != null) _minutos(r.entrada1)!,
    ];
    final conSalida = <int>[
      for (final r in ordenados)
        if (_minutos(r.salidaReal) != null) _minutos(r.salidaReal)!,
    ];

    final conHoras = ordenados.where(tieneHoras).toList();

    // Minutos trabajados promedio por día de la semana, para encontrar el
    // que más rinde.
    final porDiaSemana = <int, List<int>>{};
    for (final r in conHoras) {
      final diaSemana = DateTime.parse(r.fecha).weekday;
      porDiaSemana.putIfAbsent(diaSemana, () => []).add(minutosTrabajados(r));
    }
    int? diaMasProductivo;
    int minutosDiaMasProductivo = 0;
    for (final entry in porDiaSemana.entries) {
      final promedio =
          entry.value.fold<int>(0, (s, m) => s + m) ~/ entry.value.length;
      if (diaMasProductivo == null || promedio > minutosDiaMasProductivo) {
        diaMasProductivo = entry.key;
        minutosDiaMasProductivo = promedio;
      }
    }

    // La racha recorre el historial en orden cronológico: un día laboral que
    // no cumplió la rompe, uno justificado ni la extiende ni la rompe (no
    // había nada que cumplir), y el día de hoy en curso tampoco la rompe
    // aunque todavía no tenga salida.
    int racha = 0;
    int mejor = 0;
    for (final r in ordenados) {
      if (!r.tipoDia.exigeMeta || r.tipoDia.esJustificado) continue;
      final minutos = minutosTrabajados(r);
      if (minutos > 0 && minutos >= r.metaEfectivaMinutos) {
        racha++;
        if (racha > mejor) mejor = racha;
      } else if (minutos > 0 || r.fecha.compareTo(hoy) < 0) {
        racha = 0;
      }
    }

    return EstadisticasPersonales(
      minutosEntradaPromedio: conEntrada.isEmpty
          ? null
          : (conEntrada.fold<int>(0, (s, m) => s + m) / conEntrada.length)
              .round(),
      minutosSalidaPromedio: conSalida.isEmpty
          ? null
          : (conSalida.fold<int>(0, (s, m) => s + m) / conSalida.length)
              .round(),
      diaMasProductivo: diaMasProductivo,
      minutosDiaMasProductivo: minutosDiaMasProductivo,
      rachaActual: racha,
      mejorRacha: mejor,
      diasConHoras: conHoras.length,
    );
  }

  static List<WeeklyStat> weeklyStats(List<Registro> registros) {
    final Map<String, List<Registro>> porSemana = {};
    for (final r in registros) {
      final fecha = DateTime.parse(r.fecha);
      final lunes = fecha.subtract(Duration(days: fecha.weekday - 1));
      final key = '${lunes.year.toString().padLeft(4, '0')}-'
          '${lunes.month.toString().padLeft(2, '0')}-'
          '${lunes.day.toString().padLeft(2, '0')}';
      porSemana.putIfAbsent(key, () => []).add(r);
    }
    final resultado = porSemana.entries.map((entry) {
      final registrosSemana = entry.value;
      // Solo los días con horas registradas suman meta; los días en blanco
      // no generan déficit.
      final conHoras = registrosSemana.where(tieneHoras).toList();
      final justificados =
          registrosSemana.where((r) => r.tipoDia.esJustificado).length;
      final totalTrabajado =
          conHoras.fold<int>(0, (sum, r) => sum + minutosTrabajados(r));
      final totalMeta = conHoras.fold<int>(0, (sum, r) => sum + metaEfectiva(r));
      final diasCumplidos = conHoras
          .where((r) => minutosTrabajados(r) >= metaEfectiva(r))
          .length;
      return WeeklyStat(
        semanaInicio: entry.key,
        totalTrabajado: totalTrabajado,
        totalMeta: totalMeta,
        diasCumplidos: diasCumplidos,
        totalDias: conHoras.length,
        // Un festivo o un día de vacaciones no es un día "sin registrar".
        diasSinRegistro: registrosSemana
            .where((r) => !tieneHoras(r) && r.tipoDia.exigeMeta)
            .length,
        diasJustificados: justificados,
      );
    }).toList();
    // Semanas sin horas ni días justificados no aportan nada al reporte.
    resultado.removeWhere((s) => s.totalDias == 0 && s.diasJustificados == 0);
    resultado.sort((a, b) => b.semanaInicio.compareTo(a.semanaInicio));
    return resultado;
  }

  static List<MonthlyStat> monthlyStats(List<Registro> registros) {
    final Map<String, List<Registro>> porMes = {};
    for (final r in registros) {
      final ym = r.fecha.substring(0, 7);
      porMes.putIfAbsent(ym, () => []).add(r);
    }
    final resultado = porMes.entries.map((entry) {
      final registrosMes = entry.value;
      final conHoras = registrosMes.where(tieneHoras).toList();
      final justificados =
          registrosMes.where((r) => r.tipoDia.esJustificado).length;
      final totalTrabajado =
          conHoras.fold<int>(0, (sum, r) => sum + minutosTrabajados(r));
      final totalMeta = conHoras.fold<int>(0, (sum, r) => sum + metaEfectiva(r));
      final diasCumplidos = conHoras
          .where((r) => minutosTrabajados(r) >= metaEfectiva(r))
          .length;
      return MonthlyStat(
        yearMonth: entry.key,
        totalTrabajado: totalTrabajado,
        totalMeta: totalMeta,
        diasCumplidos: diasCumplidos,
        totalDias: conHoras.length,
        diasSinRegistro: registrosMes
            .where((r) => !tieneHoras(r) && r.tipoDia.exigeMeta)
            .length,
        diasJustificados: justificados,
      );
    }).toList();
    resultado.removeWhere((m) => m.totalDias == 0 && m.diasJustificados == 0);
    resultado.sort((a, b) => b.yearMonth.compareTo(a.yearMonth));
    return resultado;
  }

  static ProjectionStat proyeccionMesActual(
    List<Registro> registros,
    AppProvider appProvider,
    DateTime ahora,
  ) {
    final yearMonth =
        '${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}';
    final diasEnMes = DateTime(ahora.year, ahora.month + 1, 0).day;

    final registrosMes =
        registros.where((r) => r.fecha.startsWith(yearMonth)).toList();
    final fechasConHoras =
        registrosMes.where(tieneHoras).map((r) => r.fecha).toSet();
    final porFecha = {for (final r in registrosMes) r.fecha: r};

    int metaMesMinutos = 0;
    for (var dia = 1; dia <= diasEnMes; dia++) {
      final fecha = DateTime(ahora.year, ahora.month, dia);
      // Un día sin meta no exige nada. Antes se descartaban el sábado y el
      // domingo por su nombre; ahora los descarta su meta, así que quien
      // trabaja los sábados los ve contar y quien libra el miércoles no.
      final metaDelDia = appProvider.metaMinutosParaDia(fecha.weekday);
      if (metaDelDia <= 0) continue;
      // Un asueto de ley tampoco exige horas, aunque el día no esté marcado
      // a mano: un mes con dos asuetos tiene una meta más baja y la
      // proyección quedaría exigiendo un déficit que no existe.
      final sector = appProvider.sectorAsuetos;
      if (sector != null && FestivosSV.enFecha(fecha, sector: sector) != null) {
        continue;
      }
      // Un festivo, una vacación o una incapacidad ya marcada no exige horas,
      // ni siquiera si todavía no ha llegado: no debe inflar la meta del mes.
      final registro = porFecha[_fechaKey(fecha)];
      if (registro != null && registro.tipoDia.esJustificado) continue;
      // Los días ya pasados sin horas registradas no suman meta: no deben
      // generar déficit, el conteo es únicamente aditivo.
      final esPasado = dia < ahora.day;
      if (esPasado && !fechasConHoras.contains(_fechaKey(fecha))) {
        continue;
      }
      metaMesMinutos += metaDelDia;
    }

    final trabajadoHastaHoy = registrosMes.fold<int>(
        0, (sum, r) => sum + minutosTrabajados(r));

    final totalSemanasMes = ((diasEnMes - 1) ~/ 7) + 1;
    final semanaActual = ((ahora.day - 1) ~/ 7) + 1;

    final promedioSemanal = trabajadoHastaHoy / semanaActual;
    final proyeccionTotal = (promedioSemanal * totalSemanasMes).round();

    return ProjectionStat(
      metaMesMinutos: metaMesMinutos,
      trabajadoHastaHoyMinutos: trabajadoHastaHoy,
      semanaActual: semanaActual,
      totalSemanasMes: totalSemanasMes,
      proyeccionTotalMinutos: proyeccionTotal,
    );
  }

  static String _fechaKey(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  static List<BalanceDay> balanceHistorico(List<Registro> registros) {
    final ordenados = [...registros]..sort((a, b) => a.fecha.compareTo(b.fecha));
    int acumulado = 0;
    return ordenados.map((r) {
      // Los días sin horas registradas no restan al banco de horas.
      final diferencia = diferenciaMinutos(r);
      acumulado += diferencia;
      return BalanceDay(
        fecha: r.fecha,
        diferenciaMinutos: diferencia,
        balanceAcumuladoMinutos: acumulado,
        sinRegistro: !tieneHoras(r) && r.tipoDia.exigeMeta,
        tipoDia: r.tipoDia,
      );
    }).toList();
  }

  /// Los registros cuya fecha cae dentro de [desde]-[hasta] (ambos
  /// inclusive). Un extremo nulo deja ese lado abierto, así que sin
  /// extremos devuelve todo el historial.
  static List<Registro> registrosEnRango(
    List<Registro> registros, {
    DateTime? desde,
    DateTime? hasta,
  }) {
    final inicio = desde == null ? null : _fechaKey(desde);
    final fin = hasta == null ? null : _fechaKey(hasta);
    final filtrados = registros.where((r) {
      if (inicio != null && r.fecha.compareTo(inicio) < 0) return false;
      if (fin != null && r.fecha.compareTo(fin) > 0) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    return filtrados;
  }

  /// Igual que [registrosEnRango] pero para los movimientos del banco.
  static List<MovimientoBanco> movimientosEnRango(
    List<MovimientoBanco> movimientos, {
    DateTime? desde,
    DateTime? hasta,
  }) {
    final inicio = desde == null ? null : _fechaKey(desde);
    final fin = hasta == null ? null : _fechaKey(hasta);
    final filtrados = movimientos.where((m) {
      if (inicio != null && m.fecha.compareTo(inicio) < 0) return false;
      if (fin != null && m.fecha.compareTo(fin) > 0) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    return filtrados;
  }

  /// Totales del periodo listos para exportar o enseñar.
  static ResumenPeriodo resumenPeriodo(
    List<Registro> registros,
    List<MovimientoBanco> movimientos,
  ) {
    final conHoras = registros.where(tieneHoras).toList();
    return ResumenPeriodo(
      totalTrabajado:
          conHoras.fold<int>(0, (sum, r) => sum + minutosTrabajados(r)),
      totalMeta: conHoras.fold<int>(0, (sum, r) => sum + metaEfectiva(r)),
      diasConHoras: conHoras.length,
      diasCumplidos: conHoras
          .where((r) => minutosTrabajados(r) >= metaEfectiva(r))
          .length,
      diasIncumplidos: conHoras
          .where((r) => minutosTrabajados(r) < metaEfectiva(r))
          .length,
      diasSinRegistro:
          registros.where((r) => !tieneHoras(r) && r.tipoDia.exigeMeta).length,
      diasJustificados:
          registros.where((r) => r.tipoDia.esJustificado).length,
      minutosMovimientos: saldoMovimientos(movimientos),
    );
  }

  /// Suma de los ajustes y canjes anotados a mano.
  static int saldoMovimientos(List<MovimientoBanco> movimientos) =>
      movimientos.fold<int>(0, (sum, m) => sum + m.minutos);

  /// Saldo del banco de horas separando lo que viene de los días trabajados
  /// de lo que se anotó a mano, para poder explicarle al usuario de dónde
  /// sale la cifra.
  static EstadoBanco estadoBanco({
    required List<Registro> registros,
    required List<MovimientoBanco> movimientos,
    required int metaDiariaMinutos,
  }) {
    final deDias =
        registros.fold<int>(0, (sum, r) => sum + diferenciaMinutos(r));
    return EstadoBanco(
      minutosDeDias: deDias,
      minutosDeMovimientos: saldoMovimientos(movimientos),
      metaDiariaMinutos: metaDiariaMinutos,
    );
  }

  /// Fecha del [diasHabiles]-ésimo día laboral posterior a [desde].
  ///
  /// Descarta sábados y domingos siempre, y además los asuetos de ley cuando
  /// se indica un [sector]. Sin sector el plazo es solo una guía: sigue sin
  /// saber nada de las fiestas patronales ni del calendario de la empresa.
  static DateTime fechaTrasDiasHabiles(
    DateTime desde,
    int diasHabiles, {
    SectorLaboral? sector,
  }) {
    var fecha = DateTime(desde.year, desde.month, desde.day);
    var restantes = diasHabiles;
    // Tope de seguridad: aunque el calendario viniera mal, el bucle termina.
    var vueltas = 0;
    while (restantes > 0 && vueltas < 3650) {
      vueltas++;
      fecha = DateTime(fecha.year, fecha.month, fecha.day + 1);
      if (fecha.weekday == DateTime.saturday ||
          fecha.weekday == DateTime.sunday) {
        continue;
      }
      if (sector != null && FestivosSV.enFecha(fecha, sector: sector) != null) {
        continue;
      }
      restantes--;
    }
    return fecha;
  }

  /// Traduce el saldo a un plan concreto: cuántos minutos extra por día hacen
  /// falta para llegar a cero en [diasHabiles] días laborales.
  static PlanBanco planCompensacion({
    required int saldoMinutos,
    required int diasHabiles,
    required DateTime desde,
    SectorLaboral? sector,
  }) {
    final dias = diasHabiles < 1 ? 1 : diasHabiles;
    final deficit = saldoMinutos < 0 ? -saldoMinutos : 0;
    return PlanBanco(
      diasHabiles: dias,
      fechaLimite: fechaTrasDiasHabiles(desde, dias, sector: sector),
      // Se redondea hacia arriba: quedarse corto deja el banco en rojo.
      minutosExtraPorDia: deficit == 0 ? 0 : (deficit + dias - 1) ~/ dias,
      minutosDisponibles: saldoMinutos > 0 ? saldoMinutos : 0,
    );
  }
}
