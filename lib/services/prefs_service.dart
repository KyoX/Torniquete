import 'package:shared_preferences/shared_preferences.dart';

/// Acceso centralizado a SharedPreferences para los datos de configuración
/// del usuario (nombre y metas de horas).
class PrefsService {
  static const _keyNombre = 'nombre_usuario';
  static const _keyMetaLJ = 'meta_lj_horas';
  static const _keyMetaViernes = 'meta_viernes_horas';
  static const _keyGuardarUbicacion = 'guardar_ubicacion';

  static const double defaultMetaLJ = 8.5;
  static const double defaultMetaViernes = 6.5;

  Future<bool> tieneUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString(_keyNombre);
    return nombre != null && nombre.trim().isNotEmpty;
  }

  Future<String?> getNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNombre);
  }

  Future<double> getMetaLJ() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyMetaLJ) ?? defaultMetaLJ;
  }

  Future<double> getMetaViernes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyMetaViernes) ?? defaultMetaViernes;
  }

  /// Desactivado por defecto: la ubicación solo se guarda si el usuario
  /// lo habilita expresamente en Ajustes.
  Future<bool> getGuardarUbicacion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGuardarUbicacion) ?? false;
  }

  Future<void> setGuardarUbicacion(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuardarUbicacion, valor);
  }

  Future<void> guardarConfiguracion({
    required String nombre,
    required double metaLJ,
    required double metaViernes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre.trim());
    await prefs.setDouble(_keyMetaLJ, metaLJ);
    await prefs.setDouble(_keyMetaViernes, metaViernes);
  }
}
