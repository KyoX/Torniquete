import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils/time_utils.dart';
import 'prefs_service.dart';

/// Programa y cancela las notificaciones locales de la app: el aviso de
/// salida (5 minutos antes de la hora estimada) y los recordatorios para
/// no olvidar marcar la entrada, la pausa del almuerzo y la vuelta.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  static const int _reminderId = 1001;
  static const int _pruebaId = 1002;
  static const String _canalId = 'torniquete_salida';
  static const String _canalNombre = 'Recordatorio de salida';
  static const String _canalDescripcion =
      'Avisa cuando falta poco para la hora de salida';

  /// Canal aparte para los avisos de marca, para que el usuario pueda
  /// silenciarlos desde Android sin perder el aviso de salida.
  static const String _canalMarcasId = 'torniquete_marcas';
  static const String _canalMarcasNombre = 'Recordatorios de marca';
  static const String _canalMarcasDescripcion =
      'Recuerda marcar la entrada, la pausa del almuerzo y la vuelta';

  /// Cuántas citas futuras se dejan programadas por recordatorio. Dos
  /// semanas laborales cubren de sobra cualquier racha sin abrir la app.
  static const int ocurrenciasPorRecordatorio = 10;

  /// Primer id de cada recordatorio; ocupa [ocurrenciasPorRecordatorio]
  /// consecutivos. Los rangos van de 100 en 100 para que nunca se pisen.
  static const Map<RecordatorioTipo, int> _idsBase = {
    RecordatorioTipo.entrada: 2000,
    RecordatorioTipo.salidaAlmuerzo: 2100,
    RecordatorioTipo.regresoAlmuerzo: 2200,
    RecordatorioTipo.confirmarSalida: 2300,
  };

  /// Título y cuerpo de cada aviso. El texto explica *por qué* importa la
  /// marca, que es lo que hace que valga la pena atenderla.
  static const Map<RecordatorioTipo, (String, String)> _textos = {
    RecordatorioTipo.entrada: (
      'Marca tu entrada',
      'Registra la entrada para que el día empiece a contar.',
    ),
    RecordatorioTipo.salidaAlmuerzo: (
      'Hora de almorzar',
      'Marca la pausa: sin ella el día se sigue contando como trabajado.',
    ),
    RecordatorioTipo.regresoAlmuerzo: (
      'De vuelta al trabajo',
      'Continúa la jornada: la pausa corre hasta que la cierres.',
    ),
    RecordatorioTipo.confirmarSalida: (
      'Confirma tu salida',
      'El día sigue abierto y sin salida marcada. Ciérralo antes de que '
          'las horas de después se pierdan.',
    ),
  };

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Identificador IANA de la zona horaria detectada ("America/Bogota").
  /// Null mientras no se haya llamado a [init].
  String? get zonaHoraria => _zonaHoraria;
  String? _zonaHoraria;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _configurarZonaHoraria();

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
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalMarcasId,
        _canalMarcasNombre,
        description: _canalMarcasDescripcion,
        importance: Importance.high,
      ),
    );
    await _android?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Fija la zona horaria local real del teléfono. Es imprescindible para
  /// programar notificaciones a una hora del día concreta: la abreviatura que
  /// devuelve `DateTime.timeZoneName` ("COT", "-05") no existe en la base de
  /// datos IANA, así que leerla de ahí caía siempre al fallback.
  Future<void> _configurarZonaHoraria() async {
    try {
      final zona = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zona.identifier));
      _zonaHoraria = zona.identifier;
      return;
    } catch (e) {
      debugPrint('No se pudo leer la zona horaria del sistema: $e');
    }
    // Último recurso: UTC mantiene correcto el instante de los recordatorios
    // que se calculan a partir de un DateTime local concreto, aunque las
    // horas fijas del día (mismo reloj cada mañana) sí se desviarían.
    tz.setLocalLocation(tz.UTC);
    _zonaHoraria = tz.UTC.name;
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
    bool canalMarcas = false,
  }) async {
    final scheduledDate = tz.TZDateTime.from(cuando, tz.local);
    final detalles = NotificationDetails(
      android: AndroidNotificationDetails(
        canalMarcas ? _canalMarcasId : _canalId,
        canalMarcas ? _canalMarcasNombre : _canalNombre,
        channelDescription:
            canalMarcas ? _canalMarcasDescripcion : _canalDescripcion,
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

  /// Cancela todas las citas pendientes de un recordatorio de marca.
  ///
  /// Se consulta primero qué hay agendado en vez de cancelar el rango a
  /// ciegas: esto corre en cada marca y con los recordatorios apagados —que
  /// es lo normal— no cuesta nada.
  Future<void> cancelarRecordatorioMarca(RecordatorioTipo tipo) async {
    final base = _idsBase[tipo]!;
    final limite = base + ocurrenciasPorRecordatorio;
    final pendientes = await _plugin.pendingNotificationRequests();
    for (final pendiente in pendientes) {
      if (pendiente.id >= base && pendiente.id < limite) {
        await _plugin.cancel(pendiente.id);
      }
    }
  }

  /// Reprograma un recordatorio de marca.
  ///
  /// Android no sabe repetir "todos los días de trabajo saltándose el de hoy
  /// si la marca ya está hecha", así que en vez de una alarma repetida se
  /// dejan varias citas concretas. Cada vez que se abre la app o se registra
  /// una marca se vuelven a calcular, y con [omitirHoy] se salta el aviso de
  /// hoy cuando esa marca ya no hace falta.
  ///
  /// [dias] son los días de la semana en que se trabaja; los demás no
  /// reciben ninguna cita.
  ///
  /// Devuelve cuántas citas quedaron programadas.
  Future<int> programarRecordatorioMarca({
    required RecordatorioTipo tipo,
    required int minutosDelDia,
    bool omitirHoy = false,
    Set<int> dias = TimeUtils.diasLaborales,
    DateTime? ahora,
  }) async {
    await init();
    await cancelarRecordatorioMarca(tipo);

    final (titulo, cuerpo) = _textos[tipo]!;
    final base = _idsBase[tipo]!;
    final momentos = TimeUtils.proximasOcurrenciasHabiles(
      ahora ?? DateTime.now(),
      minutosDelDia,
      ocurrenciasPorRecordatorio,
      omitirHoy: omitirHoy,
      dias: dias,
    );

    var programadas = 0;
    for (var i = 0; i < momentos.length; i++) {
      final ok = await _programar(
        id: base + i,
        cuando: momentos[i],
        titulo: titulo,
        cuerpo: cuerpo,
        canalMarcas: true,
      );
      if (ok) programadas++;
    }
    return programadas;
  }

  /// Cuántas citas de este recordatorio están pendientes ahora mismo.
  /// Lo usa el diagnóstico de Ajustes.
  Future<int> recordatoriosPendientes(RecordatorioTipo tipo) async {
    final base = _idsBase[tipo]!;
    final limite = base + ocurrenciasPorRecordatorio;
    final pendientes = await _plugin.pendingNotificationRequests();
    return pendientes.where((p) => p.id >= base && p.id < limite).length;
  }
}
