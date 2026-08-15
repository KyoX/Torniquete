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

  static String formatDurationMinutes(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    return '$sign${h}h ${m.toString().padLeft(2, '0')}m';
  }
}
