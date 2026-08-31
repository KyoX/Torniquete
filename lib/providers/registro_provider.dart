import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pausa.dart';
import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../models/ubicacion_marca.dart';
import '../services/db_service.dart';
import '../services/geocerca_service.dart';
import '../services/jornadas_abiertas_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/pausas_service.dart';
import '../services/prefs_service.dart';
import '../services/reports_service.dart';
import '../services/widget_service.dart';
import '../utils/geo_utils.dart';
import '../utils/time_utils.dart';

/// Las marcas que el usuario puede registrar.
///
/// [pausa] y [reanudar] no apuntan a un hueco fijo del día: abren y cierran
/// la pausa que toque, y un día puede tener varias.
enum MarcaTipo { entrada1, pausa, reanudar, salidaReal }

/// Claves con las que se guarda la evidencia de ubicación de cada marca.
///
/// Las del almuerzo conservan el nombre que tenían cuando eran marcas fijas
/// del día para no dejar huérfana la evidencia ya guardada.
class ClaveUbicacion {
  const ClaveUbicacion._();

  static const String entrada = 'entrada1';
  static const String salidaReal = 'salidaReal';
  static const String almuerzoInicio = 'salida1';
  static const String almuerzoFin = 'entrada2';
}

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

  /// Jornadas de días anteriores que quedaron sin salida confirmada.
  ///
  /// Se revisa al cargar el día porque es entonces cuando se puede saber:
  /// mientras el día corre, la salida que falta es normal.
  List<JornadaAbierta> jornadasAbiertas = const [];

  /// Marcas cuya ubicación se está capturando en este momento, por clave.
  final Set<String> _capturandoUbicacion = {};

  bool capturandoUbicacion(String clave) =>
      _capturandoUbicacion.contains(clave);

  UbicacionMarca? ubicacionDe(String clave) => ubicacionesHoy[clave];

  /// Qué tan lejos de la sede quedó una marca. Null si la geocerca está
  /// apagada o si esa marca no tiene ubicación guardada.
  EvaluacionGeocerca? geocercaDe(String clave) {
    final ubicacion = ubicacionDe(clave);
    if (ubicacion == null) return null;
    return LocationService.instance.evaluarSede(
      sede,
      latitud: ubicacion.latitud,
      longitud: ubicacion.longitud,
    );
  }

  /// Todo lo que se sabe de dónde se registró una marca, listo para la
  /// fila que la muestra.
  EvidenciaMarca evidenciaDe(String clave) => EvidenciaMarca(
        ubicacion: ubicacionDe(clave),
        capturando: capturandoUbicacion(clave),
        geocerca: geocercaDe(clave),
      );

  /// Marca el aviso como ya mostrado. No notifica a propósito: se llama
  /// desde un listener del propio provider y no hay nada que redibujar.
  void limpiarAvisoGeocerca() => avisoGeocerca = null;

  static String fechaHoy() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Qué marca ofrecería el aviso de llegada para [registro], o null si no
  /// hay ninguna que ofrecer.
  ///
  /// Es la única definición de "qué falta marcar al llegar" de toda la app:
  /// el lado nativo no la recalcula, solo lee el resultado que se le deja
  /// escrito, porque tiene que poder preguntar con la app cerrada.
  ///
  /// Reanudar solo se ofrece si hay una pausa abierta. Sin esa condición,
  /// cualquier vuelta al radio a media mañana —salir por un café, registrar
  /// la geocerca otra vez estando ya en la oficina— preguntaría a destiempo.
  /// Quien olvida marcar la pausa tiene el recordatorio de marca para eso.
  static MarcaTipo? marcaSugeridaAlLlegar(Registro? registro) {
    if (registro == null) return null;
    // Un festivo o un día de vacaciones no espera marcas, y una jornada ya
    // cerrada tampoco: pasar por la sede después no reabre el día.
    if (registro.tipoDia.esJustificado) return null;
    if (registro.salidaReal != null) return null;
    if (registro.entrada1 == null) return MarcaTipo.entrada1;
    if (registro.pausaAbierta != null) return MarcaTipo.reanudar;
    return null;
  }

  /// Qué marca ofrecería el aviso al salir de la sede, o null si no hay
  /// ninguna que ofrecer.
  ///
  /// La contraria de [marcaSugeridaAlLlegar], y con la misma regla: se
  /// calcula aquí y viaja resuelta al lado nativo, que no sabe nada de la
  /// jornada.
  ///
  /// Una pausa abierta no se ofrece como salida. Quien sale del radio con la
  /// pausa corriendo se fue a comer o a una diligencia, no a su casa; si
  /// resulta que no vuelve, el día queda abierto y lo recoge
  /// [JornadasAbiertasService] al día siguiente, que es el momento en que se
  /// puede saber la diferencia.
  static MarcaTipo? marcaSugeridaAlSalir(Registro? registro) {
    if (registro == null) return null;
    // Sin entrada no hay jornada que cerrar: salir del radio es simplemente
    // irse de un sitio donde hoy no se ha trabajado.
    if (registro.entrada1 == null) return null;
    if (registro.salidaReal != null) return null;
    if (registro.pausaAbierta != null) return null;
    return MarcaTipo.salidaReal;
  }

  /// Cuánto antes de la hora estimada de salida se acepta ya la pregunta.
  ///
  /// Media hora antes una salida es perfectamente creíble —se sale antes, se
  /// va uno a una cita—, y esperar a la hora exacta dejaría sin preguntar
  /// justo a quien más lo necesita.
  static const int margenSalidaMinutos = 30;

  /// A partir de qué minuto del día tiene sentido preguntar si terminó la
  /// jornada, o null si hoy no hay ninguna salida que ofrecer.
  ///
  /// Sin este umbral, cualquier salida del radio a media mañana —una
  /// diligencia, un almuerzo fuera sin marcar la pausa— gastaría en el
  /// momento equivocado la única pregunta que se hace al día.
  static int? minutoParaPreguntarSalida(
    Registro? registro, {
    required int minutosAhora,
  }) {
    if (registro == null || marcaSugeridaAlSalir(registro) == null) return null;
    final estimado = ReportsService.minutoEstimadoSalida(
      registro,
      minutosAhora: minutosAhora,
    );
    if (estimado == null) return null;
    return (estimado - margenSalidaMinutos)
        .clamp(0, JornadasAbiertasService.finDelDia);
  }

  static MarcaTipo? _marcaPorNombre(String nombre) {
    for (final tipo in MarcaTipo.values) {
      if (tipo.name == nombre) return tipo;
    }
    return null;
  }

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
    final descuento = await _prefs.getDescuentoAlmuerzo();
    registroHoy = existente ??
        Registro(
          fecha: fecha,
          metaMinutos: metaMinutos,
          minutosCumplidos: 0,
          descuentoAlmuerzoMinutos: descuento,
        );
    if (existente != null && existente.metaMinutos != metaMinutos) {
      registroHoy = registroHoy!.copyWith(metaMinutos: metaMinutos);
    }
    // El día en curso sigue el ajuste vigente: cambiarlo por la mañana tiene
    // que verse hoy mismo. Los días ya cerrados conservan el suyo.
    if (existente != null && existente.descuentoAlmuerzoMinutos != descuento) {
      registroHoy = registroHoy!.copyWith(descuentoAlmuerzoMinutos: descuento);
    }
    ubicacionesHoy = await _db.getUbicacionesPorFecha(fecha);
    sede = await _prefs.getSede();
    cargando = false;
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
    await revisarJornadasAbiertas();
  }

  /// Busca días anteriores que quedaron con la entrada marcada y sin salida.
  ///
  /// Se consulta el historial entero y no los últimos días: quien lleva
  /// meses con la app puede arrastrar un día abierto de hace mucho, y ese es
  /// justo el que nadie va a encontrar solo.
  Future<void> revisarJornadasAbiertas() async {
    jornadasAbiertas = JornadasAbiertasService.detectar(
      await _db.getTodosLosRegistros(),
      hoy: fechaHoy(),
    );
    notifyListeners();
  }

  /// Cierra a las [hora] una jornada que quedó abierta y recalcula sus horas.
  ///
  /// Es una escritura sobre el pasado, así que solo se llega aquí desde una
  /// confirmación del usuario: la app propone una hora, pero quién trabajó
  /// hasta cuándo no lo sabe nadie más que él.
  Future<void> cerrarJornadaAbierta(String fecha, TimeOfDay hora) async {
    final registro = await _db.getRegistroPorFecha(fecha);
    if (registro == null) return;
    final cerrado =
        registro.copyWith(salidaReal: TimeUtils.formatTimeOfDay(hora));
    await _db.guardarRegistro(
      cerrado.copyWith(
        minutosCumplidos: ReportsService.minutosTrabajados(cerrado),
      ),
    );
    await revisarJornadasAbiertas();
  }

  TimeOfDay? get entrada1 => TimeUtils.parseTimeOfDay(registroHoy?.entrada1);
  TimeOfDay? get salidaReal => TimeUtils.parseTimeOfDay(registroHoy?.salidaReal);

  List<Pausa> get pausas => registroHoy?.pausas ?? const [];

  /// La pausa en curso, si el día está parado ahora mismo.
  Pausa? get pausaAbierta => registroHoy?.pausaAbierta;

  /// La pausa que hace de almuerzo, para poder señalarla en la lista.
  Pausa? get almuerzo => registroHoy?.almuerzo;

  /// Minutos que se lleva fuera del trabajo hoy, con la pausa en curso
  /// contando en vivo.
  int get minutosPausadosHastaAhora => PausasService.minutosPausados(
        pausas,
        hasta: TimeUtils.toMinutes(TimeOfDay.now()),
      );

  TipoDia get tipoDiaHoy => registroHoy?.tipoDia ?? TipoDia.normal;

  /// Hora estimada de salida.
  ///
  /// La entrada, más la meta del día, más todo lo que se ha estado fuera:
  /// cada pausa empuja la salida hacia adelante justo lo que duró. Al
  /// almuerzo que la empresa descuenta y todavía no se ha tomado se le hace
  /// sitio desde el principio, porque va a costar igual se salga o no.
  ///
  /// Mientras la pausa sigue abierta la hora se va corriendo minuto a
  /// minuto: es una estimación de "si vuelves ya y no paras más", y se
  /// corrige sola en cuanto se reanuda.
  TimeOfDay? get horaEstimadaSalida {
    final registro = registroHoy;
    if (registro == null) return null;

    final ahora = TimeUtils.toMinutes(TimeOfDay.now());
    final minuto =
        ReportsService.minutoEstimadoSalida(registro, minutosAhora: ahora);
    return minuto == null ? null : TimeUtils.fromMinutes(minuto);
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

  /// Cambia a mano la hora en que empezó la pausa [indice].
  Future<void> editarInicioPausa(
    int indice,
    TimeOfDay hora, {
    required String nombreUsuario,
  }) =>
      _cambiarPausas(
        (pausas) => pausas[indice] =
            pausas[indice].conInicio(TimeUtils.formatTimeOfDay(hora)),
        indice: indice,
        nombreUsuario: nombreUsuario,
      );

  /// Cambia a mano la hora en que terminó la pausa [indice].
  Future<void> editarFinPausa(
    int indice,
    TimeOfDay hora, {
    required String nombreUsuario,
  }) =>
      _cambiarPausas(
        (pausas) =>
            pausas[indice] = pausas[indice].cerrar(TimeUtils.formatTimeOfDay(hora)),
        indice: indice,
        nombreUsuario: nombreUsuario,
      );

  /// Borra una pausa entera. Lo que duró vuelve a contar como trabajado.
  Future<void> eliminarPausa(int indice, {required String nombreUsuario}) =>
      _cambiarPausas(
        (pausas) => pausas.removeAt(indice),
        nombreUsuario: nombreUsuario,
      );

  /// Aplica un cambio sobre la lista de pausas y vuelve a calcular el día.
  ///
  /// [indice] solo sirve para no tocar nada si la lista cambió por debajo
  /// (dos toques seguidos, una recarga a media edición).
  Future<void> _cambiarPausas(
    void Function(List<Pausa> pausas) cambio, {
    int? indice,
    required String nombreUsuario,
  }) async {
    final registro = registroHoy;
    if (registro == null) return;
    if (indice != null && (indice < 0 || indice >= registro.pausas.length)) {
      return;
    }
    final pausas = [...registro.pausas];
    cambio(pausas);
    registroHoy = registro.copyWith(pausas: Pausa.ordenar(pausas));
    notifyListeners();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
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
    final registro = registroHoy;
    if (registro == null) return;
    final valor = TimeUtils.formatTimeOfDay(hora);
    switch (tipo) {
      case MarcaTipo.entrada1:
        registroHoy = registro.copyWith(entrada1: valor);
        break;
      case MarcaTipo.pausa:
        // Dos pausas abiertas a la vez no significan nada: si ya hay una
        // corriendo, el botón que toca es el de continuar.
        if (registro.pausaAbierta != null) return;
        registroHoy = registro.copyWith(
          pausas: Pausa.ordenar([...registro.pausas, Pausa(inicio: valor)]),
        );
        break;
      case MarcaTipo.reanudar:
        final abierta = registro.pausaAbierta;
        if (abierta == null) return;
        registroHoy = registro.copyWith(
          pausas: [
            for (final pausa in registro.pausas)
              pausa == abierta ? pausa.cerrar(valor) : pausa,
          ],
        );
        break;
      case MarcaTipo.salidaReal:
        registroHoy = registro.copyWith(salidaReal: valor);
        break;
    }
    notifyListeners();
    // El aviso de llegada, si seguía en la barra, ya no tiene nada que
    // preguntar en cuanto la marca existe.
    await GeocercaService.instance.cancelarAviso();
    await _recalcularYProgramar(nombreParaNotificacion: nombreUsuario);
    await _guardarUbicacionDeMarca(tipo, valor, manual: manual);
  }

  /// Con qué clave se guarda la evidencia de ubicación de una marca, o null
  /// si esa marca no lleva evidencia.
  ///
  /// De las pausas solo se guarda la del almuerzo, y bajo las claves de
  /// siempre. Numerarlas ("pausa 2") sería un identificador que cambia solo
  /// en cuanto se borra o se reordena una pausa, y dejaría la evidencia
  /// apuntando al tramo equivocado.
  String? _claveDe(MarcaTipo tipo, String hora) {
    switch (tipo) {
      case MarcaTipo.entrada1:
        return ClaveUbicacion.entrada;
      case MarcaTipo.salidaReal:
        return ClaveUbicacion.salidaReal;
      case MarcaTipo.pausa:
        return registroHoy?.almuerzo?.inicio == hora
            ? ClaveUbicacion.almuerzoInicio
            : null;
      case MarcaTipo.reanudar:
        return registroHoy?.almuerzo?.fin == hora
            ? ClaveUbicacion.almuerzoFin
            : null;
    }
  }

  /// Deja constancia de dónde estaba el usuario al registrar la marca.
  /// Es totalmente opcional: si el ajuste está apagado, el permiso no está
  /// concedido o el GPS falla, la marca queda igual y sin ubicación.
  Future<void> _guardarUbicacionDeMarca(
    MarcaTipo tipo,
    String hora, {
    required bool manual,
  }) async {
    final registro = registroHoy;
    if (registro == null) return;
    final clave = _claveDe(tipo, hora);
    if (clave == null) return;
    if (!await _prefs.getGuardarUbicacion()) return;

    _capturandoUbicacion.add(clave);
    notifyListeners();
    try {
      final posicion = await LocationService.instance.capturar();
      if (posicion == null) return;
      final ubicacion = UbicacionMarca(
        fecha: registro.fecha,
        tipo: clave,
        hora: hora,
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        precisionMetros: posicion.accuracy,
        capturadoEn: DateTime.now(),
        manual: manual,
      );
      await _db.guardarUbicacion(ubicacion);
      ubicacionesHoy = {...ubicacionesHoy, clave: ubicacion};
      _revisarGeocerca(ubicacion, manual: manual);
    } finally {
      _capturandoUbicacion.remove(clave);
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
    await _sincronizarGeocerca();
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

  /// Le deja al sistema, por si la llegada o la salida ocurren con la app
  /// cerrada, la fecha del día en curso y lo que tocaría ofrecer en cada
  /// caso.
  Future<void> _sincronizarGeocerca() async {
    final registro = registroHoy;
    await GeocercaService.instance.actualizarDia(
      fecha: registro?.fecha ?? fechaHoy(),
      marcaSugerida: marcaSugeridaAlLlegar(registro)?.name,
      marcaSalida: marcaSugeridaAlSalir(registro)?.name,
      salidaDesdeMinuto: minutoParaPreguntarSalida(
        registro,
        minutosAhora: TimeUtils.toMinutes(TimeOfDay.now()),
      ),
    );
  }

  /// Registra la marca que el usuario aceptó en el aviso de llegada, si hay
  /// alguna esperando. Devuelve cuál se registró y a qué hora, o null si no
  /// había nada que hacer.
  ///
  /// La hora que queda registrada es la del toque en la notificación, no la
  /// de ahora: entre tocar y que la app termine de abrirse pueden pasar
  /// varios segundos, y la marca debe decir cuándo se llegó.
  Future<({MarcaTipo tipo, String hora})?> registrarMarcaAceptada({
    required String nombreUsuario,
  }) async {
    // Se comprueba antes de consumir: el lado nativo la entrega una sola vez,
    // y recogerla sin tener dónde escribirla la perdería.
    if (registroHoy == null) return null;
    final aceptada = await GeocercaService.instance.consumirMarcaPendiente();
    if (aceptada == null) return null;

    final tipo = _marcaPorNombre(aceptada.tipo);
    if (tipo == null) return null;
    // Una marca de ayer que se quedó sin recoger (el teléfono se apagó, la
    // app no se abrió) no se arrastra al día de hoy.
    if (DateFormat('yyyy-MM-dd').format(aceptada.cuando) != registroHoy!.fecha) {
      return null;
    }
    // Si mientras tanto se marcó a mano, manda lo que ya está guardado: la
    // marca aceptada solo vale si sigue siendo la que falta.
    if (!_sigueHaciendoFalta(tipo)) return null;

    final hora = TimeOfDay.fromDateTime(aceptada.cuando);
    await _setMarca(tipo, hora, nombreUsuario: nombreUsuario);
    return (tipo: tipo, hora: TimeUtils.formatTimeOfDay(hora));
  }

  /// True si [tipo] sigue siendo lo que la jornada espera.
  ///
  /// La entrada y la reanudación se validan contra la regla del aviso de
  /// llegada, y la salida contra la del aviso de salida. La pausa no la
  /// ofrece ningún aviso de la sede —lo explica [marcaSugeridaAlLlegar]—,
  /// pero sí la ofrecen el widget y la ficha de Ajustes rápidos, así que
  /// aquí se valida con la misma condición que usa [_setMarca] para
  /// descartarla en silencio: sin pausa ya abierta.
  bool _sigueHaciendoFalta(MarcaTipo tipo) {
    final registro = registroHoy;
    if (registro == null) return false;
    switch (tipo) {
      case MarcaTipo.salidaReal:
        return marcaSugeridaAlSalir(registro) == tipo;
      case MarcaTipo.pausa:
        return registro.entrada1 != null &&
            registro.salidaReal == null &&
            registro.pausaAbierta == null;
      case MarcaTipo.entrada1:
      case MarcaTipo.reanudar:
        return marcaSugeridaAlLlegar(registro) == tipo;
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
  ///
  /// La sede se relee en vez de usar la del provider: los días de trabajo se
  /// cambian desde Ajustes, y el aviso tiene que respetar el último valor.
  Future<void> _reprogramarRecordatoriosDeMarca() async {
    final configs = await _prefs.getRecordatorios();
    final dias = (await _prefs.getSede()).diasOficina;
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
        dias: dias,
      );
    }
  }

  bool _marcaYaHecha(RecordatorioTipo tipo) {
    switch (tipo) {
      case RecordatorioTipo.entrada:
        return registroHoy?.entrada1 != null;
      case RecordatorioTipo.salidaAlmuerzo:
        // Basta con que ya haya una pausa en la franja del almuerzo, esté
        // abierta o cerrada.
        return registroHoy?.almuerzo != null;
      case RecordatorioTipo.regresoAlmuerzo:
        // Sin pausa abierta no hay nada que reanudar: o ya se volvió o no se
        // llegó a salir.
        return registroHoy?.pausaAbierta == null;
      case RecordatorioTipo.confirmarSalida:
        // Sin entrada no hay día que cerrar, y con salida ya está cerrado:
        // en los dos casos sobra el aviso. Solo suena con el día a medias.
        return registroHoy?.entrada1 == null || registroHoy?.salidaReal != null;
    }
  }
}
