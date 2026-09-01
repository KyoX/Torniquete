import 'package:flutter/foundation.dart';

import '../services/geocerca_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';

/// Estado global de configuración del usuario: nombre, metas de horas,
/// recordatorios de marca y geocerca de la sede.
class AppProvider extends ChangeNotifier {
  /// El tema llega ya leído desde main() para que la app no arranque en
  /// claro y salte a oscuro un instante después.
  AppProvider({this.modoTema = ModoTema.sistema});

  final PrefsService _prefsService = PrefsService();

  /// Claro, oscuro o el del teléfono.
  ModoTema modoTema;

  /// Cuánto se ve el fondo de pantalla a través del widget de inicio.
  FondoWidget fondoWidget = FondoWidget.solido;

  String? nombre;

  /// Las horas que se esperan de cada día de la semana.
  MetasSemana metas = MetasSemana.clasica();

  /// Si está activo, cada marca guarda también dónde se registró.
  bool guardarUbicacion = false;

  /// Minutos de almuerzo que la empresa descuenta aunque no se tomen. Cero
  /// deja el cálculo como estaba: cuenta el almuerzo que se tomó de verdad.
  int descuentoAlmuerzoMinutos = 0;

  /// Avisos para no olvidar marcar, por tipo de marca.
  Map<RecordatorioTipo, RecordatorioConfig> recordatorios = const {};

  /// Dónde queda el trabajo y con qué radio de tolerancia.
  SedeConfig sede = const SedeConfig();

  /// Segunda sede, opcional: otra oficina, un coworking, una sucursal.
  SedeSecundaria sede2 = const SedeSecundaria();

  /// Si la app reconoce los asuetos de ley de El Salvador.
  bool asuetosActivos = true;

  /// Régimen de asuetos que aplica al usuario.
  SectorLaboral sector = SectorLaboral.privado;

  bool cargado = false;

  Future<bool> tieneUsuarioConfigurado() => _prefsService.tieneUsuario();

  Future<void> cargar() async {
    nombre = await _prefsService.getNombre();
    metas = await _prefsService.getMetas();
    guardarUbicacion = await _prefsService.getGuardarUbicacion();
    descuentoAlmuerzoMinutos = await _prefsService.getDescuentoAlmuerzo();
    recordatorios = await _prefsService.getRecordatorios();
    sede = await _prefsService.getSede();
    sede2 = await _prefsService.getSede2();
    asuetosActivos = await _prefsService.getAsuetosActivos();
    sector = await _prefsService.getSector();
    modoTema = await _prefsService.getModoTema();
    fondoWidget = await _prefsService.getFondoWidget();
    cargado = true;
    notifyListeners();
    // Android olvida las geocercas al reiniciarse y al actualizar la app. El
    // receptor de arranque las repone, pero no todos los fabricantes lo
    // entregan, así que abrir la app también las deja en su sitio.
    await resincronizarGeocerca();
  }

  /// Vuelve a pedirle al sistema la vigilancia de llegada con la sede que hay
  /// guardada ahora. Es idempotente y barato, así que se puede llamar cada
  /// vez que la app vuelve a primer plano: es lo que hace que conceder el
  /// permiso desde los ajustes de Android surta efecto sin reiniciar nada.
  Future<bool> resincronizarGeocerca() =>
      GeocercaService.instance.configurarSede(sede, sede2: sede2);

  Future<void> guardarConfiguracion({
    required String nombre,
    required MetasSemana metas,
  }) async {
    await _prefsService.guardarConfiguracion(nombre: nombre, metas: metas);
    this.nombre = nombre.trim();
    this.metas = metas;
    cargado = true;
    notifyListeners();
  }

  Future<void> setNombre(String valor) async {
    await _prefsService.setNombre(valor);
    nombre = valor.trim();
    cargado = true;
    notifyListeners();
  }

  /// Cambia la meta de un día de la semana.
  ///
  /// Solo manda sobre los días que se registren a partir de ahora y sobre el
  /// de hoy, que el dashboard vuelve a igualar al recargar: cada día guarda
  /// la meta con la que se trabajó, así que cambiar la del miércoles no
  /// reescribe los miércoles ya pasados.
  Future<void> setMetaDelDia(int weekday, double horas) async {
    final nuevas = metas.conDia(weekday, horas);
    if (nuevas == metas) return;
    await _prefsService.guardarMetas(nuevas);
    metas = nuevas;
    notifyListeners();
  }

  /// Cambia el descuento fijo de almuerzo. Solo afecta a los días que se
  /// registren a partir de ahora: cada día guarda el descuento con el que se
  /// trabajó, igual que guarda su meta.
  Future<void> setDescuentoAlmuerzo(int minutos) async {
    await _prefsService.setDescuentoAlmuerzo(minutos);
    descuentoAlmuerzoMinutos = await _prefsService.getDescuentoAlmuerzo();
    notifyListeners();
  }

  Future<void> setGuardarUbicacion(bool valor) async {
    await _prefsService.setGuardarUbicacion(valor);
    guardarUbicacion = valor;
    notifyListeners();
  }

  /// Guarda un recordatorio y lo aplica al instante.
  ///
  /// El aviso de hoy no se omite aquí: desde Ajustes no se sabe si la marca
  /// ya está hecha. El dashboard afina eso al recargar, que es justo lo que
  /// ocurre al volver de esta pantalla.
  Future<void> guardarRecordatorio(RecordatorioConfig config) async {
    await _prefsService.guardarRecordatorio(config);
    recordatorios = {...recordatorios, config.tipo: config};
    notifyListeners();

    final servicio = NotificationService.instance;
    if (config.activo) {
      await servicio.programarRecordatorioMarca(
        tipo: config.tipo,
        minutosDelDia: config.minutos,
        dias: sede.diasOficina,
      );
    } else {
      await servicio.cancelarRecordatorioMarca(config.tipo);
    }
  }

  /// Reprograma todos los recordatorios encendidos con los días de trabajo
  /// que hay guardados ahora.
  ///
  /// Hace falta al cambiar la semana de oficina: las citas ya agendadas son
  /// fechas concretas, así que quitar el lunes no borra por sí solo el aviso
  /// del lunes que viene.
  Future<void> _reprogramarRecordatorios() async {
    final servicio = NotificationService.instance;
    for (final config in recordatorios.values) {
      if (!config.activo) continue;
      await servicio.programarRecordatorioMarca(
        tipo: config.tipo,
        minutosDelDia: config.minutos,
        dias: sede.diasOficina,
      );
    }
  }

  /// Guarda la sede y le pasa al sistema la zona a vigilar. Devuelve true si
  /// al terminar Android está vigilando de verdad: con el aviso de llegada
  /// apagado, sin coordenadas o sin el permiso de fondo devuelve false, que
  /// es lo que la pantalla necesita para no prometer lo que no hay.
  Future<bool> guardarSede(SedeConfig nueva) async {
    final diasAntes = sede.diasOficina;
    await _prefsService.guardarSede(nueva);
    sede = await _prefsService.getSede();
    notifyListeners();
    if (!setEquals(diasAntes, sede.diasOficina)) {
      await _reprogramarRecordatorios();
    }
    return resincronizarGeocerca();
  }

  Future<void> borrarSede() async {
    await _prefsService.borrarSede();
    sede = await _prefsService.getSede();
    notifyListeners();
    await _reprogramarRecordatorios();
    await resincronizarGeocerca();
  }

  /// Guarda la segunda sede y le pasa al sistema las zonas a vigilar. A
  /// diferencia de [guardarSede], no toca los recordatorios: la segunda sede
  /// no tiene días propios, así que no puede cambiarlos.
  Future<bool> guardarSede2(SedeSecundaria nueva) async {
    await _prefsService.guardarSede2(nueva);
    sede2 = await _prefsService.getSede2();
    notifyListeners();
    return resincronizarGeocerca();
  }

  Future<void> borrarSede2() async {
    await _prefsService.borrarSede2();
    sede2 = await _prefsService.getSede2();
    notifyListeners();
    await resincronizarGeocerca();
  }

  Future<void> setAsuetosActivos(bool valor) async {
    await _prefsService.setAsuetosActivos(valor);
    asuetosActivos = valor;
    notifyListeners();
  }

  Future<void> setModoTema(ModoTema valor) async {
    if (valor == modoTema) return;
    modoTema = valor;
    // Se repinta ya y se guarda después: esperar al disco dejaría el ajuste
    // sin responder durante un instante.
    notifyListeners();
    await _prefsService.setModoTema(valor);
  }

  /// Cambia el fondo del widget y se lo pide repintar a Android. La
  /// preferencia se guarda dos veces a propósito: aquí para que la app la
  /// recuerde, y en las del widget, que es de donde la lee Kotlin.
  Future<void> setFondoWidget(FondoWidget valor) async {
    if (valor == fondoWidget) return;
    fondoWidget = valor;
    notifyListeners();
    await _prefsService.setFondoWidget(valor);
    await WidgetService.instance.actualizarFondo(valor);
  }

  Future<void> setSector(SectorLaboral valor) async {
    await _prefsService.setSector(valor);
    sector = valor;
    notifyListeners();
  }

  /// El sector a usar para los cálculos, o null si el usuario apagó los
  /// asuetos automáticos. Los servicios lo reciben así para saber de una vez
  /// si deben tener en cuenta el calendario o ignorarlo.
  SectorLaboral? get sectorAsuetos => asuetosActivos ? sector : null;

  /// El asueto que cae en [fecha], si los asuetos están activos.
  Asueto? asuetoEn(DateTime fecha) {
    final s = sectorAsuetos;
    return s == null ? null : FestivosSV.enFecha(fecha, sector: s);
  }

  /// Igual que [asuetoEn] pero desde la fecha en 'yyyy-MM-dd'.
  Asueto? asuetoEnClave(String fecha) {
    final s = sectorAsuetos;
    return s == null ? null : FestivosSV.enClave(fecha, sector: s);
  }

  /// Meta de minutos para el día de la semana indicado (1 = lunes ... 7 = domingo).
  int metaMinutosParaDia(int weekday) => metas.minutosDe(weekday);

  /// Meta de un día laboral típico, para traducir el banco de horas a días.
  int get metaDiariaTipicaMinutos => metas.minutosDiaTipico;
}
