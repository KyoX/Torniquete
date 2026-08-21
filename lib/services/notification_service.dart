import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Programa y cancela la notificación local que avisa al usuario
/// 5 minutos antes de la hora estimada de salida.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  static const int _reminderId = 1001;
  static const int _pruebaId = 1002;
  static const String _canalId = 'torniquete_salida';
  static const String _canalNombre = 'Recordatorio de salida';
  static const String _canalDescripcion =
      'Avisa cuando falta poco para la hora de salida';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      // `timeZoneName` suele devolver una abreviatura ("COT", "-05") que no
      // existe en la base de datos IANA; si falla, UTC sigue siendo correcto
      // porque TZDateTime.from conserva el instante exacto.
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalId,
        _canalNombre,
        description: _canalDescripcion,
        importance: Importance.high,
      ),
    );
    await _android?.requestNotificationsPermission();

    _initialized = true;
  }

  /// True si el usuario tiene habilitadas las notificaciones de la app.
  Future<bool> notificacionesHabilitadas() async =>
      await _android?.areNotificationsEnabled() ?? false;

  /// True si el sistema permite programar alarmas exactas (Android 12+).
  Future<bool> puedeProgramarExactas() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  /// True si el recordatorio de salida está programado ahora mismo.
  Future<bool> recordatorioProgramado() async {
    final pendientes = await _plugin.pendingNotificationRequests();
    return pendientes.any((p) => p.id == _reminderId);
  }

  Future<void> pedirPermisos() async {
    await _android?.requestNotificationsPermission();
    if (!await puedeProgramarExactas()) {
      await _android?.requestExactAlarmsPermission();
    }
  }

  Future<void> cancelarRecordatorioSalida() async {
    await _plugin.cancel(_reminderId);
  }

  /// Programa una notificación 5 minutos antes de [horaEstimadaSalida].
  /// Si esa hora ya pasó o falta menos de 5 minutos, no programa nada.
  /// Devuelve true si quedó programada.
  Future<bool> programarRecordatorioSalida({
    required DateTime horaEstimadaSalida,
    required String nombre,
  }) async {
    await init();
    await cancelarRecordatorioSalida();

    final horaAviso = horaEstimadaSalida.subtract(const Duration(minutes: 5));
    if (!horaAviso.isAfter(DateTime.now())) return false;

    return _programar(
      id: _reminderId,
      cuando: horaAviso,
      titulo: '¡Casi es hora de salir!',
      cuerpo:
          'Prepara tus cosas, $nombre! Faltan 5 minutos para pasar el torniquete.',
    );
  }

  /// Programa una notificación de prueba dentro de [espera] para verificar
  /// que el sistema realmente entrega las alarmas programadas.
  Future<bool> programarPrueba({
    Duration espera = const Duration(seconds: 10),
  }) async {
    await init();
    await _plugin.cancel(_pruebaId);
    return _programar(
      id: _pruebaId,
      cuando: DateTime.now().add(espera),
      titulo: 'Notificación de prueba',
      cuerpo: 'Si ves esto, los recordatorios de salida funcionan.',
    );
  }

  Future<bool> _programar({
    required int id,
    required DateTime cuando,
    required String titulo,
    required String cuerpo,
  }) async {
    final scheduledDate = tz.TZDateTime.from(cuando, tz.local);
    const detalles = NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNombre,
        channelDescription: _canalDescripcion,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    Future<void> agendar(AndroidScheduleMode modo) => _plugin.zonedSchedule(
          id,
          titulo,
          cuerpo,
          scheduledDate,
          detalles,
          androidScheduleMode: modo,
        );

    try {
      await agendar(AndroidScheduleMode.exactAllowWhileIdle);
      return true;
    } on PlatformException catch (e) {
      // Sin permiso de alarmas exactas: mejor una notificación aproximada
      // que ninguna.
      debugPrint('Alarma exacta rechazada (${e.code}), se usa modo inexacto.');
      try {
        await agendar(AndroidScheduleMode.inexactAllowWhileIdle);
        return true;
      } catch (e2) {
        debugPrint('No se pudo programar la notificación: $e2');
        return false;
      }
    } catch (e) {
      debugPrint('No se pudo programar la notificación: $e');
      return false;
    }
  }
}
