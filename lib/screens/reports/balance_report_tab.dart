import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/movimiento_banco.dart';
import '../../providers/app_provider.dart';
import '../../models/registro.dart';
import '../../services/db_service.dart';
import '../../services/reports_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';

/// Banco de horas: además de mostrar el balance acumulado, dice qué hacer
/// con él —cuánto trabajar de más para saldar el déficit dentro de un plazo,
/// o cuántos días de compensatorio dan las horas a favor— y permite anotar
/// los movimientos que la app no puede deducir sola.
class BalanceReportTab extends StatefulWidget {
  final List<Registro> registros;
  final List<MovimientoBanco> movimientos;

  /// Meta de un día laboral típico, para traducir el saldo a días.
  final int metaDiariaMinutos;

  /// Se llama cuando se anota o se borra un movimiento, para que la pantalla
  /// de reportes vuelva a leer la base de datos.
  final Future<void> Function() onCambio;

  const BalanceReportTab({
    super.key,
    required this.registros,
    required this.movimientos,
    required this.metaDiariaMinutos,
    required this.onCambio,
  });

  @override
  State<BalanceReportTab> createState() => _BalanceReportTabState();
}

class _BalanceReportTabState extends State<BalanceReportTab> {
  /// Plazos ofrecidos para saldar el déficit, en días laborales.
  static const List<int> _plazos = [5, 10, 15, 20];

  int _plazoElegido = 10;

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('d MMM yyyy', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  String _conSigno(int minutos) =>
      (minutos >= 0 ? '+' : '') + TimeUtils.formatDurationMinutes(minutos);

  Future<void> _anotarMovimiento(MotivoMovimiento motivo) async {
    final movimiento = await showDialog<MovimientoBanco>(
      context: context,
      builder: (_) => _DialogoMovimiento(motivo: motivo),
    );
    if (movimiento == null) return;
    await DbService.instance.guardarMovimiento(movimiento);
    await widget.onCambio();
  }

  Future<void> _borrarMovimiento(MovimientoBanco movimiento) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar movimiento'),
        content: Text(
          'Se quitará ${_conSigno(movimiento.minutos)} del banco de horas '
          '(${movimiento.motivo.etiqueta.toLowerCase()} '
          'del ${_formatearFecha(movimiento.fecha)}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true || movimiento.id == null) return;
    await DbService.instance.eliminarMovimiento(movimiento.id!);
    await widget.onCambio();
  }

  @override
  Widget build(BuildContext context) {
    final estado = ReportsService.estadoBanco(
      registros: widget.registros,
      movimientos: widget.movimientos,
      metaDiariaMinutos: widget.metaDiariaMinutos,
    );
    // El plazo se cuenta sobre días en que de verdad se trabaja, así que
    // descuenta los asuetos de ley igual que la proyección del mes.
    final sector = context.watch<AppProvider>().sectorAsuetos;
    final plan = ReportsService.planCompensacion(
      saldoMinutos: estado.saldoMinutos,
      diasHabiles: _plazoElegido,
      desde: DateTime.now(),
      sector: sector,
    );
    final balances = ReportsService.balanceHistorico(widget.registros);
    final ordenDesc = balances.reversed.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TarjetaSaldo(estado: estado),
        const SizedBox(height: 16),
        _TarjetaPlan(
          asuetosContados: sector != null,
          estado: estado,
          plan: plan,
          plazos: _plazos,
          plazoElegido: _plazoElegido,
          onPlazo: (dias) => setState(() => _plazoElegido = dias),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _anotarMovimiento(MotivoMovimiento.canje),
                icon: const Icon(Icons.redeem, size: 18),
                label: const Text('Canjear horas'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _anotarMovimiento(MotivoMovimiento.ajuste),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ajustar saldo'),
              ),
            ),
          ],
        ),
        if (widget.movimientos.isNotEmpty) ...[
          const SizedBox(height: 20),
          _titulo('Movimientos anotados', Theme.of(context)),
          const SizedBox(height: 8),
          ...widget.movimientos.map(
            (m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  m.motivo == MotivoMovimiento.canje ? Icons.redeem : Icons.tune,
                ),
                title: Text(m.motivo.etiqueta),
                subtitle: Text(
                  [
                    _formatearFecha(m.fecha),
                    if (m.nota?.trim().isNotEmpty ?? false) m.nota!.trim(),
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _conSigno(m.minutos),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: m.minutos >= 0
                            ? AppColors.cumplido
                            : AppColors.rojo,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Borrar movimiento',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _borrarMovimiento(m),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _titulo('Día a día', Theme.of(context)),
        const SizedBox(height: 8),
        ...ordenDesc.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_formatearFecha(b.fecha)),
                subtitle: Text(_subtituloDia(b)),
                trailing: Text(
                  b.sinRegistro ? '—' : _conSigno(b.diferenciaMinutos),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: b.sinRegistro
                        ? AppColors.neutro
                        : (b.diferenciaMinutos >= 0
                            ? AppColors.cumplido
                            : AppColors.rojo),
                  ),
                ),
              ),
            )),
      ],
    );
  }

  String _subtituloDia(BalanceDay b) {
    final acumulado = 'Balance acumulado: '
        '${_conSigno(b.balanceAcumuladoMinutos)}';
    if (b.sinRegistro) return 'Sin horas registradas · balance sin cambios';
    if (b.justificado) return '${b.tipoDia.etiqueta} · $acumulado';
    return acumulado;
  }
}

Widget _titulo(String texto, ThemeData tema) => Text(
      texto,
      style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );

/// Saldo total y de dónde sale.
class _TarjetaSaldo extends StatelessWidget {
  final EstadoBanco estado;

  const _TarjetaSaldo({required this.estado});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positivo = estado.aFavor;
    final alFrente =
        positivo ? scheme.onPrimaryContainer : scheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: positivo ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text('Balance acumulado', style: TextStyle(color: alFrente)),
          const SizedBox(height: 6),
          Text(
            (positivo ? '+' : '') +
                TimeUtils.formatDurationMinutes(estado.saldoMinutos),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 32,
              color: alFrente,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            positivo
                ? 'Tienes tiempo extra acumulado'
                : 'Estás en déficit de horas',
            style: TextStyle(color: alFrente),
          ),
          if (estado.minutosDeMovimientos != 0) ...[
            const SizedBox(height: 10),
            Text(
              'Días trabajados: '
              '${estado.minutosDeDias >= 0 ? '+' : ''}'
              '${TimeUtils.formatDurationMinutes(estado.minutosDeDias)} · '
              'Movimientos: '
              '${estado.minutosDeMovimientos >= 0 ? '+' : ''}'
              '${TimeUtils.formatDurationMinutes(estado.minutosDeMovimientos)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: alFrente),
            ),
          ],
        ],
      ),
    );
  }
}

/// Qué hacer con el saldo: repartir el déficit en un plazo, o traducir las
/// horas a favor a días de compensatorio.
class _TarjetaPlan extends StatelessWidget {
  /// Si el plazo ya descontó los asuetos de ley, para no prometer de más.
  final bool asuetosContados;

  final EstadoBanco estado;
  final PlanBanco plan;
  final List<int> plazos;
  final int plazoElegido;
  final ValueChanged<int> onPlazo;

  const _TarjetaPlan({
    required this.asuetosContados,
    required this.estado,
    required this.plan,
    required this.plazos,
    required this.plazoElegido,
    required this.onPlazo,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat('d MMM', 'es').format(plan.fechaLimite);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined),
                const SizedBox(width: 10),
                Text(
                  'Qué hacer con el saldo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plan.hayDeficit) ...[
              Text(
                'Plazo para ponerte al día',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final dias in plazos)
                    ChoiceChip(
                      label: Text('$dias días'),
                      selected: dias == plazoElegido,
                      onSelected: (elegido) {
                        if (elegido) onPlazo(dias);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Trabaja '),
                    TextSpan(
                      text: TimeUtils.formatDurationMinutes(
                          plan.minutosExtraPorDia),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: ' de más cada día laboral y llegarás a cero el '
                          '$fecha.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                asuetosContados
                    ? 'El plazo ya descuenta fines de semana y asuetos de '
                        'ley. Las fiestas patronales y los días que dé la '
                        'empresa no los conoce: márcalos y el plazo se '
                        'recalcula.'
                    : 'El plazo solo descarta sábados y domingos. Activa los '
                        'asuetos en Ajustes para que también los descuente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Tienes '),
                    TextSpan(
                      text: TimeUtils.formatDurationMinutes(
                          plan.minutosDisponibles),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: estado.metaDiariaMinutos > 0
                          ? ' disponibles: alcanzan para '
                              '${estado.diasEquivalentes.toStringAsFixed(1)} '
                              'días de compensatorio.'
                          : ' disponibles.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuando uses esas horas, anótalas con "Canjear horas" para '
                'que el saldo refleje lo que de verdad te queda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pide los datos de un canje o un ajuste del banco de horas.
class _DialogoMovimiento extends StatefulWidget {
  final MotivoMovimiento motivo;

  const _DialogoMovimiento({required this.motivo});

  @override
  State<_DialogoMovimiento> createState() => _DialogoMovimientoState();
}

class _DialogoMovimientoState extends State<_DialogoMovimiento> {
  final _formKey = GlobalKey<FormState>();
  final _horasController = TextEditingController();
  final _minutosController = TextEditingController(text: '0');
  final _notaController = TextEditingController();
  DateTime _fecha = DateTime.now();

  /// Solo aplica a los ajustes: un canje siempre resta.
  bool _aFavor = true;

  bool get _esCanje => widget.motivo == MotivoMovimiento.canje;

  @override
  void dispose() {
    _horasController.dispose();
    _minutosController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  String? _validarHoras(String? valor) {
    final horas = int.tryParse((valor ?? '').trim());
    if (horas == null || horas < 0 || horas > 999) return 'Inválido';
    return null;
  }

  String? _validarMinutos(String? valor) {
    final minutos = int.tryParse((valor ?? '').trim());
    if (minutos == null || minutos < 0 || minutos > 59) return '0 a 59';
    return null;
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(ahora.year - 2),
      lastDate: DateTime(ahora.year + 1),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final total = int.parse(_horasController.text.trim()) * 60 +
        int.parse(_minutosController.text.trim());
    if (total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica cuánto tiempo mover.')),
      );
      return;
    }
    // Un canje siempre consume saldo; un ajuste puede ir en los dos sentidos.
    final signo = _esCanje || !_aFavor ? -1 : 1;
    Navigator.of(context).pop(
      MovimientoBanco(
        fecha: DateFormat('yyyy-MM-dd').format(_fecha),
        minutos: signo * total,
        motivo: widget.motivo,
        nota: _notaController.text.trim().isEmpty
            ? null
            : _notaController.text.trim(),
        creadoEn: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esCanje ? 'Canjear horas' : 'Ajustar saldo'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _esCanje
                    ? 'Anota las horas acumuladas que gastaste: un día '
                        'compensatorio, salir temprano, llegar más tarde.'
                    : 'Corrige el saldo: horas que te reconocieron, o el '
                        'saldo que traías antes de instalar la app.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _horasController,
                      decoration: const InputDecoration(
                        labelText: 'Horas',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validarHoras,
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _minutosController,
                      decoration: const InputDecoration(
                        labelText: 'Minutos',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validarMinutos,
                    ),
                  ),
                ],
              ),
              if (!_esCanje) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _aFavor,
                  onChanged: (valor) => setState(() => _aFavor = valor),
                  title: Text(_aFavor ? 'Suma al saldo' : 'Resta del saldo'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _elegirFecha,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('d MMM yyyy', 'es').format(_fecha)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notaController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Anotar')),
      ],
    );
  }
}
