import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../services/location_service.dart';
import '../services/prefs_service.dart';
import '../utils/time_utils.dart';

/// Avisos para no olvidar marcar la entrada, la salida a almuerzo y el
/// regreso. Apagados por defecto: son útiles solo si el horario es estable.
class RecordatoriosCard extends StatelessWidget {
  const RecordatoriosCard({super.key});

  Future<void> _elegirHora(
    BuildContext context,
    RecordatorioConfig config,
  ) async {
    final appProvider = context.read<AppProvider>();
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeUtils.fromMinutes(config.minutos),
      helpText: config.tipo.etiqueta,
    );
    if (elegida == null) return;
    await appProvider.guardarRecordatorio(
      config.copyWith(minutos: TimeUtils.toMinutes(elegida), activo: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final recordatorios = appProvider.recordatorios;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm_outlined),
                const SizedBox(width: 10),
                Text(
                  'Recordatorios de marca',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Avisos de lunes a viernes. El de hoy no suena si esa marca ya '
              'está hecha.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final tipo in RecordatorioTipo.values)
              if (recordatorios[tipo] case final config?)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: config.activo,
                  onChanged: (valor) => appProvider.guardarRecordatorio(
                    config.copyWith(activo: valor),
                  ),
                  title: Text(config.tipo.etiqueta),
                  subtitle: Text(
                    'A las ${TimeUtils.formatAmPm(TimeUtils.fromMinutes(config.minutos))}',
                  ),
                  secondary: IconButton(
                    tooltip: 'Cambiar la hora',
                    icon: const Icon(Icons.schedule),
                    onPressed: () => _elegirHora(context, config),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Geocerca de la sede: guarda dónde queda el trabajo y avisa cuando una
/// marca se registra lejos de ahí.
class SedeCard extends StatefulWidget {
  const SedeCard({super.key});

  @override
  State<SedeCard> createState() => _SedeCardState();
}

class _SedeCardState extends State<SedeCard> {
  bool _capturando = false;

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), action: accion),
    );
  }

  /// Toma la posición actual como sede. Es la forma menos frustrante de
  /// configurarla: estando en el trabajo, un toque y listo.
  Future<void> _usarUbicacionActual() async {
    final appProvider = context.read<AppProvider>();
    setState(() => _capturando = true);
    try {
      final permiso = await LocationService.instance.solicitarPermiso();
      if (!mounted) return;
      switch (permiso) {
        case PermisoUbicacion.concedido:
          break;
        case PermisoUbicacion.servicioApagado:
          _avisar(
            'El GPS del teléfono está apagado.',
            accion: SnackBarAction(
              label: 'Activar',
              onPressed: LocationService.instance.abrirAjustesDeUbicacion,
            ),
          );
          return;
        case PermisoUbicacion.denegadoParaSiempre:
          _avisar(
            'El permiso de ubicación está bloqueado para esta app.',
            accion: SnackBarAction(
              label: 'Ajustes',
              onPressed: LocationService.instance.abrirAjustesDeLaApp,
            ),
          );
          return;
        case PermisoUbicacion.denegado:
          _avisar('Sin permiso de ubicación no se puede guardar la sede.');
          return;
      }

      final posicion = await LocationService.instance.capturar();
      if (!mounted) return;
      if (posicion == null) {
        _avisar('No se pudo leer la ubicación. Inténtalo junto a una ventana.');
        return;
      }
      await appProvider.guardarSede(
        appProvider.sede.copyWith(
          latitud: posicion.latitude,
          longitud: posicion.longitude,
          activa: true,
        ),
      );
      if (!mounted) return;
      _avisar('Sede guardada en tu ubicación actual.');
    } finally {
      if (mounted) setState(() => _capturando = false);
    }
  }

  Future<void> _editarNombre() async {
    final appProvider = context.read<AppProvider>();
    final controller =
        TextEditingController(text: appProvider.sede.nombre ?? '');
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre de la sede'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Oficina principal, Planta norte...',
            border: OutlineInputBorder(),
          ),
          maxLength: 40,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nombre == null) return;
    await appProvider.guardarSede(appProvider.sede.copyWith(nombre: nombre));
  }

  Future<void> _olvidar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Olvidar sede'),
        content: const Text(
          'Se borrarán las coordenadas guardadas y dejarás de recibir avisos '
          'cuando marques lejos del trabajo. Las marcas no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Olvidar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await context.read<AppProvider>().borrarSede();
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final sede = appProvider.sede;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.business_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sede',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_capturando)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sede.activa,
              // Sin coordenadas no hay nada contra qué comparar.
              onChanged: sede.tieneCoordenadas
                  ? (valor) =>
                      appProvider.guardarSede(sede.copyWith(activa: valor))
                  : null,
              title: const Text('Avisarme si marco lejos del trabajo'),
              subtitle: Text(
                sede.tieneCoordenadas
                    ? 'Solo es un aviso: la marca se guarda igual.'
                    : 'Primero guarda dónde queda la sede.',
              ),
            ),
            if (sede.tieneCoordenadas) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline),
                title: Text(sede.nombre?.trim().isNotEmpty == true
                    ? sede.nombre!.trim()
                    : 'Sin nombre'),
                subtitle: Text(
                  '${sede.latitud!.toStringAsFixed(5)}, '
                  '${sede.longitud!.toStringAsFixed(5)}',
                ),
                trailing: IconButton(
                  tooltip: 'Cambiar el nombre',
                  icon: const Icon(Icons.edit),
                  onPressed: _editarNombre,
                ),
              ),
              Text(
                'Radio: ${sede.radioMetros} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Slider(
                value: sede.radioMetros
                    .clamp(SedeConfig.minRadioMetros, SedeConfig.maxRadioMetros)
                    .toDouble(),
                min: SedeConfig.minRadioMetros.toDouble(),
                max: SedeConfig.maxRadioMetros.toDouble(),
                divisions:
                    (SedeConfig.maxRadioMetros - SedeConfig.minRadioMetros) ~/ 50,
                label: '${sede.radioMetros} m',
                onChanged: (valor) => appProvider.guardarSede(
                  sede.copyWith(radioMetros: valor.round()),
                ),
              ),
              Text(
                'Dentro de un edificio el GPS se desvía con facilidad: un '
                'radio corto produce falsas alertas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _capturando ? null : _usarUbicacionActual,
              icon: const Icon(Icons.my_location),
              label: Text(sede.tieneCoordenadas
                  ? 'Actualizar con mi ubicación actual'
                  : 'Usar mi ubicación actual como sede'),
            ),
            if (sede.tieneCoordenadas)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _olvidar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Olvidar sede'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Exportar el historial a CSV, hacer un respaldo completo y restaurarlo.
class DatosCard extends StatefulWidget {
  const DatosCard({super.key});

  @override
  State<DatosCard> createState() => _DatosCardState();
}

class _DatosCardState extends State<DatosCard> {
  bool _ocupado = false;

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      await accion();
    } catch (e) {
      _avisar('No se pudo completar la operación: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _exportarCsv() => _ejecutar(() async {
        await BackupService.instance.exportarCsv();
      });

  Future<void> _respaldar() => _ejecutar(() async {
        await BackupService.instance.crearRespaldo();
      });

  Future<void> _restaurar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: const Text(
          'Se reemplazará TODO lo que hay en la app —días, ubicaciones y '
          'movimientos del banco— por el contenido del respaldo. Lo que no '
          'esté en el archivo se pierde.\n\n'
          'Si tienes datos recientes, haz primero un respaldo de lo actual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reemplazar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    await _ejecutar(() async {
      final resumen = await BackupService.instance.restaurarDesdeArchivo();
      if (!mounted) return;
      switch (resumen.resultado) {
        case ResultadoRestauracion.ok:
          // La configuración pudo cambiar con el respaldo.
          await context.read<AppProvider>().cargar();
          _avisar('Restaurados ${resumen.dias} días, '
              '${resumen.movimientos} movimientos y '
              '${resumen.ubicaciones} ubicaciones.');
          break;
        case ResultadoRestauracion.cancelado:
          break;
        case ResultadoRestauracion.archivoInvalido:
          _avisar('Ese archivo no es un respaldo de Torniquete.');
          break;
        case ResultadoRestauracion.versionNoSoportada:
          _avisar(resumen.detalle ??
              'El respaldo es de una versión más nueva de la app.');
          break;
        case ResultadoRestauracion.error:
          _avisar(resumen.detalle ?? 'No se pudo restaurar el respaldo.');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.save_alt_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Datos y respaldo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_ocupado)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Todo se guarda solo en este teléfono. Si lo pierdes o lo '
              'formateas sin respaldo, el historial se va con él.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _exportarCsv,
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Exportar historial a CSV'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _respaldar,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Crear respaldo completo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _restaurar,
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar desde un respaldo'),
            ),
            const SizedBox(height: 8),
            Text(
              'El CSV usa punto y coma como separador, que es lo que espera '
              'Excel en español. El respaldo es un archivo .json que solo '
              'entiende esta app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
