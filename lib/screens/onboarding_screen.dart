import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/prefs_service.dart';
import 'dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  late final TextEditingController _metaLJController;
  late final TextEditingController _metaViernesController;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _metaLJController =
        TextEditingController(text: PrefsService.defaultMetaLJ.toString());
    _metaViernesController = TextEditingController(
        text: PrefsService.defaultMetaViernes.toString());
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _metaLJController.dispose();
    _metaViernesController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final appProvider = context.read<AppProvider>();
    // Se arranca con la semana clásica —lunes a jueves y viernes— y no con
    // los siete días: quien acaba de instalar la app no tiene por qué llenar
    // una cifra por día para empezar. En Ajustes se afina día por día.
    await appProvider.guardarConfiguracion(
      nombre: _nombreController.text,
      metas: MetasSemana.clasica(
        lunesAJueves: double.parse(_metaLJController.text.replaceAll(',', '.')),
        viernes: double.parse(_metaViernesController.text.replaceAll(',', '.')),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  String? _validarNumero(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed > 24) return 'Valor inválido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/logo_mark.png', height: 120),
                  const SizedBox(height: 12),
                  Text(
                    'Bienvenido a Torniquete',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configura tus datos para empezar a controlar tu jornada',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
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
                        : const Text('Guardar y Continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
