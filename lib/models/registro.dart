import '../services/pausas_service.dart';
import 'pausa.dart';
import 'tipo_dia.dart';

class Registro {
  final int? id;
  final String fecha; // YYYY-MM-DD
  final String? entrada1; // HH:mm - Entrada del día
  final String? salidaReal; // HH:mm - Salida confirmada por el usuario

  /// Los tramos en los que se dejó de trabajar, en orden.
  ///
  /// Sustituyen al par salida-almuerzo / regreso: un día puede tener una
  /// diligencia a media mañana, el almuerzo y una salida por la tarde, y
  /// antes solo cabía una de las tres.
  final List<Pausa> pausas;

  final int metaMinutos; // meta del día en minutos
  final int minutosCumplidos; // minutos trabajados acumulados (columna horas_cumplidas)

  /// Festivo, vacaciones, incapacidad o permiso eximen de la meta del día.
  final TipoDia tipoDia;

  /// Aclaración libre del día ("Festivo de la Independencia", "Cita médica").
  final String? nota;

  /// Minutos de almuerzo que la empresa descuenta este día aunque no se
  /// hayan tomado.
  ///
  /// Se guarda por día, como [metaMinutos], y no se lee de las preferencias
  /// al vuelo: cambiar la regla en Ajustes no debe reescribir el cálculo de
  /// los días ya trabajados bajo otra regla.
  final int descuentoAlmuerzoMinutos;

  const Registro({
    this.id,
    required this.fecha,
    this.entrada1,
    this.salidaReal,
    this.pausas = const [],
    required this.metaMinutos,
    this.minutosCumplidos = 0,
    this.tipoDia = TipoDia.normal,
    this.nota,
    this.descuentoAlmuerzoMinutos = 0,
  });

  /// Meta que este día realmente exige. Los días justificados no piden horas,
  /// así que no restan del banco y todo lo que se trabaje en ellos es extra.
  int get metaEfectivaMinutos => tipoDia.exigeMeta ? metaMinutos : 0;

  /// La pausa en curso, si el día está parado ahora mismo.
  Pausa? get pausaAbierta => PausasService.abierta(pausas);

  /// La pausa que hace de almuerzo, deducida de la hora.
  Pausa? get almuerzo => PausasService.pausaDeAlmuerzo(pausas);

  /// Hora en que se salió a almorzar, si alguna pausa cae en la ventana del
  /// almuerzo.
  ///
  /// Es una lectura de [pausas], no un dato aparte: la jornada solo se
  /// guarda una vez. Existe porque los reportes y el widget hablan de
  /// "almuerzo" y "regreso", que es lo que una planilla espera ver.
  String? get salida1 => almuerzo?.inicio;

  /// Hora del regreso de ese almuerzo.
  String? get entrada2 => almuerzo?.fin;

  Registro copyWith({
    int? id,
    String? fecha,
    String? entrada1,
    String? salidaReal,
    List<Pausa>? pausas,
    int? metaMinutos,
    int? minutosCumplidos,
    TipoDia? tipoDia,
    String? nota,
    int? descuentoAlmuerzoMinutos,
    bool clearEntrada1 = false,
    bool clearSalidaReal = false,
    bool clearNota = false,
  }) {
    return Registro(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      entrada1: clearEntrada1 ? null : (entrada1 ?? this.entrada1),
      salidaReal: clearSalidaReal ? null : (salidaReal ?? this.salidaReal),
      pausas: pausas ?? this.pausas,
      metaMinutos: metaMinutos ?? this.metaMinutos,
      minutosCumplidos: minutosCumplidos ?? this.minutosCumplidos,
      tipoDia: tipoDia ?? this.tipoDia,
      nota: clearNota ? null : (nota ?? this.nota),
      descuentoAlmuerzoMinutos:
          descuentoAlmuerzoMinutos ?? this.descuentoAlmuerzoMinutos,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha': fecha,
      'entrada_1': entrada1,
      // Las dos columnas del almuerzo se siguen escribiendo aunque ya no se
      // lean: son la proyección de la pausa del almuerzo, y dejarlas al día
      // mantiene legible cualquier respaldo o consulta directa a la base.
      'salida_1': salida1,
      'entrada_2': entrada2,
      'pausas': Pausa.serializarLista(pausas),
      'salida_real': salidaReal,
      'meta_minutos': metaMinutos,
      'horas_cumplidas': minutosCumplidos,
      'tipo_dia': tipoDia.clave,
      'nota': nota,
      'descuento_almuerzo_min': descuentoAlmuerzoMinutos,
    };
  }

  factory Registro.fromMap(Map<String, Object?> map) {
    return Registro(
      id: map['id'] as int?,
      fecha: map['fecha'] as String,
      entrada1: map['entrada_1'] as String?,
      salidaReal: map['salida_real'] as String?,
      pausas: _pausasDe(map),
      metaMinutos: map['meta_minutos'] as int? ?? 0,
      minutosCumplidos: map['horas_cumplidas'] as int? ?? 0,
      tipoDia: TipoDia.desdeClave(map['tipo_dia'] as String?),
      nota: map['nota'] as String?,
      descuentoAlmuerzoMinutos: map['descuento_almuerzo_min'] as int? ?? 0,
    );
  }

  /// Las pausas del día, o el almuerzo de siempre si vienen de un origen que
  /// no las conoce: un respaldo hecho antes de que existieran.
  static List<Pausa> _pausasDe(Map<String, Object?> map) {
    final crudo = map['pausas'];
    if (crudo != null) return Pausa.parsear(crudo as String?);
    final salida = map['salida_1'] as String?;
    if (salida == null || salida.isEmpty) return const [];
    final regreso = map['entrada_2'] as String?;
    return [
      Pausa(inicio: salida, fin: regreso?.isEmpty ?? true ? null : regreso),
    ];
  }
}
