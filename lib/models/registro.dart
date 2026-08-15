class Registro {
  final int? id;
  final String fecha; // YYYY-MM-DD
  final String? entrada1; // HH:mm - Entrada mañana
  final String? salida1; // HH:mm - Salida almuerzo
  final String? entrada2; // HH:mm - Entrada tarde
  final String? salidaReal; // HH:mm - Salida confirmada por el usuario
  final int metaMinutos; // meta del día en minutos
  final int minutosCumplidos; // minutos trabajados acumulados (columna horas_cumplidas)

  const Registro({
    this.id,
    required this.fecha,
    this.entrada1,
    this.salida1,
    this.entrada2,
    this.salidaReal,
    required this.metaMinutos,
    this.minutosCumplidos = 0,
  });

  Registro copyWith({
    int? id,
    String? fecha,
    String? entrada1,
    String? salida1,
    String? entrada2,
    String? salidaReal,
    int? metaMinutos,
    int? minutosCumplidos,
    bool clearEntrada1 = false,
    bool clearSalida1 = false,
    bool clearEntrada2 = false,
    bool clearSalidaReal = false,
  }) {
    return Registro(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      entrada1: clearEntrada1 ? null : (entrada1 ?? this.entrada1),
      salida1: clearSalida1 ? null : (salida1 ?? this.salida1),
      entrada2: clearEntrada2 ? null : (entrada2 ?? this.entrada2),
      salidaReal: clearSalidaReal ? null : (salidaReal ?? this.salidaReal),
      metaMinutos: metaMinutos ?? this.metaMinutos,
      minutosCumplidos: minutosCumplidos ?? this.minutosCumplidos,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha': fecha,
      'entrada_1': entrada1,
      'salida_1': salida1,
      'entrada_2': entrada2,
      'salida_real': salidaReal,
      'meta_minutos': metaMinutos,
      'horas_cumplidas': minutosCumplidos,
    };
  }

  factory Registro.fromMap(Map<String, Object?> map) {
    return Registro(
      id: map['id'] as int?,
      fecha: map['fecha'] as String,
      entrada1: map['entrada_1'] as String?,
      salida1: map['salida_1'] as String?,
      entrada2: map['entrada_2'] as String?,
      salidaReal: map['salida_real'] as String?,
      metaMinutos: map['meta_minutos'] as int? ?? 0,
      minutosCumplidos: map['horas_cumplidas'] as int? ?? 0,
    );
  }
}
