import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/movimiento_banco.dart';
import '../../models/registro.dart';
import '../../providers/app_provider.dart';
import '../../services/db_service.dart';
import 'balance_report_tab.dart';
import 'daily_report_tab.dart';
import 'monthly_report_tab.dart';
import 'projection_report_tab.dart';
import 'weekly_report_tab.dart';

/// Todo lo que las pestañas de reportes necesitan de la base de datos.
class _DatosReportes {
  final List<Registro> registros;
  final List<MovimientoBanco> movimientos;

  const _DatosReportes({required this.registros, required this.movimientos});

  /// Sin días ni movimientos no hay nada que reportar.
  bool get vacio => registros.isEmpty && movimientos.isEmpty;
}

/// Pantalla de reportes: cumplimiento diario, semanal, mensual, proyección
/// del mes y banco de horas acumulado. Carga los registros una sola vez y
/// los comparte entre las pestañas.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<_DatosReportes> _datosFuture;

  @override
  void initState() {
    super.initState();
    _datosFuture = _cargar();
  }

  Future<_DatosReportes> _cargar() async {
    return _DatosReportes(
      registros: await DbService.instance.getTodosLosRegistros(),
      movimientos: await DbService.instance.getMovimientos(),
    );
  }

  /// Vuelve a leer la base de datos tras anotar o borrar un movimiento del
  /// banco de horas.
  Future<void> _recargar() async {
    final datos = await _cargar();
    if (!mounted) return;
    setState(() => _datosFuture = Future.value(datos));
  }

  @override
  Widget build(BuildContext context) {
    final metaDiaria = context.watch<AppProvider>().metaDiariaTipicaMinutos;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reportes'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Diario'),
              Tab(text: 'Semanal'),
              Tab(text: 'Mensual'),
              Tab(text: 'Proyección'),
              Tab(text: 'Banco de horas'),
            ],
          ),
        ),
        body: FutureBuilder<_DatosReportes>(
          future: _datosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final datos = snapshot.data ??
                const _DatosReportes(registros: [], movimientos: []);
            if (datos.vacio) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aún no hay marcaciones registradas para generar reportes.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return TabBarView(
              children: [
                DailyReportTab(registros: datos.registros),
                WeeklyReportTab(registros: datos.registros),
                MonthlyReportTab(registros: datos.registros),
                ProjectionReportTab(registros: datos.registros),
                BalanceReportTab(
                  registros: datos.registros,
                  movimientos: datos.movimientos,
                  metaDiariaMinutos: metaDiaria,
                  onCambio: _recargar,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
