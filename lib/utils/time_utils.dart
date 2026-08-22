import 'package:flutter/material.dart';

/// Utilidades para convertir entre TimeOfDay, minutos desde medianoche
/// y el formato "HH:mm" usado para persistir las marcas en la base de datos.
class TimeUtils {
  static String formatTimeOfDay(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static TimeOfDay? parseTimeOfDay(String? value) {
    if (value == null || !value.contains(':')) return null;
    final parts = value.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static int toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  static TimeOfDay fromMinutes(int minutes) {
    final normalized = minutes % (24 * 60);
    final positive = normalized < 0 ? normalized + 24 * 60 : normalized;
    return TimeOfDay(hour: positive ~/ 60, minute: positive % 60);
  }

  static String formatHHmm(String? raw) {
    final t = parseTimeOfDay(raw);
    if (t == null) return '--:--';
    return formatTimeOfDay(t);
  }

  static String formatAmPm(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Las próximas [cantidad] veces que darán las [minutosDelDia] en un día
  /// laboral (lunes a viernes), empezando por [desde].
  ///
  /// Se usa para los recordatorios de marca: en vez de una notificación
  /// diaria repetida —que también sonaría sábado y domingo y no se puede
  /// saltar un día suelto— se programan varias citas concretas y se vuelven
  /// a calcular cada vez que la app se abre o se registra una marca.
  ///
  /// Con [omitirHoy] se descarta la ocurrencia de hoy aunque todavía no haya
  /// llegado la hora (por ejemplo, porque esa marca ya está hecha).
  static List<DateTime> proximasOcurrenciasHabiles(
    DateTime desde,
    int minutosDelDia,
    int cantidad, {
    bool omitirHoy = false,
  }) {
    if (cantidad <= 0) return const [];
    final resultado = <DateTime>[];
    // Tope de seguridad: 8 semanas bastan de sobra para cualquier cantidad
    // razonable y evitan un bucle infinito si algo viene mal.
    for (var i = 0; i < 56 && resultado.length < cantidad; i++) {
      // Se construye cada fecha desde el día 1 en vez de ir sumando duraciones:
      // así el resultado es siempre la hora del reloj que se pidió.
      final dia = DateTime(desde.year, desde.month, desde.day + i);
      final esFinDeSemana =
          dia.weekday == DateTime.saturday || dia.weekday == DateTime.sunday;
      if (esFinDeSemana) continue;

      final momento = DateTime(
        dia.year,
        dia.month,
        dia.day,
        minutosDelDia ~/ 60,
        minutosDelDia % 60,
      );
      final esHoy = i == 0;
      if (esHoy && (omitirHoy || !momento.isAfter(desde))) continue;
      resultado.add(momento);
    }
    return resultado;
  }

  static String formatDurationMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    return '$sign${h}h ${m.toString().padLeft(2, '0')}m';
  }
}
