import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../models/ubicacion_marca.dart';
import '../services/db_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../utils/time_utils.dart';

enum MarcaTipo { entrada1, salida1, entrada2, salidaReal }

/// Maneja el registro del día actual: sus marcas, el cálculo de la hora
/// estimada de salida y la persistencia en SQLite + notificaciones.
class RegistroProvider extends ChangeNotifier {
  final DbService _db = DbService.instance;
  final PrefsService _prefs = PrefsService();

  Registro? registroHoy;
  bool cargando = true;

  /// Ubicaciones guardadas para las marcas de hoy, por tipo de marca.
  Map<String, UbicacionMarca> ubicacionesHoy = {};

  /// Tipos de marca cuya ubicación se está capturando en este momento.
  final Set<MarcaTipo> _capturandoUbicacion = {};

  bool capturandoUbicacion(MarcaTipo tipo) =>
      _capturandoUbicacion.contains(tipo);

  UbicacionMarca? ubicacionDe(MarcaTipo tipo) => ubicacionesHoy[tipo.name];

  static String fechaHoy() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Carga (o crea) el registro de hoy. Si se pasa [nombreUsuario] se
  /// vuelve a programar el recordatorio de salida, para que siga vigente
  /// aunque la alarma se haya perdido (reinstalación, cierre forzado, etc.).
  Future<void> cargarRegistroDeHoy(
    int metaMinutos, {
    String? nombreUsuario,
  }) async {
    cargando = true;
    notifyListeners();
    final fecha = fechaHoy();
    final existente = await _db.getRegistroPorFecha(fecha);
    registroHoy = existente ??
        Registro(fecha: fecha, metaMinutos: metaMinutos, minutosCumplidos: 0);
    if (existente != null && existente.metaMinutos != metaMinutos) {
      registroHoy = registroHoy!.copyWith(metaMinutos: metaMinutos);
    }
    ubicacionesHoy = await _db.getUbicacionesPorFecha(fecha);
    cargando = false;
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
  }

  TimeOfDay? get entrada1 => TimeUtils.parseTimeOfDay(registroHoy?.entrada1);
  TimeOfDay? get salida1 => TimeUtils.parseTimeOfDay(registroHoy?.salida1);
  TimeOfDay? get entrada2 => TimeUtils.parseTimeOfDay(registroHoy?.entrada2);
  TimeOfDay? get salidaReal => TimeUtils.parseTimeOfDay(registroHoy?.salidaReal);

  /// Tiempo trabajado en la mañana (Marca2 - Marca1), en minutos.
  int? get tiempoTrabajadoMananaMin {
    final e1 = entrada1;
    final s1 = salida1;
    if (e1 == null || s1 == null) return null;
    return TimeUtils.toMinutes(s1) - TimeUtils.toMinutes(e1);
  }

  /// Tiempo restante para cumplir la meta tras descontar lo trabajado en la mañana.
  int? get tiempoRestanteMin {
    final trabajado = tiempoTrabajadoMananaMin;
    if (trabajado == null || registroHoy == null) return null;
    return registroHoy!.metaMinutos - trabajado;
  }

  /// Hora estimada de salida = Marca3 (entrada2) + tiempo restante.
  TimeOfDay? get horaEstimadaSalida {
    final e2 = entrada2;
    final restante = tiempoRestanteMin;
    if (e2 == null || restante == null) return null;
    return TimeUtils.fromMinutes(TimeUtils.toMinutes(e2) + restante);
  }

  DateTime? get horaEstimadaSalidaDateTime {
    final t = horaEstimadaSalida;
    if (t == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  /// Minutos trabajados hasta ahora. Si ya se confirmó la salida real, el
  /// cálculo queda fijo (mañana + tarde real); si no, se estima en vivo con
  /// la hora actual del dispositivo.
  int get minutosTrabajadosHastaAhora {
    int total = 0;
    final trabajadoManana = tiempoTrabajadoMananaMin;
    if (trabajadoManana != null && trabajadoManana > 0) {
      total += trabajadoManana;
    }
    final e2 = entrada2;
    final sr = salidaReal;
    if (e2 != null && sr != null) {
      final trabajadoTarde = TimeUtils.toMinutes(sr) - TimeUtils.toMinutes(e2);
      if (trabajadoTarde > 0) total += trabajadoTarde;
    } else if (e2 != null) {
      final ahora = TimeOfDay.now();
      final restanteHoy = TimeUtils.toMinutes(ahora) - TimeUtils.toMinutes(e2);
      if (restanteHoy > 0) total += restanteHoy;
    }
    return total;
  }

  double get progreso {
    final meta = registroHoy?.metaMinutos ?? 1;
    if (meta <= 0) return 0;
    final valor = minutosTrabajadosHastaAhora / meta;
    return valor.clamp(0.0, 1.0);
  }

  bool get metaCumplida =>
      registroHoy != null && minutosTrabajadosHastaAhora >= registroHoy!.metaMinutos;

  Future<void> marcar(MarcaTipo tipo, {required String nombreUsuario}) async {
    await _setMarca(tipo, TimeOfDay.now(), nombreUsuario: nombreUsuario);
  }

  /// Confirma la hora real de salida (por si se trabaja más tiempo del
  /// estimado). Queda registrada para los reportes de cumplimiento.
  Future<void> confirmarSalida({required String nombreUsuario}) async {
    await _setMarca(MarcaTipo.salidaReal, TimeOfDay.now(),
        nombreUsuario: nombreUsuario);
  }

  Future<void> editarManualmente(
    MarcaTipo tipo,
    TimeOfDay hora, {
    required String nombreUsuario,
  }) async {
    await _setMarca(tipo, hora, nombreUsuario: nombreUsuario, manual: true);
  }

  Future<void> _setMarca(
    MarcaTipo tipo,
    TimeOfDay hora, {
    required String nombreUsuario,
    bool manual = false,
  }) async {
    if (registroHoy == null) return;
    final valor = TimeUtils.formatTimeOfDay(hora);
    switch (tipo) {
      case MarcaTipo.entrada1:
        registroHoy = registroHoy!.copyWith(entrada1: valor);
        break;
      case MarcaTipo.salida1:
        registroHoy = registroHoy!.copyWith(salida1: valor);
        break;
      case MarcaTipo.entrada2:
        registroHoy = registroHoy!.copyWith(entrada2: valor);
        break;
      case MarcaTipo.salidaReal:
        registroHoy = registroHoy!.copyWith(salidaReal: valor);
        break;
    }
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
    await _guardarUbicacionDeMarca(tipo, valor, manual: manual);
  }

  /// Deja constancia de dónde estaba el usuario al registrar la marca.
  /// Es totalmente opcional: si el ajuste está apagado, el permiso no está
  /// concedido o el GPS falla, la marca queda igual y sin ubicación.
  Future<void> _guardarUbicacionDeMarca(
    MarcaTipo tipo,
    String hora, {
    required bool manual,
  }) async {
    if (registroHoy == null) return;
    if (!await _prefs.getGuardarUbicacion()) return;

    _capturandoUbicacion.add(tipo);
    notifyListeners();
    try {
      final posicion = await LocationService.instance.capturar();
      if (posicion == null) return;
      final ubicacion = UbicacionMarca(
        fecha: registroHoy!.fecha,
        tipo: tipo.name,
        hora: hora,
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        precisionMetros: posicion.accuracy,
        capturadoEn: DateTime.now(),
        manual: manual,
      );
      await _db.guardarUbicacion(ubicacion);
      ubicacionesHoy = {...ubicacionesHoy, tipo.name: ubicacion};
    } finally {
      _capturandoUbicacion.remove(tipo);
      notifyListeners();
    }
  }

  Future<void> _recalcularYProgramar({String? nombreParaNotificacion}) async {
    if (registroHoy == null) return;
    registroHoy = registroHoy!.copyWith(
      minutosCumplidos: minutosTrabajadosHastaAhora,
    );
    await _db.guardarRegistro(registroHoy!);
    notifyListeners();

    if (salidaReal != null) {
      await NotificationService.instance.cancelarRecordatorioSalida();
      return;
    }

    final salida = horaEstimadaSalidaDateTime;
    if (salida != null && nombreParaNotificacion != null) {
      await NotificationService.instance.programarRecordatorioSalida(
        horaEstimadaSalida: salida,
        nombre: nombreParaNotificacion,
      );
    } else if (salida == null) {
      await NotificationService.instance.cancelarRecordatorioSalida();
    }
  }
}
