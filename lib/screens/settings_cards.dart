import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/asuetos_service.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../services/location_service.dart';
import '../services/prefs_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import 'reports/export_report_sheet.dart';

/// Deja elegir si la app se ve clara, oscura o como esté el teléfono, y
/// cuánto se transparenta el widget de la pantalla de inicio.
class AparienciaCard extends StatelessWidget {
  const AparienciaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final modo = appProvider.modoTema;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6_outlined),
                const SizedBox(width: 10),
                Text(
                  'Apariencia',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'El cambio se ve al instante y se recuerda la próxima vez que '
              'abras la app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opcion in ModoTema.values)
                  ChoiceChip(
                    label: Text(opcion.etiqueta),
                    selected: modo == opcion,
                    onSelected: (elegido) {
                      if (elegido) appProvider.setModoTema(opcion);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              modo.descripcion,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 28),
            Text(
              'Fondo del widget de inicio',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opcion in FondoWidget.values)
                  ChoiceChip(
                    label: Text(opcion.etiqueta),
                    selected: appProvider.fondoWidget == opcion,
                    onSelected: (elegido) {
                      if (elegido) appProvider.setFondoWidget(opcion);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              appProvider.fondoWidget.descripcion,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Exportar el reporte de cumplimiento (PDF o Excel), volcar el historial a
/// CSV, hacer un respaldo completo y restaurarlo.
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

  /// Reporte para comprobar el cumplimiento del horario ante alguien más.
  /// Es la misma hoja que abre el botón de la pantalla de Reportes.
  Future<void> _exportarReporte() => _ejecutar(() async {
        final registros = await DbService.instance.getTodosLosRegistros();
        final movimientos = await DbService.instance.getMovimientos();
        if (!mounted) return;
        if (registros.isEmpty && movimientos.isEmpty) {
          _avisar('Todavía no hay marcaciones que reportar.');
          return;
        }
        final app = context.read<AppProvider>();
        await mostrarHojaExportar(
          context,
          registros: registros,
          movimientos: movimientos,
          metaDiariaMinutos: app.metaDiariaTipicaMinutos,
          nombre: app.nombre,
        );
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
            FilledButton.tonalIcon(
              onPressed: _ocupado ? null : _exportarReporte,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar reporte (PDF o Excel)'),
            ),
            const SizedBox(height: 8),
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
              'El reporte es lo que se entrega cuando hay que comprobar que '
              'se cumplió el horario: trae totales, porcentaje de '
              'cumplimiento y el detalle día por día. El CSV es el volcado '
              'crudo del historial, con punto y coma como separador, que es '
              'lo que espera Excel en español. El respaldo es un archivo '
              '.json que solo entiende esta app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asuetos de ley de El Salvador: qué régimen aplica, si la app los reconoce
/// y una revisión del historial ya guardado.
class AsuetosCard extends StatefulWidget {
  const AsuetosCard({super.key});

  @override
  State<AsuetosCard> createState() => _AsuetosCardState();
}

class _AsuetosCardState extends State<AsuetosCard> {
  bool _revisando = false;

  /// Busca en el historial los días que resultaron ser asueto y ofrece
  /// marcarlos. Solo toca días en blanco: ver [AsuetosService.candidatos].
  Future<void> _revisarHistorial() async {
    final appProvider = context.read<AppProvider>();
    final sector = appProvider.sectorAsuetos;
    if (sector == null) return;

    setState(() => _revisando = true);
    try {
      final registros = await DbService.instance.getTodosLosRegistros();
      final candidatos = AsuetosService.candidatos(registros, sector);
      if (!mounted) return;

      if (candidatos.isEmpty) {
        _avisar('No hay días en blanco que coincidan con un asueto.');
        return;
      }

      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            candidatos.length == 1
                ? 'Marcar un día como festivo'
                : 'Marcar ${candidatos.length} días como festivo',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Estos días quedaron guardados sin horas y coinciden con '
                  'un asueto. Al marcarlos dejarán de contar como días '
                  'laborales en blanco.',
                ),
                const SizedBox(height: 12),
                for (final c in candidatos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_fechaLegible(c.registro.fecha)} — ${c.asueto.nombre}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Marcar'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;

      final marcados = await AsuetosService.marcar(candidatos);
      if (!mounted) return;
      _avisar(
        marcados == 1
            ? 'Se marcó un día como festivo.'
            : 'Se marcaron $marcados días como festivo.',
      );
    } finally {
      if (mounted) setState(() => _revisando = false);
    }
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final activos = appProvider.asuetosActivos;
    final proximo = _proximoAsueto(appProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_outlined),
                const SizedBox(width: 10),
                Text(
                  'Asuetos de El Salvador',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'La app reconoce los asuetos de ley y no te exige horas en '
              'ellos. Las fiestas patronales y los días que dé la empresa '
              'siguen siendo manuales.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: activos,
              onChanged: appProvider.setAsuetosActivos,
              title: const Text('Reconocer los asuetos de ley'),
              subtitle: Text(_resumenProximo(activos, proximo)),
            ),
            if (activos) ...[
              const Divider(),
              Text(
                'Régimen que te aplica',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final sector in SectorLaboral.values)
                    ChoiceChip(
                      label: Text(sector.etiqueta),
                      selected: appProvider.sector == sector,
                      onSelected: (elegido) {
                        if (elegido) appProvider.setSector(sector);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                appProvider.sector.fundamento,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                appProvider.sector == SectorLaboral.publico
                    ? 'Incluye el 3, 5 y 6 de agosto.'
                    : 'De las fiestas agostinas solo cuenta el 6 de agosto.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _revisando ? null : _revisarHistorial,
                icon: _revisando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar el historial'),
              ),
              const SizedBox(height: 4),
              Text(
                'Busca días ya guardados que cayeron en asueto y quedaron '
                'sin horas. No toca los días en los que sí trabajaste.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Fecha en palabras, que es como se lee un calendario.
  static String _fechaLegible(String fecha) =>
      DateFormat("d 'de' MMMM 'de' y", 'es').format(DateTime.parse(fecha));

  /// Distingue el asueto de hoy del siguiente: decir "próximo" de un día
  /// que es hoy se lee como si faltara.
  String _resumenProximo(bool activos, Asueto? proximo) {
    if (!activos || proximo == null) return 'Los asuetos no afectarán tus metas';
    final esHoy = proximo.fecha == FestivosSV.clave(DateTime.now());
    final cuando = esHoy ? 'Hoy' : 'Próximo';
    return '$cuando: ${proximo.nombre}, ${_fechaLegible(proximo.fecha)}';
  }

  /// El siguiente asueto a partir de hoy, para que el ajuste diga algo útil
  /// en vez de solo estar encendido.
  Asueto? _proximoAsueto(AppProvider appProvider) {
    final sector = appProvider.sectorAsuetos;
    if (sector == null) return null;
    final hoy = DateTime.now();
    final proximos = FestivosSV.entre(
      hoy,
      DateTime(hoy.year + 1, hoy.month, hoy.day),
      sector: sector,
    );
    return proximos.isEmpty ? null : proximos.first;
  }
}
