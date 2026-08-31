import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/registro_provider.dart';
import '../services/asuetos_service.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../services/descuento_almuerzo_service.dart';
import '../services/geocerca_service.dart';
import '../services/location_service.dart';
import '../services/prefs_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import 'reports/export_report_sheet.dart';

/// Almuerzo que la empresa descuenta salgas o no a comer.
///
/// Apagado por defecto (cero minutos): sin configurarlo la app cuenta el
/// almuerzo que se tomó de verdad, que es como funcionaba antes.
class DescuentoAlmuerzoCard extends StatefulWidget {
  const DescuentoAlmuerzoCard({super.key});

  @override
  State<DescuentoAlmuerzoCard> createState() => _DescuentoAlmuerzoCardState();
}

class _DescuentoAlmuerzoCardState extends State<DescuentoAlmuerzoCard> {
  /// Valor que se está eligiendo con el dedo puesto sobre el deslizador. Se
  /// guarda al soltar y no en cada paso: el ajuste reescribe el día en curso.
  int? _arrastrado;

  bool _revisando = false;

  static String _legible(int minutos) {
    if (minutos <= 0) return 'Sin descuento fijo';
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Recalcula los días ya guardados con el descuento vigente.
  ///
  /// Va detrás de una confirmación que dice cuánto se mueve el banco de horas
  /// porque reescribe el pasado, que es justo lo que la app evita hacer sola:
  /// cada día se sella con la regla que estaba vigente cuando se trabajó.
  Future<void> _aplicarAlHistorial() async {
    final appProvider = context.read<AppProvider>();
    final descuento = appProvider.descuentoAlmuerzoMinutos;

    setState(() => _revisando = true);
    try {
      final registros = await DbService.instance.getTodosLosRegistros();
      final revision = DescuentoAlmuerzoService.revisar(
        registros,
        descuento: descuento,
        hoy: RegistroProvider.fechaHoy(),
      );
      if (!mounted) return;

      if (revision.sinTrabajo) {
        _avisar('Todos los días guardados ya usan este descuento.');
        return;
      }

      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aplicar al historial'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_encabezado(revision.aSellar.length, descuento)),
                const SizedBox(height: 12),
                Text(_resumenDelCambio(revision)),
                if (revision.cambios.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final cambio in revision.cambios.take(_maxPrevisualizados))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_fechaLegible(cambio.registro.fecha)}: '
                        '${TimeUtils.formatDurationMinutes(cambio.minutosAntes)} '
                        '→ '
                        '${TimeUtils.formatDurationMinutes(cambio.minutosDespues)}',
                      ),
                    ),
                  if (revision.cambios.length > _maxPrevisualizados)
                    Text(
                      'y ${revision.cambios.length - _maxPrevisualizados} días más.',
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Recalcular'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;

      final dias = await DescuentoAlmuerzoService.aplicar(revision);
      if (!mounted) return;
      _avisar(dias == 1
          ? 'Se recalculó un día del historial.'
          : 'Se recalcularon $dias días del historial.');
    } finally {
      if (mounted) setState(() => _revisando = false);
    }
  }

  /// Qué se va a recalcular. Poner el descuento en cero no es "recalcular con
  /// nada": es dejar de descontar, y así se dice.
  static String _encabezado(int dias, int descuento) {
    final uno = dias == 1;
    final cuantos = uno ? 'Un día guardado' : '$dias días guardados';
    return descuento <= 0
        ? '$cuantos ${uno ? 'dejará' : 'dejarán'} de descontar un almuerzo '
            'fijo.'
        : '$cuantos ${uno ? 'se recalculará' : 'se recalcularán'} descontando '
            '${_legible(descuento)} de almuerzo.';
  }

  /// Cuántos días cambian de verdad y hacia dónde se mueve el banco. Es el
  /// número que importa: el resto solo cambia de etiqueta.
  static String _resumenDelCambio(RevisionDescuento revision) {
    if (revision.cambios.isEmpty) {
      return 'Ninguno cambia de horas: son días en blanco, justificados o con '
          'un almuerzo que ya duraba más que el descuento. Se actualizan de '
          'todos modos para que se recalculen bien si los editas.';
    }
    final total = revision.diferenciaMinutos;
    final cuantos = revision.cambios.length == 1
        ? 'Uno cambia de horas'
        : '${revision.cambios.length} cambian de horas';
    return '$cuantos y tu banco ${total < 0 ? 'baja' : 'sube'} '
        '${TimeUtils.formatDurationMinutes(total.abs())}.';
  }

  static const int _maxPrevisualizados = 8;

  static String _fechaLegible(String fecha) =>
      DateFormat("d 'de' MMM 'de' y", 'es').format(DateTime.parse(fecha));

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final minutos = _arrastrado ?? appProvider.descuentoAlmuerzoMinutos;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_outlined),
                const SizedBox(width: 10),
                Text(
                  'Almuerzo descontado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Hay empresas que descuentan un almuerzo fijo salgas o no a '
              'comer. Con esto configurado la app lo resta del día aunque no '
              'marques la salida a almorzar, así la hora de salida deja de '
              'adelantarse por no ir a comer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              _legible(minutos),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Slider(
              value: minutos
                  .clamp(0, PrefsService.maxDescuentoAlmuerzo)
                  .toDouble(),
              min: 0,
              max: PrefsService.maxDescuentoAlmuerzo.toDouble(),
              divisions: PrefsService.maxDescuentoAlmuerzo ~/ 5,
              label: _legible(minutos),
              onChanged: (valor) =>
                  setState(() => _arrastrado = valor.round()),
              onChangeEnd: (valor) async {
                await appProvider.setDescuentoAlmuerzo(valor.round());
                if (mounted) setState(() => _arrastrado = null);
              },
            ),
            Text(
              minutos <= 0
                  ? 'Se cuenta el almuerzo que realmente tomes: la pausa que '
                      'hagas entre las 11:30 y las 2.'
                  : 'Es un mínimo: si almuerzas más de ${_legible(minutos)}, '
                      'se descuenta el tiempo que de verdad tomaste. Si '
                      'almuerzas menos —o no sales— se descuenta igual. Solo '
                      'cuenta la pausa que hagas entre las 11:30 y las 2; una '
                      'salida a media mañana es tiempo fuera, pero no es el '
                      'almuerzo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Cambiarlo afecta al día de hoy y a los que registres después. '
              'Los días ya guardados conservan el descuento con el que se '
              'trabajaron, igual que conservan su meta de horas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _revisando ? null : _aplicarAlHistorial,
              icon: _revisando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history_toggle_off),
              label: const Text('Aplicar al historial'),
            ),
            const SizedBox(height: 4),
            Text(
              'Si tu empresa ya descontaba el almuerzo antes de que '
              'configuraras esto, el historial quedó con horas de más. Esto '
              'lo recalcula, diciéndote primero cuánto se mueve tu banco de '
              'horas. No toca el día de hoy, que ya sigue el ajuste.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Avisos para no olvidar marcar la entrada, la pausa del almuerzo y el
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
    final sede = appProvider.sede;

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
              sede.diasOficina.isEmpty
                  ? 'Sin ningún día marcado en Sede no suena ningún aviso.'
                  : 'Suenan ${sede.diasOficinaLegible.toLowerCase()}, los días '
                      'que marcaste en Sede. El de hoy no suena si esa marca '
                      'ya está hecha.',
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

class _SedeCardState extends State<SedeCard> with WidgetsBindingObserver {
  bool _capturando = false;
  bool _procesandoLlegada = false;

  /// Radio que se está eligiendo con el dedo puesto sobre el deslizador.
  int? _radioArrastrado;

  /// Lo que Android dice que está vigilando de verdad, que no siempre
  /// coincide con lo que pide el interruptor.
  EstadoGeocerca _vigilancia = EstadoGeocerca.apagada;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisarVigilancia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// El permiso de "todo el tiempo" se concede fuera de la app, en los
  /// ajustes de Android. Al volver hay que reponer la geocerca y releer el
  /// estado, o el usuario vería el permiso dado y la vigilancia apagada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _revisarVigilancia();
  }

  Future<void> _revisarVigilancia() async {
    if (!mounted) return;
    await context.read<AppProvider>().resincronizarGeocerca();
    final estado = await GeocercaService.instance.estado();
    if (!mounted) return;
    setState(() => _vigilancia = estado);
  }

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

  /// Enciende o apaga el aviso de llegada.
  ///
  /// Encenderlo pide la ubicación "todo el tiempo", que es la única con la
  /// que Android dispara una geocerca teniendo la app cerrada. Si el usuario
  /// solo concede "mientras se usa la app" la preferencia se guarda igual:
  /// así el ajuste recuerda lo que pidió y la vigilancia arranca sola en
  /// cuanto suba el permiso desde los ajustes del sistema.
  Future<void> _cambiarAvisoLlegada(bool valor) async {
    final appProvider = context.read<AppProvider>();
    if (!valor) {
      await appProvider.guardarSede(
        appProvider.sede.copyWith(avisarAlLlegar: false),
      );
      await _revisarVigilancia();
      _avisar('Ya no se te avisará al llegar a la sede.');
      return;
    }

    setState(() => _procesandoLlegada = true);
    try {
      final permiso = await LocationService.instance.solicitarPermisoDeFondo();
      if (!mounted) return;
      final vigilando = await appProvider.guardarSede(
        appProvider.sede.copyWith(avisarAlLlegar: true),
      );
      if (!mounted) return;
      await _revisarVigilancia();
      if (!mounted) return;

      switch (permiso) {
        case PermisoDeFondo.concedido:
          _avisar(vigilando
              ? 'Listo: al llegar a la sede te preguntaré si marco.'
              : 'Android no aceptó vigilar la sede. Revisa que los servicios '
                  'de Google Play estén al día.');
        case PermisoDeFondo.soloEnUso:
          _avisar(
            'Falta conceder la ubicación como "Permitir todo el tiempo": sin '
            'ella Android no avisa con la app cerrada.',
            accion: SnackBarAction(
              label: 'Ajustes',
              onPressed: LocationService.instance.abrirAjustesDeLaApp,
            ),
          );
        case PermisoDeFondo.servicioApagado:
          _avisar(
            'El GPS del teléfono está apagado.',
            accion: SnackBarAction(
              label: 'Activar',
              onPressed: LocationService.instance.abrirAjustesDeUbicacion,
            ),
          );
        case PermisoDeFondo.sinPermiso:
          _avisar(
            'Sin permiso de ubicación no se puede vigilar la llegada.',
            accion: SnackBarAction(
              label: 'Ajustes',
              onPressed: LocationService.instance.abrirAjustesDeLaApp,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _procesandoLlegada = false);
    }
  }

  /// Enciende o apaga un día de oficina. Guardar la sede vuelve a hablar con
  /// Android, que es lo que hace falta cuando la semana se queda sin días —se
  /// retira la geocerca— o recupera el primero.
  Future<void> _cambiarDiaOficina(int dia, bool elegido) async {
    final appProvider = context.read<AppProvider>();
    final dias = {...appProvider.sede.diasOficina};
    if (elegido) {
      dias.add(dia);
    } else {
      dias.remove(dia);
    }
    await appProvider.guardarSede(
      appProvider.sede.copyWith(diasOficina: dias),
    );
    await _revisarVigilancia();
  }

  /// Qué está pasando de verdad con la vigilancia, dicho en una línea.
  String _estadoLlegada(SedeConfig sede) {
    if (!sede.tieneCoordenadas) return 'Primero guarda dónde queda la sede.';
    if (!sede.avisarAlLlegar) {
      return 'Al quedarte dentro del radio, una notificación te pregunta si '
          'marcas la entrada o si continúas una pausa que dejaste abierta.';
    }
    if (sede.diasOficina.isEmpty) {
      return 'No hay ningún día de oficina marcado, así que no se avisará.';
    }
    if (_vigilancia.vigilando) {
      return 'Android está vigilando la sede: el aviso llega aunque la app '
          'esté cerrada.';
    }
    if (!_vigilancia.permisoDeFondo) {
      return 'Falta la ubicación "Permitir todo el tiempo". Sin ella Android '
          'no despierta la app al llegar.';
    }
    return 'Pedido, pero el sistema todavía no confirma la vigilancia.';
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
                if (_capturando || _procesandoLlegada)
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sede.avisarAlLlegar,
              onChanged: sede.tieneCoordenadas && !_procesandoLlegada
                  ? _cambiarAvisoLlegada
                  : null,
              title: const Text('Avisarme al llegar para marcar'),
              subtitle: Text(_estadoLlegada(sede)),
            ),
            const SizedBox(height: 4),
            Text(
              'Días que vas a la sede',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var dia = 1; dia <= 7; dia++)
                  FilterChip(
                    label: Text(SedeConfig.abreviaturasDias[dia - 1]),
                    selected: sede.diasOficina.contains(dia),
                    onSelected: (elegido) => _cambiarDiaOficina(dia, elegido),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sede.diasOficina.isEmpty
                  ? 'Sin ningún día marcado no llega nada: ni el recordatorio '
                      'de marca ni el aviso al llegar.'
                  : '${sede.diasOficinaLegible}. Los demás días no se te '
                      'recuerda marcar ni se te pregunta nada al pasar por '
                      'la sede.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            if (sede.avisarAlLlegar && !_vigilancia.permisoDeFondo)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: LocationService.instance.abrirAjustesDeLaApp,
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Permitir ubicación todo el tiempo'),
                ),
              ),
            if (sede.avisarAlLlegar)
              Text(
                'Se pregunta una sola vez al día por cada marca, y solo tras '
                'un rato dentro del radio, para que pasar cerca de camino a '
                'otro sitio no gaste el aviso.',
                style: Theme.of(context).textTheme.bodySmall,
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
                'Radio: ${_radioArrastrado ?? sede.radioMetros} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Slider(
                value: (_radioArrastrado ?? sede.radioMetros)
                    .clamp(SedeConfig.minRadioMetros, SedeConfig.maxRadioMetros)
                    .toDouble(),
                min: SedeConfig.minRadioMetros.toDouble(),
                max: SedeConfig.maxRadioMetros.toDouble(),
                divisions:
                    (SedeConfig.maxRadioMetros - SedeConfig.minRadioMetros) ~/ 50,
                label: '${_radioArrastrado ?? sede.radioMetros} m',
                // Mientras se arrastra el valor solo vive aquí: guardar en
                // cada paso volvería a registrar la geocerca decenas de veces
                // por un gesto, y el sistema solo necesita la definitiva.
                onChanged: (valor) =>
                    setState(() => _radioArrastrado = valor.round()),
                onChangeEnd: (valor) async {
                  await appProvider
                      .guardarSede(sede.copyWith(radioMetros: valor.round()));
                  if (mounted) setState(() => _radioArrastrado = null);
                },
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
