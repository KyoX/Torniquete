import 'package:flutter/material.dart';

import '../../models/registro.dart';
import '../../services/db_service.dart';
import 'balance_report_tab.dart';
import 'daily_report_tab.dart';
import 'monthly_report_tab.dart';
import 'projection_report_tab.dart';
import 'weekly_report_tab.dart';

/// Pantalla de reportes: cumplimiento diario, semanal, mensual, proyección
/// del mes y banco de horas acumulado. Carga los registros una sola vez y
/// los comparte entre las pestañas.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<List<Registro>> _registrosFuture;

  @override
  void initState() {
    super.initState();
    _registrosFuture = DbService.instance.getTodosLosRegistros();
  }

  @override
  Widget build(BuildContext context) {
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
        body: FutureBuilder<List<Registro>>(
          future: _registrosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final registros = snapshot.data ?? [];
            if (registros.isEmpty) {
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
                DailyReportTab(registros: registros),
                WeeklyReportTab(registros: registros),
                MonthlyReportTab(registros: registros),
                ProjectionReportTab(registros: registros),
                BalanceReportTab(registros: registros),
              ],
            );
          },
        ),
      ),
    );
  }
}
