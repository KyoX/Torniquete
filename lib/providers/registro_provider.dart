import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../models/ubicacion_marca.dart';
import '../services/db_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../services/reports_service.dart';
import '../services/widget_service.dart';
import '../utils/geo_utils.dart';
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

  /// Configuración de la sede, para comparar cada marca contra la geocerca.
  SedeConfig sede = const SedeConfig();

  /// Aviso pendiente de mostrar cuando una marca cae fuera de la sede.
  /// La pantalla lo consume con [limpiarAvisoGeocerca].
  String? avisoGeocerca;

  /// Tipos de marca cuya ubicación se está capturando en este momento.
  final Set<MarcaTipo> _capturandoUbicacion = {};

  bool capturandoUbicacion(MarcaTipo tipo) =>
      _capturandoUbicacion.contains(tipo);

  UbicacionMarca? ubicacionDe(MarcaTipo tipo) => ubicacionesHoy[tipo.name];

  /// Qué tan lejos de la sede quedó una marca. Null si la geocerca está
  /// apagada o si esa marca no tiene ubicación guardada.
  EvaluacionGeocerca? geocercaDe(MarcaTipo tipo) {
    final ubicacion = ubicacionDe(tipo);
    if (ubicacion == null) return null;
    return LocationService.instance.evaluarSede(
      sede,
      latitud: ubicacion.latitud,
      longitud: ubicacion.longitud,
    );
  }

  /// Marca el aviso como ya mostrado. No notifica a propósito: se llama
  /// desde un listener del propio provider y no hay nada que redibujar.
  void limpiarAvisoGeocerca() => avisoGeocerca = null;

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
    sede = await _prefs.getSede();
    cargando = false;
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
  }

  TimeOfDay? get entrada1 => TimeUtils.parseTimeOfDay(registroHoy?.entrada1);
  TimeOfDay? get salida1 => TimeUtils.parseTimeOfDay(registroHoy?.salida1);
  TimeOfDay? get entrada2 => TimeUtils.parseTimeOfDay(registroHoy?.entrada2);
  TimeOfDay? get salidaReal => TimeUtils.parseTimeOfDay(registroHoy?.salidaReal);

  TipoDia get tipoDiaHoy => registroHoy?.tipoDia ?? TipoDia.normal;

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
    return registroHoy!.metaEfectivaMinutos - trabajado;
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

  /// Minutos trabajados hasta ahora. Cada tramo (mañana y tarde) se cierra
  /// con su marca de salida si ya existe; si no, cuenta en vivo contra la
  /// hora actual del dispositivo. Así el progreso avanza desde la entrada
  /// de la mañana y no se queda en cero hasta salir a almorzar.
  int get minutosTrabajadosHastaAhora {
    final registro = registroHoy;
    if (registro == null) return 0;
    return ReportsService.minutosEnVivo(
      registro,
      TimeUtils.toMinutes(TimeOfDay.now()),
    );
  }

  double get progreso {
    final meta = registroHoy?.metaEfectivaMinutos ?? 0;
    // Un día justificado no pide horas: si se trabajó algo, todo es extra y
    // la barra se muestra llena en vez de clavada en cero.
    if (meta <= 0) return minutosTrabajadosHastaAhora > 0 ? 1.0 : 0.0;
    return (minutosTrabajadosHastaAhora / meta).clamp(0.0, 1.0);
  }

  bool get metaCumplida {
    final registro = registroHoy;
    if (registro == null) return false;
    if (registro.tipoDia.esJustificado) return true;
    return minutosTrabajadosHastaAhora >= registro.metaEfectivaMinutos;
  }

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

  /// Marca hoy como festivo, vacaciones, incapacidad o permiso. El día deja
  /// de exigir meta, así que también se cancela el aviso de salida.
  Future<void> cambiarTipoDia(
    TipoDia tipo, {
    String? nota,
    required String nombreUsuario,
  }) async {
    if (registroHoy == null) return;
    registroHoy = registroHoy!.copyWith(
      tipoDia: tipo,
      nota: nota,
      clearNota: nota == null || nota.trim().isEmpty,
    );
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
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
      _revisarGeocerca(ubicacion, manual: manual);
    } finally {
      _capturandoUbicacion.remove(tipo);
      notifyListeners();
    }
  }

  /// Compara la marca recién guardada contra la geocerca de la sede y prepara
  /// el aviso si quedó fuera.
  ///
  /// Es solo un aviso: la marca se guarda igual. La app no sabe si el usuario
  /// está en una sede distinta, en una visita a cliente o si el GPS se
  /// equivocó, así que no le corresponde bloquear nada.
  void _revisarGeocerca(UbicacionMarca ubicacion, {required bool manual}) {
    final evaluacion = LocationService.instance.evaluarSede(
      sede,
      latitud: ubicacion.latitud,
      longitud: ubicacion.longitud,
    );
    if (evaluacion == null || evaluacion.dentro) {
      avisoGeocerca = null;
      return;
    }
    final donde = sede.nombre?.trim().isNotEmpty == true
        ? sede.nombre!.trim()
        : 'la sede';
    avisoGeocerca = manual
        ? 'Marca registrada a ${evaluacion.distanciaLegible} de $donde '
            '(la ubicación es la de ahora, no la de la hora que escribiste).'
        : 'Marca registrada a ${evaluacion.distanciaLegible} de $donde.';
  }

  Future<void> _recalcularYProgramar({String? nombreParaNotificacion}) async {
    if (registroHoy == null) return;
    registroHoy = registroHoy!.copyWith(
      minutosCumplidos: minutosTrabajadosHastaAhora,
    );
    await _db.guardarRegistro(registroHoy!);
    notifyListeners();

    await _actualizarWidget();
    await _reprogramarRecordatoriosDeMarca();

    // En un día justificado no hay meta que cumplir ni salida que anunciar.
    if (salidaReal != null || registroHoy!.tipoDia.esJustificado) {
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

  Future<void> _actualizarWidget() async {
    await WidgetService.instance.actualizar(
      WidgetService.resumir(
        registro: registroHoy,
        horaEstimadaSalida: horaEstimadaSalida,
        ahora: DateTime.now(),
      ),
    );
  }

  /// Vuelve a calcular los avisos de marca. Se rehacen en cada cambio porque
  /// el aviso de hoy sobra en cuanto la marca correspondiente ya está hecha.
  Future<void> _reprogramarRecordatoriosDeMarca() async {
    final configs = await _prefs.getRecordatorios();
    final servicio = NotificationService.instance;
    // Un festivo o un día de vacaciones no necesita que le recuerden marcar.
    final justificado = registroHoy?.tipoDia.esJustificado ?? false;

    for (final config in configs.values) {
      if (!config.activo) {
        await servicio.cancelarRecordatorioMarca(config.tipo);
        continue;
      }
      await servicio.programarRecordatorioMarca(
        tipo: config.tipo,
        minutosDelDia: config.minutos,
        omitirHoy: justificado || _marcaYaHecha(config.tipo),
      );
    }
  }

  bool _marcaYaHecha(RecordatorioTipo tipo) {
    switch (tipo) {
      case RecordatorioTipo.entrada:
        return registroHoy?.entrada1 != null;
      case RecordatorioTipo.salidaAlmuerzo:
        return registroHoy?.salida1 != null;
      case RecordatorioTipo.regresoAlmuerzo:
        return registroHoy?.entrada2 != null;
    }
  }
}
