import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Programa y cancela la notificación local que avisa al usuario
/// 5 minutos antes de la hora estimada de salida.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  static const int _reminderId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final String localName = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      tz.setLocalLocation(tz.local);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'torniquete_salida',
        'Recordatorio de salida',
        description: 'Avisa cuando falta poco para la hora de salida',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<void> cancelarRecordatorioSalida() async {
    await _plugin.cancel(_reminderId);
  }

  /// Programa una notificación 5 minutos antes de [horaEstimadaSalida].
  /// Si esa hora ya pasó o falta menos de 5 minutos, no programa nada.
  Future<void> programarRecordatorioSalida({
    required DateTime horaEstimadaSalida,
    required String nombre,
  }) async {
    await cancelarRecordatorioSalida();

    final horaAviso = horaEstimadaSalida.subtract(const Duration(minutes: 5));
    final ahora = DateTime.now();
    if (horaAviso.isBefore(ahora)) return;

    final scheduledDate = tz.TZDateTime.from(horaAviso, tz.local);

    await _plugin.zonedSchedule(
      _reminderId,
      '¡Casi es hora de salir!',
      'Prepara tus cosas, $nombre! Faltan 5 minutos para pasar el torniquete.',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'torniquete_salida',
          'Recordatorio de salida',
          channelDescription:
              'Avisa cuando falta poco para la hora de salida',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
