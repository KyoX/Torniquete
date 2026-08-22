import 'package:flutter/material.dart';

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
  double metaLJHoras = PrefsService.defaultMetaLJ;
  double metaViernesHoras = PrefsService.defaultMetaViernes;

  /// Si está activo, cada marca guarda también dónde se registró.
  bool guardarUbicacion = false;

  /// Avisos para no olvidar marcar, por tipo de marca.
  Map<RecordatorioTipo, RecordatorioConfig> recordatorios = const {};

  /// Dónde queda el trabajo y con qué radio de tolerancia.
  SedeConfig sede = const SedeConfig();

  /// Si la app reconoce los asuetos de ley de El Salvador.
  bool asuetosActivos = true;

  /// Régimen de asuetos que aplica al usuario.
  SectorLaboral sector = SectorLaboral.privado;

  bool cargado = false;

  Future<bool> tieneUsuarioConfigurado() => _prefsService.tieneUsuario();

  Future<void> cargar() async {
    nombre = await _prefsService.getNombre();
    metaLJHoras = await _prefsService.getMetaLJ();
    metaViernesHoras = await _prefsService.getMetaViernes();
    guardarUbicacion = await _prefsService.getGuardarUbicacion();
    recordatorios = await _prefsService.getRecordatorios();
    sede = await _prefsService.getSede();
    asuetosActivos = await _prefsService.getAsuetosActivos();
    sector = await _prefsService.getSector();
    modoTema = await _prefsService.getModoTema();
    fondoWidget = await _prefsService.getFondoWidget();
    cargado = true;
    notifyListeners();
  }

  Future<void> guardarConfiguracion({
    required String nombre,
    required double metaLJHoras,
    required double metaViernesHoras,
  }) async {
    await _prefsService.guardarConfiguracion(
      nombre: nombre,
      metaLJ: metaLJHoras,
      metaViernes: metaViernesHoras,
    );
    this.nombre = nombre.trim();
    this.metaLJHoras = metaLJHoras;
    this.metaViernesHoras = metaViernesHoras;
    cargado = true;
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
      );
    } else {
      await servicio.cancelarRecordatorioMarca(config.tipo);
    }
  }

  Future<void> guardarSede(SedeConfig nueva) async {
    await _prefsService.guardarSede(nueva);
    sede = await _prefsService.getSede();
    notifyListeners();
  }

  Future<void> borrarSede() async {
    await _prefsService.borrarSede();
    sede = await _prefsService.getSede();
    notifyListeners();
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
  int metaMinutosParaDia(int weekday) {
    final horas = weekday == DateTime.friday ? metaViernesHoras : metaLJHoras;
    return (horas * 60).round();
  }

  /// Meta de un día laboral típico, para traducir el banco de horas a días.
  int get metaDiariaTipicaMinutos => (metaLJHoras * 60).round();
}
