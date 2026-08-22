/// Asuetos de ley de El Salvador.
///
/// Todo lo de este archivo son funciones puras y sin dependencias: no tocan
/// la base de datos, la red ni Flutter. Así el calendario se puede probar
/// entero y la app lo consulta cuando lo necesita en vez de guardar una lista
/// de fechas que habría que refrescar cada año.
library;

/// A qué régimen de asuetos está sujeto el usuario.
///
/// La diferencia práctica son las fiestas agostinas: el Código de Trabajo
/// reconoce solo el 6 de agosto, mientras que a los empleados públicos les
/// corresponden además el 3 y el 5.
enum SectorLaboral {
  privado(
    'privado',
    'Sector privado',
    'Código de Trabajo, Art. 190',
  ),
  publico(
    'publico',
    'Sector público',
    'Ley de Asuetos, Vacaciones y Licencias de los Empleados Públicos',
  );

  const SectorLaboral(this.clave, this.etiqueta, this.fundamento);

  final String clave;
  final String etiqueta;

  /// De dónde sale la lista, para poder mostrarlo en Ajustes.
  final String fundamento;

  static SectorLaboral desdeClave(String? clave) => SectorLaboral.values
      .firstWhere((s) => s.clave == clave, orElse: () => SectorLaboral.privado);
}

/// Un día de asueto concreto, ya resuelto a una fecha del calendario.
class Asueto {
  /// Fecha en 'yyyy-MM-dd', el mismo formato con el que se guardan los días.
  final String fecha;

  final String nombre;

  /// True si la fecha depende de la Pascua y por tanto cambia cada año.
  final bool movil;

  const Asueto({
    required this.fecha,
    required this.nombre,
    this.movil = false,
  });

  @override
  String toString() => '$fecha $nombre';
}

class FestivosSV {
  const FestivosSV._();

  /// Fecha en el formato que usa la app para indexar los días.
  static String clave(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  /// Domingo de Pascua del [anio] en el calendario gregoriano.
  ///
  /// Es el algoritmo de Meeus/Jones/Butcher. De él cuelgan los únicos asuetos
  /// móviles del año —jueves, viernes y sábado de Semana Santa—, así que sin
  /// esto habría que teclear a mano las fechas de cada año.
  static DateTime domingoDePascua(int anio) {
    final a = anio % 19;
    final b = anio ~/ 100;
    final c = anio % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final mes = (h + l - 7 * m + 114) ~/ 31;
    final dia = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(anio, mes, dia);
  }

  /// Índice por año para no recalcular la Pascua en cada consulta. La
  /// proyección del mes y el plan del banco de horas preguntan día por día.
  static final Map<int, Map<String, Asueto>> _cachePrivado = {};
  static final Map<int, Map<String, Asueto>> _cachePublico = {};

  static Map<int, Map<String, Asueto>> _cache(SectorLaboral sector) =>
      sector == SectorLaboral.publico ? _cachePublico : _cachePrivado;

  /// Todos los asuetos del [anio], ordenados por fecha.
  static List<Asueto> delAnio(
    int anio, {
    SectorLaboral sector = SectorLaboral.privado,
  }) =>
      _indice(anio, sector).values.toList();

  static Map<String, Asueto> _indice(int anio, SectorLaboral sector) {
    final cache = _cache(sector);
    final guardado = cache[anio];
    if (guardado != null) return guardado;

    final pascua = domingoDePascua(anio);
    DateTime antesDePascua(int dias) =>
        DateTime(pascua.year, pascua.month, pascua.day - dias);

    final asuetos = <Asueto>[
      Asueto(fecha: clave(DateTime(anio, 1, 1)), nombre: 'Año Nuevo'),
      Asueto(
        fecha: clave(antesDePascua(3)),
        nombre: 'Jueves Santo',
        movil: true,
      ),
      Asueto(
        fecha: clave(antesDePascua(2)),
        nombre: 'Viernes Santo',
        movil: true,
      ),
      Asueto(
        fecha: clave(antesDePascua(1)),
        nombre: 'Sábado Santo',
        movil: true,
      ),
      Asueto(fecha: clave(DateTime(anio, 5, 1)), nombre: 'Día del Trabajo'),
      Asueto(fecha: clave(DateTime(anio, 5, 10)), nombre: 'Día de la Madre'),
      Asueto(fecha: clave(DateTime(anio, 6, 17)), nombre: 'Día del Padre'),
      // Fiestas agostinas. Al sector público le corresponden tres días; el
      // Código de Trabajo solo reconoce el 6.
      if (sector == SectorLaboral.publico) ...[
        Asueto(fecha: clave(DateTime(anio, 8, 3)), nombre: 'Fiestas agostinas'),
        Asueto(fecha: clave(DateTime(anio, 8, 5)), nombre: 'Fiestas agostinas'),
      ],
      Asueto(
        fecha: clave(DateTime(anio, 8, 6)),
        nombre: 'Divino Salvador del Mundo',
      ),
      Asueto(
        fecha: clave(DateTime(anio, 9, 15)),
        nombre: 'Día de la Independencia',
      ),
      Asueto(
        fecha: clave(DateTime(anio, 11, 2)),
        nombre: 'Día de los Difuntos',
      ),
      Asueto(fecha: clave(DateTime(anio, 12, 25)), nombre: 'Navidad'),
    ]..sort((a, b) => a.fecha.compareTo(b.fecha));

    final indice = {for (final a in asuetos) a.fecha: a};
    cache[anio] = indice;
    return indice;
  }

  /// El asueto que cae en [fecha], o null si es un día corriente.
  static Asueto? enFecha(
    DateTime fecha, {
    SectorLaboral sector = SectorLaboral.privado,
  }) =>
      _indice(fecha.year, sector)[clave(fecha)];

  /// Igual que [enFecha] pero a partir de una fecha ya en 'yyyy-MM-dd', que
  /// es como vienen guardadas en la base de datos.
  static Asueto? enClave(
    String fecha, {
    SectorLaboral sector = SectorLaboral.privado,
  }) {
    final anio = int.tryParse(fecha.length >= 4 ? fecha.substring(0, 4) : '');
    if (anio == null) return null;
    return _indice(anio, sector)[fecha];
  }

  static bool esFinDeSemana(DateTime fecha) =>
      fecha.weekday == DateTime.saturday || fecha.weekday == DateTime.sunday;

  /// True si en [fecha] se espera que se trabaje: ni fin de semana ni asueto.
  ///
  /// Es lo que usan la proyección del mes y el plan del banco de horas para
  /// no exigir horas de un día en que la oficina está cerrada.
  static bool esDiaHabil(
    DateTime fecha, {
    SectorLaboral sector = SectorLaboral.privado,
  }) =>
      !esFinDeSemana(fecha) && enFecha(fecha, sector: sector) == null;

  /// Asuetos que caen entre [desde] y [hasta], ambos incluidos.
  static List<Asueto> entre(
    DateTime desde,
    DateTime hasta, {
    SectorLaboral sector = SectorLaboral.privado,
  }) {
    if (hasta.isBefore(desde)) return const [];
    final desdeClave = clave(desde);
    final hastaClave = clave(hasta);
    final resultado = <Asueto>[];
    for (var anio = desde.year; anio <= hasta.year; anio++) {
      for (final asueto in delAnio(anio, sector: sector)) {
        if (asueto.fecha.compareTo(desdeClave) >= 0 &&
            asueto.fecha.compareTo(hastaClave) <= 0) {
          resultado.add(asueto);
        }
      }
    }
    return resultado;
  }
}
