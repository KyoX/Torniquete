import '../models/registro.dart';
import '../providers/app_provider.dart';
import '../utils/time_utils.dart';

class DailyStat {
  final Registro registro;
  final int minutosTrabajados;

  DailyStat({required this.registro, required this.minutosTrabajados});

  /// Día sin horas registradas: no cuenta ni a favor ni en contra.
  bool get sinRegistro => minutosTrabajados <= 0;

  bool get cumplida => !sinRegistro && minutosTrabajados >= registro.metaMinutos;

  /// Diferencia contra la meta. Los días sin horas registradas no restan.
  int get diferenciaMinutos =>
      sinRegistro ? 0 : minutosTrabajados - registro.metaMinutos;
}

class WeeklyStat {
  final String semanaInicio; // "2026-08-11" (lunes de la semana)
  final int totalTrabajado;
  final int totalMeta;
  final int diasCumplidos;
  final int totalDias; // días con horas registradas
  final int diasSinRegistro;

  WeeklyStat({
    required this.semanaInicio,
    required this.totalTrabajado,
    required this.totalMeta,
    required this.diasCumplidos,
    required this.totalDias,
    this.diasSinRegistro = 0,
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

  MonthlyStat({
    required this.yearMonth,
    required this.totalTrabajado,
    required this.totalMeta,
    required this.diasCumplidos,
    required this.totalDias,
    this.diasSinRegistro = 0,
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

  BalanceDay({
    required this.fecha,
    required this.diferenciaMinutos,
    required this.balanceAcumuladoMinutos,
    this.sinRegistro = false,
  });
}

/// Funciones puras de agregación para las pantallas de reportes.
/// No dependen de widgets ni de la base de datos directamente: reciben
/// la lista de registros ya cargada.
class ReportsService {
  static int minutosTrabajados(Registro r) {
    final e1 = TimeUtils.parseTimeOfDay(r.entrada1);
    final s1 = TimeUtils.parseTimeOfDay(r.salida1);
    final e2 = TimeUtils.parseTimeOfDay(r.entrada2);
    final sr = TimeUtils.parseTimeOfDay(r.salidaReal);
    if (e1 != null && s1 != null && e2 != null && sr != null) {
      return (TimeUtils.toMinutes(s1) - TimeUtils.toMinutes(e1)) +
          (TimeUtils.toMinutes(sr) - TimeUtils.toMinutes(e2));
    }
    return r.minutosCumplidos;
  }

  /// Minutos trabajados calculados únicamente a partir de las marcas
  /// presentes (sin caer al valor guardado). Se usa al editar un día
  /// manualmente desde el Historial, donde el usuario define los valores
  /// definitivos de ese día.
  static int minutosDesdeMarcas(Registro r) {
    int total = 0;
    final e1 = TimeUtils.parseTimeOfDay(r.entrada1);
    final s1 = TimeUtils.parseTimeOfDay(r.salida1);
    final e2 = TimeUtils.parseTimeOfDay(r.entrada2);
    final sr = TimeUtils.parseTimeOfDay(r.salidaReal);
    if (e1 != null && s1 != null) {
      total += TimeUtils.toMinutes(s1) - TimeUtils.toMinutes(e1);
    }
    if (e2 != null && sr != null) {
      total += TimeUtils.toMinutes(sr) - TimeUtils.toMinutes(e2);
    }
    return total;
  }

  /// Un día "cuenta" solo si tiene horas registradas. Los días en blanco
  /// no restan contra la meta: el balance es únicamente aditivo.
  static bool tieneHoras(Registro r) => minutosTrabajados(r) > 0;

  /// Diferencia del día contra su meta; 0 si el día no tiene horas registradas.
  static int diferenciaMinutos(Registro r) =>
      tieneHoras(r) ? minutosTrabajados(r) - r.metaMinutos : 0;

  static List<DailyStat> dailyStats(List<Registro> registros) {
    final ordenados = [...registros]..sort((a, b) => b.fecha.compareTo(a.fecha));
    return ordenados
        .map((r) => DailyStat(registro: r, minutosTrabajados: minutosTrabajados(r)))
        .toList();
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
      final totalTrabajado =
          conHoras.fold<int>(0, (sum, r) => sum + minutosTrabajados(r));
      final totalMeta = conHoras.fold<int>(0, (sum, r) => sum + r.metaMinutos);
      final diasCumplidos = conHoras
          .where((r) => minutosTrabajados(r) >= r.metaMinutos)
          .length;
      return WeeklyStat(
        semanaInicio: entry.key,
        totalTrabajado: totalTrabajado,
        totalMeta: totalMeta,
        diasCumplidos: diasCumplidos,
        totalDias: conHoras.length,
        diasSinRegistro: registrosSemana.length - conHoras.length,
      );
    }).toList();
    // Semanas donde no se registraron horas no aportan nada al reporte.
    resultado.removeWhere((s) => s.totalDias == 0);
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
      final totalTrabajado =
          conHoras.fold<int>(0, (sum, r) => sum + minutosTrabajados(r));
      final totalMeta = conHoras.fold<int>(0, (sum, r) => sum + r.metaMinutos);
      final diasCumplidos = conHoras
          .where((r) => minutosTrabajados(r) >= r.metaMinutos)
          .length;
      return MonthlyStat(
        yearMonth: entry.key,
        totalTrabajado: totalTrabajado,
        totalMeta: totalMeta,
        diasCumplidos: diasCumplidos,
        totalDias: conHoras.length,
        diasSinRegistro: registrosMes.length - conHoras.length,
      );
    }).toList();
    resultado.removeWhere((m) => m.totalDias == 0);
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

    int metaMesMinutos = 0;
    for (var dia = 1; dia <= diasEnMes; dia++) {
      final fecha = DateTime(ahora.year, ahora.month, dia);
      if (fecha.weekday == DateTime.saturday ||
          fecha.weekday == DateTime.sunday) {
        continue;
      }
      // Los días ya pasados sin horas registradas no suman meta: no deben
      // generar déficit, el conteo es únicamente aditivo.
      final esPasado = dia < ahora.day;
      if (esPasado && !fechasConHoras.contains(_fechaKey(fecha))) {
        continue;
      }
      metaMesMinutos += appProvider.metaMinutosParaDia(fecha.weekday);
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
        sinRegistro: !tieneHoras(r),
      );
    }).toList();
  }
}
