import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'settings_cards.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _metaLJController;
  late final TextEditingController _metaViernesController;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final appProvider = context.read<AppProvider>();
    _nombreController = TextEditingController(text: appProvider.nombre ?? '');
    _metaLJController =
        TextEditingController(text: appProvider.metaLJHoras.toString());
    _metaViernesController =
        TextEditingController(text: appProvider.metaViernesHoras.toString());
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _metaLJController.dispose();
    _metaViernesController.dispose();
    super.dispose();
  }

  String? _validarNumero(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed > 24) return 'Valor inválido';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    await context.read<AppProvider>().guardarConfiguracion(
          nombre: _nombreController.text,
          metaLJHoras:
              double.parse(_metaLJController.text.replaceAll(',', '.')),
          metaViernesHoras:
              double.parse(_metaViernesController.text.replaceAll(',', '.')),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _metaLJController,
                decoration: const InputDecoration(
                  labelText: 'Meta de horas (Lunes a Jueves)',
                  prefixIcon: Icon(Icons.calendar_view_week),
                  border: OutlineInputBorder(),
                  suffixText: 'horas',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validarNumero,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _metaViernesController,
                decoration: const InputDecoration(
                  labelText: 'Meta de horas (Viernes)',
                  prefixIcon: Icon(Icons.weekend),
                  border: OutlineInputBorder(),
                  suffixText: 'horas',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validarNumero,
              ),
              const SizedBox(height: 32),
              const RecordatoriosCard(),
              const SizedBox(height: 16),
              const _UbicacionCard(),
              const SizedBox(height: 16),
              const SedeCard(),
              const SizedBox(height: 16),
              const AsuetosCard(),
              const SizedBox(height: 16),
              const DatosCard(),
              const SizedBox(height: 16),
              const _NotificacionesCard(),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Permite activar el guardado de la ubicación en cada marca. Está apagado
/// por defecto; al encenderlo se pide el permiso de ubicación al sistema.
class _UbicacionCard extends StatefulWidget {
  const _UbicacionCard();

  @override
  State<_UbicacionCard> createState() => _UbicacionCardState();
}

class _UbicacionCardState extends State<_UbicacionCard> {
  bool _procesando = false;

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), action: accion),
    );
  }

  Future<void> _cambiar(bool valor) async {
    final appProvider = context.read<AppProvider>();
    if (!valor) {
      await appProvider.setGuardarUbicacion(false);
      _avisar('Ya no se guardará la ubicación de las marcas.');
      return;
    }

    setState(() => _procesando = true);
    final resultado = await LocationService.instance.solicitarPermiso();
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case PermisoUbicacion.concedido:
        await appProvider.setGuardarUbicacion(true);
        _avisar('Listo: cada marca guardará dónde se registró.');
        break;
      case PermisoUbicacion.servicioApagado:
        _avisar(
          'El GPS del teléfono está apagado.',
          accion: SnackBarAction(
            label: 'Activar',
            onPressed: LocationService.instance.abrirAjustesDeUbicacion,
          ),
        );
        break;
      case PermisoUbicacion.denegadoParaSiempre:
        _avisar(
          'El permiso de ubicación está bloqueado para esta app.',
          accion: SnackBarAction(
            label: 'Ajustes',
            onPressed: LocationService.instance.abrirAjustesDeLaApp,
          ),
        );
        break;
      case PermisoUbicacion.denegado:
        _avisar('Sin permiso de ubicación no se puede guardar la evidencia.');
        break;
    }
  }

  Future<void> _borrarGuardadas() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar ubicaciones'),
        content: const Text(
          'Se eliminarán todas las ubicaciones guardadas junto a tus marcas. '
          'Las horas registradas no se tocan.',
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
    if (confirmado != true) return;
    await DbService.instance.borrarTodasLasUbicaciones();
    _avisar('Ubicaciones borradas.');
  }

  @override
  Widget build(BuildContext context) {
    final activo = context.watch<AppProvider>().guardarUbicacion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ubicación',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_procesando)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: activo,
              onChanged: _procesando ? null : _cambiar,
              title: const Text('Guardar ubicación'),
              subtitle: const Text(
                'Guarda dónde estabas al registrar cada marca, por si hay '
                'que justificar en una auditoría que llegaste al trabajo.',
              ),
            ),
            Text(
              'Las coordenadas se guardan solo en este teléfono, junto al '
              'historial, y nunca se envían a ningún servidor.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _borrarGuardadas,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Borrar ubicaciones guardadas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diagnóstico de notificaciones: deja ver si el sistema las tiene
/// habilitadas, si el recordatorio de salida está programado y permite
/// enviar una de prueba para comprobar que llegan.
class _NotificacionesCard extends StatefulWidget {
  const _NotificacionesCard();

  @override
  State<_NotificacionesCard> createState() => _NotificacionesCardState();
}

class _NotificacionesCardState extends State<_NotificacionesCard> {
  bool _cargando = true;
  bool _habilitadas = false;
  bool _exactas = false;
  bool _programado = false;

  @override
  void initState() {
    super.initState();
    _revisar();
  }

  Future<void> _revisar() async {
    setState(() => _cargando = true);
    final servicio = NotificationService.instance;
    final habilitadas = await servicio.notificacionesHabilitadas();
    final exactas = await servicio.puedeProgramarExactas();
    final programado = await servicio.recordatorioProgramado();
    if (!mounted) return;
    setState(() {
      _habilitadas = habilitadas;
      _exactas = exactas;
      _programado = programado;
      _cargando = false;
    });
  }

  Future<void> _pedirPermisos() async {
    await NotificationService.instance.pedirPermisos();
    await _revisar();
  }

  Future<void> _probar() async {
    final ok = await NotificationService.instance.programarPrueba();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Notificación de prueba programada: llega en 10 segundos.'
            : 'No se pudo programar la notificación de prueba.'),
      ),
    );
    await _revisar();
  }

  Widget _fila(String etiqueta, bool ok, String siOk, String siNo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 20,
            color: ok ? AppColors.cumplido : AppColors.pendiente,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(etiqueta)),
          Text(
            ok ? siOk : siNo,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notificaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Revisar de nuevo',
                  icon: const Icon(Icons.refresh),
                  onPressed: _cargando ? null : _revisar,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_cargando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              _fila('Permiso del sistema', _habilitadas, 'Activo', 'Bloqueado'),
              _fila('Alarmas exactas', _exactas, 'Permitidas', 'Bloqueadas'),
              _fila('Aviso de salida de hoy', _programado, 'Programado',
                  'Sin programar'),
              const SizedBox(height: 4),
              Text(
                'El aviso se programa al marcar la entrada de la tarde y '
                'suena 5 minutos antes de la hora estimada de salida.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (!_habilitadas || !_exactas)
                OutlinedButton.icon(
                  onPressed: _pedirPermisos,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Conceder permisos'),
                ),
              OutlinedButton.icon(
                onPressed: _probar,
                icon: const Icon(Icons.send),
                label: const Text('Enviar notificación de prueba'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
