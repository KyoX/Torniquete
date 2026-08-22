/// Naturaleza de un día del historial. Los días que no son [TipoDia.normal]
/// no exigen meta de horas: no generan déficit en el banco de horas y, si
/// aun así se trabajó, todo lo trabajado cuenta como tiempo extra.
///
/// No incluye "compensatorio" a propósito: tomarse un día a cuenta de las
/// horas acumuladas es un retiro del banco, no una exención de meta, y se
/// registra como movimiento (ver MovimientoBanco).
enum TipoDia {
  normal('normal', 'Día normal'),
  festivo('festivo', 'Festivo'),
  vacaciones('vacaciones', 'Vacaciones'),
  incapacidad('incapacidad', 'Incapacidad'),
  permiso('permiso', 'Permiso');

  const TipoDia(this.clave, this.etiqueta);

  /// Valor persistido en SQLite y en los archivos exportados.
  final String clave;

  /// Nombre visible en la interfaz.
  final String etiqueta;

  /// Solo los días normales exigen cumplir la meta de horas.
  bool get exigeMeta => this == TipoDia.normal;

  /// Los demás tipos justifican la ausencia: no son un día "sin registrar".
  bool get esJustificado => !exigeMeta;

  /// Lee la clave guardada. Cualquier valor desconocido (una base de datos
  /// de una versión futura, un CSV editado a mano) se trata como día normal
  /// para no perder la meta de ese día en silencio.
  static TipoDia desdeClave(String? clave) {
    if (clave == null) return TipoDia.normal;
    return TipoDia.values.firstWhere(
      (t) => t.clave == clave,
      orElse: () => TipoDia.normal,
    );
  }
}
