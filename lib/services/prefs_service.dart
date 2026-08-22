import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import 'widget_service.dart';

/// Marcas del día que la app puede recordar. Cada una tiene su hora sugerida
/// y su propio rango de identificadores de notificación.
enum RecordatorioTipo {
  entrada('entrada', 'Marcar entrada', 7 * 60 + 50),
  salidaAlmuerzo('salida_almuerzo', 'Salir a almorzar', 12 * 60),
  regresoAlmuerzo('regreso_almuerzo', 'Volver del almuerzo', 13 * 60);

  const RecordatorioTipo(this.clave, this.etiqueta, this.minutosPorDefecto);

  final String clave;
  final String etiqueta;

  /// Hora sugerida, en minutos desde medianoche.
  final int minutosPorDefecto;
}

/// Estado de un recordatorio: si está activo y a qué hora suena.
class RecordatorioConfig {
  final RecordatorioTipo tipo;
  final bool activo;

  /// Minutos desde medianoche.
  final int minutos;

  const RecordatorioConfig({
    required this.tipo,
    required this.activo,
    required this.minutos,
  });

  RecordatorioConfig copyWith({bool? activo, int? minutos}) =>
      RecordatorioConfig(
        tipo: tipo,
        activo: activo ?? this.activo,
        minutos: minutos ?? this.minutos,
      );
}

/// Ubicación de la sede y radio dentro del cual se considera que la marca
/// se hizo "en el trabajo".
class SedeConfig {
  final bool activa;
  final double? latitud;
  final double? longitud;
  final int radioMetros;
  final String? nombre;

  const SedeConfig({
    this.activa = false,
    this.latitud,
    this.longitud,
    this.radioMetros = defaultRadioMetros,
    this.nombre,
  });

  static const int defaultRadioMetros = 200;

  /// Un radio muy pequeño produce falsas alertas: el GPS de un teléfono
  /// dentro de un edificio se desvía decenas de metros con facilidad.
  static const int minRadioMetros = 50;
  static const int maxRadioMetros = 2000;

  bool get tieneCoordenadas => latitud != null && longitud != null;

  /// Solo se puede vigilar la geocerca si está encendida y ya se guardó
  /// dónde queda la sede.
  bool get vigente => activa && tieneCoordenadas;

  SedeConfig copyWith({
    bool? activa,
    double? latitud,
    double? longitud,
    int? radioMetros,
    String? nombre,
  }) =>
      SedeConfig(
        activa: activa ?? this.activa,
        latitud: latitud ?? this.latitud,
        longitud: longitud ?? this.longitud,
        radioMetros: radioMetros ?? this.radioMetros,
        nombre: nombre ?? this.nombre,
      );
}

/// Acceso centralizado a SharedPreferences para los datos de configuración
/// del usuario (nombre, metas de horas, recordatorios y geocerca).
class PrefsService {
  static const _keyNombre = 'nombre_usuario';
  static const _keyMetaLJ = 'meta_lj_horas';
  static const _keyMetaViernes = 'meta_viernes_horas';
  static const _keyGuardarUbicacion = 'guardar_ubicacion';
  static const _keySedeActiva = 'sede_activa';
  static const _keySedeLat = 'sede_latitud';
  static const _keySedeLon = 'sede_longitud';
  static const _keySedeRadio = 'sede_radio_m';
  static const _keySedeNombre = 'sede_nombre';
  static const _keyAsuetosActivos = 'asuetos_activos';
  static const _keySector = 'sector_laboral';
  static const _keyModoTema = 'modo_tema';
  static const _keyFondoWidget = 'fondo_widget';

  static const double defaultMetaLJ = 8.5;
  static const double defaultMetaViernes = 6.5;

  static String _keyRecordatorioActivo(RecordatorioTipo t) =>
      'recordatorio_${t.clave}_activo';
  static String _keyRecordatorioMinutos(RecordatorioTipo t) =>
      'recordatorio_${t.clave}_min';

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

  /// Todos los recordatorios de marca, apagados por defecto.
  Future<Map<RecordatorioTipo, RecordatorioConfig>> getRecordatorios() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final tipo in RecordatorioTipo.values)
        tipo: RecordatorioConfig(
          tipo: tipo,
          activo: prefs.getBool(_keyRecordatorioActivo(tipo)) ?? false,
          minutos: prefs.getInt(_keyRecordatorioMinutos(tipo)) ??
              tipo.minutosPorDefecto,
        ),
    };
  }

  Future<void> guardarRecordatorio(RecordatorioConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRecordatorioActivo(config.tipo), config.activo);
    await prefs.setInt(_keyRecordatorioMinutos(config.tipo), config.minutos);
  }

  Future<SedeConfig> getSede() async {
    final prefs = await SharedPreferences.getInstance();
    return SedeConfig(
      activa: prefs.getBool(_keySedeActiva) ?? false,
      latitud: prefs.getDouble(_keySedeLat),
      longitud: prefs.getDouble(_keySedeLon),
      radioMetros:
          prefs.getInt(_keySedeRadio) ?? SedeConfig.defaultRadioMetros,
      nombre: prefs.getString(_keySedeNombre),
    );
  }

  Future<void> guardarSede(SedeConfig sede) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySedeActiva, sede.activa);
    await prefs.setInt(_keySedeRadio, sede.radioMetros);
    if (sede.latitud != null && sede.longitud != null) {
      await prefs.setDouble(_keySedeLat, sede.latitud!);
      await prefs.setDouble(_keySedeLon, sede.longitud!);
    }
    final nombre = sede.nombre?.trim();
    if (nombre == null || nombre.isEmpty) {
      await prefs.remove(_keySedeNombre);
    } else {
      await prefs.setString(_keySedeNombre, nombre);
    }
  }

  /// Encendido por defecto: reconocer los asuetos de ley acierta mucho más
  /// veces de las que se equivoca, y de todos modos solo sugiere.
  Future<bool> getAsuetosActivos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAsuetosActivos) ?? true;
  }

  Future<void> setAsuetosActivos(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAsuetosActivos, valor);
  }

  /// Sigue al teléfono mientras el usuario no elija otra cosa.
  Future<ModoTema> getModoTema() async {
    final prefs = await SharedPreferences.getInstance();
    return ModoTema.desdeClave(prefs.getString(_keyModoTema));
  }

  Future<void> setModoTema(ModoTema modo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModoTema, modo.clave);
  }

  /// El widget arranca sólido: es lo que se ve bien sobre cualquier fondo
  /// de pantalla.
  Future<FondoWidget> getFondoWidget() async {
    final prefs = await SharedPreferences.getInstance();
    return FondoWidget.desdeClave(prefs.getString(_keyFondoWidget));
  }

  Future<void> setFondoWidget(FondoWidget fondo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFondoWidget, fondo.clave);
  }

  Future<SectorLaboral> getSector() async {
    final prefs = await SharedPreferences.getInstance();
    return SectorLaboral.desdeClave(prefs.getString(_keySector));
  }

  Future<void> setSector(SectorLaboral sector) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySector, sector.clave);
  }

  /// Olvida dónde queda la sede y apaga la vigilancia.
  Future<void> borrarSede() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySedeLat);
    await prefs.remove(_keySedeLon);
    await prefs.remove(_keySedeNombre);
    await prefs.setBool(_keySedeActiva, false);
  }
}
