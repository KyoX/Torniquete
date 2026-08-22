/// Por qué se movió el saldo del banco de horas a mano.
enum MotivoMovimiento {
  /// Se gastaron horas acumuladas (día compensatorio, salir temprano...).
  canje('canje', 'Canje de horas'),

  /// Corrección del saldo: horas reconocidas por la empresa, arrastre de un
  /// periodo anterior, ajuste de nómina.
  ajuste('ajuste', 'Ajuste de saldo');

  const MotivoMovimiento(this.clave, this.etiqueta);

  final String clave;
  final String etiqueta;

  static MotivoMovimiento desdeClave(String? clave) =>
      MotivoMovimiento.values.firstWhere(
        (m) => m.clave == clave,
        orElse: () => MotivoMovimiento.ajuste,
      );
}

/// Movimiento manual del banco de horas. Los días trabajados alimentan el
/// saldo automáticamente; esto cubre lo que la app no puede deducir sola:
/// horas gastadas en un compensatorio o un saldo traído de antes de instalar
/// la app.
class MovimientoBanco {
  final int? id;
  final String fecha; // YYYY-MM-DD

  /// Positivo suma al saldo, negativo lo consume. Un canje siempre se guarda
  /// en negativo; un ajuste puede ir en cualquier sentido.
  final int minutos;

  final MotivoMovimiento motivo;
  final String? nota;
  final DateTime creadoEn;

  const MovimientoBanco({
    this.id,
    required this.fecha,
    required this.minutos,
    required this.motivo,
    this.nota,
    required this.creadoEn,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha': fecha,
      'minutos': minutos,
      'motivo': motivo.clave,
      'nota': nota,
      'creado_en': creadoEn.toIso8601String(),
    };
  }

  factory MovimientoBanco.fromMap(Map<String, Object?> map) {
    return MovimientoBanco(
      id: map['id'] as int?,
      fecha: map['fecha'] as String,
      minutos: (map['minutos'] as num?)?.toInt() ?? 0,
      motivo: MotivoMovimiento.desdeClave(map['motivo'] as String?),
      nota: map['nota'] as String?,
      creadoEn:
          DateTime.tryParse(map['creado_en'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
