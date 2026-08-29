import '../utils/time_utils.dart';

/// Un tramo del día en el que se dejó de trabajar: se sale y se vuelve.
///
/// Sustituye al par salida-de-almuerzo / regreso, que solo sabía contar una
/// interrupción al día y obligaba a elegir cuál de las dos registrar cuando
/// había que salir a media mañana *y* a comer.
///
/// Cuál de las pausas es "el almuerzo" no se marca: se deduce de la hora en
/// [PausasService]. Una pausa no sabe por qué se hizo, y no tiene por qué.
class Pausa {
  /// "HH:mm" en que se dejó de trabajar.
  final String inicio;

  /// "HH:mm" en que se volvió, o null mientras la pausa sigue en curso.
  final String? fin;

  const Pausa({required this.inicio, this.fin});

  bool get abierta => fin == null;

  int? get inicioMinutos => _minutos(inicio);
  int? get finMinutos => _minutos(fin);

  static int? _minutos(String? hora) {
    final t = TimeUtils.parseTimeOfDay(hora);
    return t == null ? null : TimeUtils.toMinutes(t);
  }

  /// Cuánto duró, cerrando la pausa en curso a [hasta] (minutos desde
  /// medianoche). Sin [hasta] una pausa abierta no dura nada todavía.
  ///
  /// Nunca negativa: una pausa que termina antes de empezar es un error de
  /// edición, no tiempo trabajado de regalo.
  int duracion({int? hasta}) {
    final desde = inicioMinutos;
    if (desde == null) return 0;
    final cierre = finMinutos ?? hasta;
    if (cierre == null) return 0;
    final minutos = cierre - desde;
    return minutos > 0 ? minutos : 0;
  }

  Pausa cerrar(String hora) => Pausa(inicio: inicio, fin: hora);

  Pausa reabrir() => Pausa(inicio: inicio);

  Pausa conInicio(String hora) => Pausa(inicio: hora, fin: fin);

  /// Cómo viaja a la base de datos: "inicio-fin", con el fin vacío mientras
  /// la pausa siga abierta. Se guarda en una sola columna de texto en vez de
  /// en una tabla aparte porque las pausas no se consultan nunca por su
  /// cuenta: se leen y se escriben siempre con el día al que pertenecen.
  static const String separador = ';';

  String serializar() => '$inicio-${fin ?? ''}';

  static String serializarLista(List<Pausa> pausas) =>
      ordenar(pausas).map((p) => p.serializar()).join(separador);

  /// Lee la lista guardada descartando lo que no se entienda. Un texto
  /// corrupto deja el día sin pausas, que es recuperable a mano, en vez de
  /// tumbar la carga del historial entero.
  static List<Pausa> parsear(String? crudo) {
    if (crudo == null || crudo.trim().isEmpty) return const [];
    final pausas = <Pausa>[];
    for (final trozo in crudo.split(separador)) {
      final partes = trozo.split('-');
      if (partes.length != 2) continue;
      final inicio = partes[0].trim();
      if (TimeUtils.parseTimeOfDay(inicio) == null) continue;
      final fin = partes[1].trim();
      pausas.add(
        Pausa(
          inicio: inicio,
          fin: TimeUtils.parseTimeOfDay(fin) == null ? null : fin,
        ),
      );
    }
    return ordenar(pausas);
  }

  /// Por hora de inicio. Las pausas se marcan en orden a lo largo del día,
  /// pero editar una a mano puede desordenarlas.
  static List<Pausa> ordenar(List<Pausa> pausas) => [...pausas]
    ..sort((a, b) => (a.inicioMinutos ?? 0).compareTo(b.inicioMinutos ?? 0));

  @override
  bool operator ==(Object other) =>
      other is Pausa && other.inicio == inicio && other.fin == fin;

  @override
  int get hashCode => Object.hash(inicio, fin);

  @override
  String toString() => 'Pausa(${serializar()})';
}
