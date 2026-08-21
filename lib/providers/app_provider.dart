import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

/// Estado global de configuración del usuario: nombre y metas de horas.
class AppProvider extends ChangeNotifier {
  final PrefsService _prefsService = PrefsService();

  String? nombre;
  double metaLJHoras = PrefsService.defaultMetaLJ;
  double metaViernesHoras = PrefsService.defaultMetaViernes;

  /// Si está activo, cada marca guarda también dónde se registró.
  bool guardarUbicacion = false;
  bool cargado = false;

  Future<bool> tieneUsuarioConfigurado() => _prefsService.tieneUsuario();

  Future<void> cargar() async {
    nombre = await _prefsService.getNombre();
    metaLJHoras = await _prefsService.getMetaLJ();
    metaViernesHoras = await _prefsService.getMetaViernes();
    guardarUbicacion = await _prefsService.getGuardarUbicacion();
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

  /// Meta de minutos para el día de la semana indicado (1 = lunes ... 7 = domingo).
  int metaMinutosParaDia(int weekday) {
    final horas = weekday == DateTime.friday ? metaViernesHoras : metaLJHoras;
    return (horas * 60).round();
  }
}
