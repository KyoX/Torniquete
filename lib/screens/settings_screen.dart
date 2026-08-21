import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/notification_service.dart';

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
            color: ok ? Colors.green : Colors.orange,
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
