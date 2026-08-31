import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../providers/app_provider.dart';
import '../providers/historial_provider.dart';
import '../providers/registro_provider.dart';
import '../services/db_service.dart';
import '../services/pausas_service.dart';
import '../services/reports_service.dart';
import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import 'edit_day_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistorialProvider _historial = HistorialProvider();

  @override
  void initState() {
    super.initState();
    _historial.recargar();
  }

  @override
  void dispose() {
    _historial.dispose();
    super.dispose();
  }

  /// Salta la lista al mes que se elija. Se pide un día porque Material no
  /// trae un selector de mes; del elegido solo se usa el mes.
  Future<void> _elegirMes() async {
    final ahora = DateTime.now();
    final elegido = await showDatePicker(
      context: context,
      initialDate: _historial.mes ?? ahora,
      firstDate: DateTime(ahora.year - 5),
      lastDate: ahora,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Salta al mes que quieras revisar',
    );
    if (elegido == null) return;
    await _historial.irAlMes(elegido);
  }

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  Future<void> _confirmarReinicio(Registro registro) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar día'),
        content: Text(
          'Se borrarán todas las marcas de ${_formatearFecha(registro.fecha)}. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    await DbService.instance.eliminarRegistro(registro.fecha);

    if (registro.fecha == RegistroProvider.fechaHoy() && mounted) {
      final appProvider = context.read<AppProvider>();
      final metaMinutos =
          appProvider.metaMinutosParaDia(DateTime.now().weekday);
      await context.read<RegistroProvider>().cargarRegistroDeHoy(
            metaMinutos,
            nombreUsuario: appProvider.nombre,
          );
    }

    if (!mounted) return;
    await _historial.recargar();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Día ${_formatearFecha(registro.fecha)} reiniciado')),
    );
  }

  Future<void> _agregarDia() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(ahora.year - 2),
      lastDate: ahora,
      helpText: 'Selecciona el día a registrar',
    );
    if (fecha == null || !mounted) return;

    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final existente = await DbService.instance.getRegistroPorFecha(fechaStr);
    if (!mounted) return;

    final appProvider = context.read<AppProvider>();
    final registro = existente ??
        Registro(
          fecha: fechaStr,
          metaMinutos: appProvider.metaMinutosParaDia(fecha.weekday),
          descuentoAlmuerzoMinutos: appProvider.descuentoAlmuerzoMinutos,
        );

    await _editarDia(registro);
  }

  Future<void> _editarDia(Registro registro) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditDayScreen(registro: registro)),
    );
    if (guardado != true) return;

    if (registro.fecha == RegistroProvider.fechaHoy() && mounted) {
      final appProvider = context.read<AppProvider>();
      final metaMinutos =
          appProvider.metaMinutosParaDia(DateTime.now().weekday);
      await context.read<RegistroProvider>().cargarRegistroDeHoy(
            metaMinutos,
            nombreUsuario: appProvider.nombre,
          );
    }

    if (!mounted) return;
    await _historial.recargar();

    if (!mounted) return;
    _avisarSiNoSeVe(registro);
  }

  /// Un día guardado fuera del trozo que se está mirando no cambia nada en
  /// pantalla, y parece que no se guardó. Pasa al agregar un día de otro mes
  /// o de un tipo que el filtro deja fuera.
  void _avisarSiNoSeVe(Registro registro) {
    if (_historial.dias.any((d) => d.fecha == registro.fecha)) return;
    final dia = DateTime.tryParse(registro.fecha);
    if (dia == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('El día se guardó, pero no está a la vista.'),
        action: SnackBarAction(
          label: 'Ir a ese día',
          onPressed: () => _historial.mostrarMesDe(dia),
        ),
      ),
    );
  }

  /// Línea de resumen del día: cuánto se trabajó y contra qué meta, o por
  /// qué ese día no pide horas.
  String _resumenHoras(
    Registro r,
    int minutos,
    bool justificado,
    bool sinRegistro,
  ) {
    if (justificado) {
      return minutos > 0
          ? '${TimeUtils.formatDurationMinutes(minutos)} trabajados, '
              'todo como tiempo extra'
          : 'Sin meta de horas';
    }
    if (sinRegistro) return 'Sin horas registradas';
    return '${TimeUtils.formatDurationMinutes(minutos)} '
        'de ${TimeUtils.formatDurationMinutes(r.metaMinutos)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarDia,
        icon: const Icon(Icons.add),
        label: const Text('Agregar día'),
      ),
      body: ListenableBuilder(
        listenable: _historial,
        builder: (context, _) => Column(
          children: [
            _BarraFiltros(historial: _historial, onElegirMes: _elegirMes),
            const Divider(height: 1),
            Expanded(child: _lista()),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    final dias = _historial.dias;
    if (dias.isEmpty) {
      if (_historial.cargando) {
        return const Center(child: CircularProgressIndicator());
      }
      return _SinResultados(
        filtrado: _historial.filtrado,
        onLimpiar: _historial.limpiarFiltros,
      );
    }

    // Una fila de más al final mientras quede historial por traer.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: dias.length + (_historial.hayMas ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index < dias.length) return _tarjetaDia(dias[index]);
        // Si esta fila se está construyendo, el usuario ya va llegando al
        // final de lo cargado: se pide la página siguiente. ListView la
        // construye un poco antes de que se vea, así que la espera casi
        // siempre queda fuera de pantalla.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _historial.cargarMas());
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _tarjetaDia(Registro r) {
    final asueto = context.read<AppProvider>().asuetoEnClave(r.fecha);
    final minutos = ReportsService.minutosTrabajados(r);
    final justificado = r.tipoDia.esJustificado;
    // Un festivo o unas vacaciones no son un día "sin registrar": no falta
    // nada por marcar en ellos.
    final sinRegistro = !justificado && minutos <= 0;
    final cumplida =
        justificado || (!sinRegistro && minutos >= r.metaEfectivaMinutos);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editarDia(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _formatearFecha(r.fecha),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    justificado
                        ? Icons.event_available
                        : (cumplida
                            ? Icons.check_circle
                            : (sinRegistro
                                ? Icons.remove_circle_outline
                                : Icons.error_outline)),
                    color: justificado
                        ? AppColors.neutroDe(context)
                        : (cumplida
                            ? AppColors.cumplidoDe(context)
                            : (sinRegistro
                                ? AppColors.neutroDe(context)
                                : AppColors.pendienteDe(context))),
                  ),
                  IconButton(
                    tooltip: 'Editar día',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editarDia(r),
                  ),
                  IconButton(
                    tooltip: 'Reiniciar día',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () => _confirmarReinicio(r),
                  ),
                ],
              ),
              if (justificado ||
                  asueto != null ||
                  (r.nota?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                _EtiquetaDia(registro: r, asueto: asueto),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Marca('Entrada', TimeUtils.formatHHmm(r.entrada1)),
                  _Marca('Pausas', PausasService.resumen(r.pausas)),
                  _Marca('Salida real', TimeUtils.formatHHmm(r.salidaReal)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _resumenHoras(r, minutos, justificado, sinRegistro),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El mes que se está mirando y los tipos de día que se dejan pasar.
class _BarraFiltros extends StatelessWidget {
  final HistorialProvider historial;
  final VoidCallback onElegirMes;

  const _BarraFiltros({required this.historial, required this.onElegirMes});

  @override
  Widget build(BuildContext context) {
    final mes = historial.mes;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          InputChip(
            avatar: const Icon(Icons.event, size: 18),
            label: Text(mes == null ? 'Cualquier mes' : _nombreDelMes(mes)),
            onPressed: onElegirMes,
            // La X solo aparece cuando hay un mes que quitar.
            onDeleted: mes == null ? null : historial.quitarMes,
          ),
          const SizedBox(width: 8),
          for (final tipo in TipoDia.values) ...[
            FilterChip(
              label: Text(tipo.etiqueta),
              selected: historial.tipos.contains(tipo),
              onSelected: (marcado) {
                final tipos = {...historial.tipos};
                if (marcado) {
                  tipos.add(tipo);
                } else {
                  tipos.remove(tipo);
                }
                historial.filtrarPor(tipos);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// "Agosto de 2026".
  static String _nombreDelMes(DateTime mes) {
    final texto = DateFormat("MMMM 'de' yyyy", 'es').format(mes);
    return texto[0].toUpperCase() + texto.substring(1);
  }
}

/// Ni un día que enseñar: o todavía no hay historial, o el filtro se lo comió
/// entero, que son dos cosas distintas.
class _SinResultados extends StatelessWidget {
  final bool filtrado;
  final VoidCallback onLimpiar;

  const _SinResultados({required this.filtrado, required this.onLimpiar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filtrado
                  ? 'Ningún día coincide con lo que estás buscando.'
                  : 'Aún no hay registros guardados.',
              textAlign: TextAlign.center,
            ),
            if (filtrado)
              TextButton(
                onPressed: onLimpiar,
                child: const Text('Quitar los filtros'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  final String label;

  /// Ya formateado por quien llama: una hora suelta o el resumen de las
  /// pausas, que no es una hora.
  final String valor;

  const _Marca(this.label, this.valor);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $valor',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// Distintivo del tipo de día y su nota, para reconocer de un vistazo por
/// qué un día del historial no tiene horas.
class _EtiquetaDia extends StatelessWidget {
  final Registro registro;

  /// El asueto de ley que cae ese día, si lo hay.
  final Asueto? asueto;

  const _EtiquetaDia({required this.registro, this.asueto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nota = registro.nota?.trim();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (registro.tipoDia.esJustificado)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              registro.tipoDia.etiqueta,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        // El asueto solo se anuncia si el día no está ya marcado: en cuanto
        // se marca, la etiqueta del tipo de día y la nota lo dicen mejor.
        if (asueto != null && !registro.tipoDia.esJustificado)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Asueto: ${asueto!.nombre}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        if (nota != null && nota.isNotEmpty)
          Text(nota, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
