import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../services/db_service.dart';
import '../utils/time_utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Registro>> _historialFuture;

  @override
  void initState() {
    super.initState();
    _historialFuture = DbService.instance.getHistorial();
  }

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: FutureBuilder<List<Registro>>(
        future: _historialFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final registros = snapshot.data ?? [];
          if (registros.isEmpty) {
            return const Center(
              child: Text('Aún no hay registros guardados.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: registros.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = registros[index];
              final cumplida = r.minutosCumplidos >= r.metaMinutos;
              return Card(
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          Icon(
                            cumplida
                                ? Icons.check_circle
                                : Icons.remove_circle_outline,
                            color: cumplida ? Colors.green : Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          _Marca('Entrada', r.entrada1),
                          _Marca('Salida almuerzo', r.salida1),
                          _Marca('Regreso', r.entrada2),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${TimeUtils.formatDurationMinutes(r.minutosCumplidos)} '
                        'de ${TimeUtils.formatDurationMinutes(r.metaMinutos)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  final String label;
  final String? valor;

  const _Marca(this.label, this.valor);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: ${TimeUtils.formatHHmm(valor)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
