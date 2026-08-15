import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

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
