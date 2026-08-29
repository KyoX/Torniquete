import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import 'widget_service.dart';

/// Marcas del día que la app puede recordar. Cada una tiene su hora sugerida
/// y su propio rango de identificadores de notificación.
enum RecordatorioTipo {
  entrada('entrada', 'Marcar entrada', 7 * 60 + 50),
  salidaAlmuerzo('salida_almuerzo', 'Pausar para almorzar', 12 * 60),
  regresoAlmuerzo('regreso_almuerzo', 'Continuar tras el almuerzo', 13 * 60);

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

  /// Si Android debe avisar al llegar para ofrecer la marca que toque.
  final bool avisarAlLlegar;

  /// Días de la semana en los que se va a la sede (1 = lunes … 7 = domingo).
  ///
  /// Solo condiciona el aviso de llegada. Con trabajo híbrido, pasar cerca de
  /// la oficina un día de teletrabajo no debe preguntar si se marca la
  /// entrada; el resto de la app no cambia, porque desde casa se trabaja y se
  /// marca igual.
  final Set<int> diasOficina;

  const SedeConfig({
    this.activa = false,
    this.latitud,
    this.longitud,
    this.radioMetros = defaultRadioMetros,
    this.nombre,
    this.avisarAlLlegar = false,
    this.diasOficina = diasLaboralesTipicos,
  });

  static const int defaultRadioMetros = 200;

  /// De lunes a viernes, que es la semana laboral de la mayoría.
  static const Set<int> diasLaboralesTipicos = {1, 2, 3, 4, 5};

  /// Nombres de los días, indexados por el `weekday` de [DateTime].
  static const List<String> nombresDias = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  /// Etiquetas de dos letras para los botones. Se usan dos y no una porque
  /// "M" sirve igual para martes que para miércoles.
  static const List<String> abreviaturasDias = [
    'Lu',
    'Ma',
    'Mi',
    'Ju',
    'Vi',
    'Sá',
    'Do',
  ];

  static String nombreDia(int dia) => nombresDias[dia - 1];

  /// Un radio muy pequeño produce falsas alertas: el GPS de un teléfono
  /// dentro de un edificio se desvía decenas de metros con facilidad.
  static const int minRadioMetros = 50;
  static const int maxRadioMetros = 2000;

  bool get tieneCoordenadas => latitud != null && longitud != null;

  /// Solo se puede vigilar la geocerca si está encendida y ya se guardó
  /// dónde queda la sede.
  bool get vigente => activa && tieneCoordenadas;

  /// El aviso de llegada es independiente de [vigente] a propósito: son dos
  /// cosas distintas —avisar de una marca lejana y avisar al llegar— y quien
  /// quiere una no tiene por qué querer la otra. Lo único que comparten es
  /// necesitar unas coordenadas contra las que comparar.
  ///
  /// Sin ningún día de oficina marcado no hay nada que vigilar: más vale no
  /// registrar la geocerca que tener a Android despertando a la app para un
  /// aviso que nunca va a salir.
  bool get vigilanciaLlegadaVigente =>
      avisarAlLlegar && tieneCoordenadas && diasOficina.isNotEmpty;

  /// Los días de oficina dichos como los diría una persona: "De lunes a
  /// viernes", "Lunes, miércoles y viernes".
  String get diasOficinaLegible {
    final dias = diasOficina.where((d) => d >= 1 && d <= 7).toList()..sort();
    if (dias.isEmpty) return 'Ningún día';
    if (dias.length == 7) return 'Todos los días';
    if (dias.length == 1) return _capitalizar(nombreDia(dias.first));

    final seguidos = dias.last - dias.first == dias.length - 1;
    if (seguidos && dias.length > 2) {
      return 'De ${nombreDia(dias.first)} a ${nombreDia(dias.last)}';
    }
    final nombres = dias.map(nombreDia).toList();
    final ultimo = nombres.removeLast();
    return _capitalizar('${nombres.join(', ')} y $ultimo');
  }

  static String _capitalizar(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

  SedeConfig copyWith({
    bool? activa,
    double? latitud,
    double? longitud,
    int? radioMetros,
    String? nombre,
    bool? avisarAlLlegar,
    Set<int>? diasOficina,
  }) =>
      SedeConfig(
        activa: activa ?? this.activa,
        latitud: latitud ?? this.latitud,
        longitud: longitud ?? this.longitud,
        radioMetros: radioMetros ?? this.radioMetros,
        nombre: nombre ?? this.nombre,
        avisarAlLlegar: avisarAlLlegar ?? this.avisarAlLlegar,
        diasOficina: diasOficina ?? this.diasOficina,
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
  static const _keySedeAvisoLlegada = 'sede_aviso_llegada';
  static const _keySedeDiasOficina = 'sede_dias_oficina';
  static const _keyAsuetosActivos = 'asuetos_activos';
  static const _keySector = 'sector_laboral';
  static const _keyModoTema = 'modo_tema';
  static const _keyFondoWidget = 'fondo_widget';
  static const _keyDescuentoAlmuerzo = 'descuento_almuerzo_min';

  static const double defaultMetaLJ = 8.5;
  static const double defaultMetaViernes = 6.5;

  /// Tope del descuento fijo de almuerzo. Dos horas cubren cualquier jornada
  /// partida real y evitan que un dedazo deje el día entero en cero.
  static const int maxDescuentoAlmuerzo = 120;

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

  /// Minutos de almuerzo que la empresa descuenta aunque no se tomen.
  ///
  /// Cero por defecto: sin configurarlo la app sigue contando el almuerzo
  /// real, que es lo que hacía antes de que este ajuste existiera.
  Future<int> getDescuentoAlmuerzo() async {
    final prefs = await SharedPreferences.getInstance();
    final valor = prefs.getInt(_keyDescuentoAlmuerzo) ?? 0;
    return valor.clamp(0, maxDescuentoAlmuerzo);
  }

  Future<void> setDescuentoAlmuerzo(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyDescuentoAlmuerzo,
      minutos.clamp(0, maxDescuentoAlmuerzo),
    );
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
      avisarAlLlegar: prefs.getBool(_keySedeAvisoLlegada) ?? false,
      diasOficina: _leerDiasOficina(prefs.getStringList(_keySedeDiasOficina)),
    );
  }

  /// La lista guardada, o de lunes a viernes si nunca se tocó el ajuste.
  ///
  /// "Ningún día" es una elección válida y se distingue de "sin configurar"
  /// por la ausencia de la clave, no por la lista vacía.
  static Set<int> _leerDiasOficina(List<String>? guardados) {
    if (guardados == null) return SedeConfig.diasLaboralesTipicos;
    return {
      for (final valor in guardados)
        if (int.tryParse(valor) case final dia?)
          if (dia >= 1 && dia <= 7) dia,
    };
  }

  Future<void> guardarSede(SedeConfig sede) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySedeActiva, sede.activa);
    await prefs.setBool(_keySedeAvisoLlegada, sede.avisarAlLlegar);
    await prefs.setInt(_keySedeRadio, sede.radioMetros);
    await prefs.setStringList(
      _keySedeDiasOficina,
      (sede.diasOficina.toList()..sort()).map((d) => d.toString()).toList(),
    );
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
    await prefs.setBool(_keySedeAvisoLlegada, false);
  }
}
