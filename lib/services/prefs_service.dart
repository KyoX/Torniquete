import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import 'widget_service.dart';

/// Marcas del día que la app puede recordar. Cada una tiene su hora sugerida
/// y su propio rango de identificadores de notificación.
enum RecordatorioTipo {
  entrada('entrada', 'Marcar entrada', 7 * 60 + 50),
  salidaAlmuerzo('salida_almuerzo', 'Pausar para almorzar', 12 * 60),
  regresoAlmuerzo('regreso_almuerzo', 'Continuar tras el almuerzo', 13 * 60),
  // A diferencia de los otros tres, este no recuerda un hábito del día: solo
  // suena si a esta hora el día sigue con entrada y sin salida.
  confirmarSalida('confirmar_salida', 'Confirmar la salida', 20 * 60);

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

/// Los días de la semana, nombrados por el `weekday` de [DateTime]
/// (1 = lunes … 7 = domingo).
///
/// Están aquí y no dentro de una configuración concreta porque los comparten
/// dos ajustes que no se conocen entre sí: la semana de oficina y la meta de
/// horas de cada día.
class DiasSemana {
  const DiasSemana._();

  static const List<String> nombres = [
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
  static const List<String> abreviaturas = [
    'Lu',
    'Ma',
    'Mi',
    'Ju',
    'Vi',
    'Sá',
    'Do',
  ];

  static String nombre(int dia) => nombres[dia - 1];

  static String abreviatura(int dia) => abreviaturas[dia - 1];

  static String capitalizar(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
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
  /// Es la semana de trabajo del usuario, y manda sobre todo lo que la app
  /// dice por su cuenta: ni el aviso al llegar ni los recordatorios de marca
  /// aparecen un día que no está en la lista. Con trabajo híbrido, un lunes
  /// de teletrabajo no es un día de torniquete, así que ni pasar cerca de la
  /// oficina ni que den las ocho justifican una notificación.
  ///
  /// Lo que se marca a mano no se toca: cualquier día se puede registrar
  /// entera una jornada.
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
    if (dias.length == 1) {
      return DiasSemana.capitalizar(DiasSemana.nombre(dias.first));
    }

    final seguidos = dias.last - dias.first == dias.length - 1;
    if (seguidos && dias.length > 2) {
      return 'De ${DiasSemana.nombre(dias.first)} '
          'a ${DiasSemana.nombre(dias.last)}';
    }
    final nombres = dias.map(DiasSemana.nombre).toList();
    final ultimo = nombres.removeLast();
    return DiasSemana.capitalizar('${nombres.join(', ')} y $ultimo');
  }

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

/// Cuántas horas se esperan de cada día de la semana.
///
/// Antes la app solo sabía de dos metas —lunes a jueves y viernes— y le daba
/// la del lunes a los sábados, así que un 4x10, media jornada el miércoles o
/// un sábado suelto no cabían, y registrar un fin de semana inventaba un
/// déficit de una jornada entera.
@immutable
class MetasSemana {
  /// Horas de cada día, indexadas por el `weekday` de [DateTime]
  /// (1 = lunes … 7 = domingo).
  ///
  /// Un día en cero no exige horas: cuenta como libre, no resta del banco y
  /// lo que se trabaje en él es tiempo extra, igual que un festivo.
  final Map<int, double> horas;

  const MetasSemana._(this.horas);

  /// Nadie trabaja más de un día en un día.
  static const double maxHoras = 24;

  /// La semana que la app daba por supuesta: lunes a jueves iguales, el
  /// viernes por su cuenta y el fin de semana libre.
  ///
  /// Es lo que se le da a quien nunca ha tocado el ajuste y lo que guarda el
  /// onboarding: pedir siete cifras para empezar a usar la app es demasiado,
  /// y de aquí se afina después día por día.
  factory MetasSemana.clasica({
    double lunesAJueves = PrefsService.defaultMetaLJ,
    double viernes = PrefsService.defaultMetaViernes,
  }) =>
      MetasSemana.desde({
        DateTime.monday: lunesAJueves,
        DateTime.tuesday: lunesAJueves,
        DateTime.wednesday: lunesAJueves,
        DateTime.thursday: lunesAJueves,
        DateTime.friday: viernes,
      });

  /// Las horas de los días que se pasen; el resto de la semana queda libre.
  ///
  /// Sanea lo que entra —negativos, jornadas de treinta horas, un día 9— en
  /// vez de confiar: esto llega de las preferencias y de un respaldo escrito
  /// por otra versión.
  factory MetasSemana.desde(Map<int, double> horas) => MetasSemana._({
        for (var dia = DateTime.monday; dia <= DateTime.sunday; dia++)
          dia: _sanear(horas[dia]),
      });

  static double _sanear(double? valor) {
    if (valor == null || valor.isNaN || valor <= 0) return 0;
    return valor > maxHoras ? maxHoras : valor;
  }

  double horasDe(int weekday) => horas[weekday] ?? 0;

  int minutosDe(int weekday) => (horasDe(weekday) * 60).round();

  bool exigeHoras(int weekday) => minutosDe(weekday) > 0;

  /// Los días que piden horas, de lunes a domingo.
  List<int> get diasConMeta => [
        for (var dia = DateTime.monday; dia <= DateTime.sunday; dia++)
          if (exigeHoras(dia)) dia,
      ];

  int get minutosSemana => [
        for (var dia = DateTime.monday; dia <= DateTime.sunday; dia++)
          minutosDe(dia),
      ].fold(0, (suma, m) => suma + m);

  /// Cuánto dura un día de trabajo típico, que es como se traduce el banco de
  /// horas a días ("te sobran ≈ 2 días").
  ///
  /// Es el promedio de los días que piden horas y no la meta del lunes: con
  /// 8h 30m de lunes a jueves y 6h 30m el viernes, una semana entera de banco
  /// son cinco días justos, y dividir entre la del lunes diría cuatro y pico.
  int get minutosDiaTipico {
    final dias = diasConMeta;
    if (dias.isEmpty) return 0;
    return (minutosSemana / dias.length).round();
  }

  /// La misma semana con [weekday] cambiado.
  MetasSemana conDia(int weekday, double horasDelDia) =>
      MetasSemana.desde({...horas, weekday: horasDelDia});

  /// Las metas dichas como las diría una persona, juntando los días seguidos
  /// que piden lo mismo: "De lunes a jueves 8h 30m · Viernes 6h 30m".
  String get legible {
    final dias = diasConMeta;
    if (dias.isEmpty) return 'Ningún día pide horas';

    final trozos = <String>[];
    var i = 0;
    while (i < dias.length) {
      var fin = i;
      while (fin + 1 < dias.length &&
          dias[fin + 1] == dias[fin] + 1 &&
          horasDe(dias[fin + 1]) == horasDe(dias[i])) {
        fin++;
      }
      final duracion = TimeUtils.formatDurationMinutes(minutosDe(dias[i]));
      final cuando = switch (fin - i) {
        0 => DiasSemana.capitalizar(DiasSemana.nombre(dias[i])),
        1 => DiasSemana.capitalizar(
            '${DiasSemana.nombre(dias[i])} y ${DiasSemana.nombre(dias[fin])}',
          ),
        _ => 'De ${DiasSemana.nombre(dias[i])} '
            'a ${DiasSemana.nombre(dias[fin])}',
      };
      trozos.add('$cuando $duracion');
      i = fin + 1;
    }
    return trozos.join(' · ');
  }

  /// Las siete horas en orden, que es como se guardan y como viajan en un
  /// respaldo.
  List<double> get comoLista => [
        for (var dia = DateTime.monday; dia <= DateTime.sunday; dia++)
          horasDe(dia),
      ];

  /// Lee lo que devuelve [comoLista]. Una lista que no trae los siete días se
  /// descarta entera: media semana leída a medias es peor que el valor por
  /// defecto.
  static MetasSemana? desdeLista(List<double?>? valores) {
    if (valores == null || valores.length != DateTime.daysPerWeek) return null;
    return MetasSemana.desde({
      for (var dia = DateTime.monday; dia <= DateTime.sunday; dia++)
        dia: valores[dia - 1] ?? 0,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is MetasSemana && mapEquals(horas, other.horas);

  @override
  int get hashCode => Object.hashAll(comoLista);
}

/// Acceso centralizado a SharedPreferences para los datos de configuración
/// del usuario (nombre, metas de horas, recordatorios y geocerca).
class PrefsService {
  static const _keyNombre = 'nombre_usuario';
  static const _keyMetaLJ = 'meta_lj_horas';
  static const _keyMetaViernes = 'meta_viernes_horas';
  static const _keyMetasSemana = 'metas_semana_horas';
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

  /// La meta de cada día de la semana.
  ///
  /// Quien viene de una versión que solo sabía de dos metas no tiene la clave
  /// nueva: se le arma la semana clásica con las dos que sí tiene guardadas,
  /// así que la app le sigue pidiendo exactamente lo mismo que ayer. La
  /// conversión no se escribe aquí: se guarda sola la primera vez que toque
  /// el ajuste, y mientras tanto una versión anterior sigue leyendo lo suyo.
  Future<MetasSemana> getMetas() async {
    final prefs = await SharedPreferences.getInstance();
    final guardadas = MetasSemana.desdeLista(
      prefs.getStringList(_keyMetasSemana)?.map(double.tryParse).toList(),
    );
    if (guardadas != null) return guardadas;
    return MetasSemana.clasica(
      lunesAJueves: prefs.getDouble(_keyMetaLJ) ?? defaultMetaLJ,
      viernes: prefs.getDouble(_keyMetaViernes) ?? defaultMetaViernes,
    );
  }

  /// Guarda la semana entera y, de paso, las dos metas viejas.
  ///
  /// Las viejas se siguen escribiendo porque son lo único que entiende una
  /// versión anterior de la app: si se instala el APK de ayer sobre este, el
  /// lunes y el viernes siguen en su sitio en vez de volver a los valores de
  /// fábrica.
  Future<void> guardarMetas(MetasSemana metas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyMetasSemana,
      metas.comoLista.map((h) => h.toString()).toList(),
    );
    await prefs.setDouble(_keyMetaLJ, metas.horasDe(DateTime.monday));
    await prefs.setDouble(_keyMetaViernes, metas.horasDe(DateTime.friday));
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

  Future<void> setNombre(String nombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre.trim());
  }

  Future<void> guardarConfiguracion({
    required String nombre,
    required MetasSemana metas,
  }) async {
    await setNombre(nombre);
    await guardarMetas(metas);
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
