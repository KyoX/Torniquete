import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/registro_provider.dart';
import '../services/jornadas_abiertas_service.dart';
import '../utils/time_utils.dart';

/// Avisa de los días que quedaron con la entrada marcada y sin salida.
///
/// Sin salida real no hay jornada que medir, así que esas horas no están en
/// el banco: el aviso existe porque es el único error de marcación que le
/// resta horas al usuario sin que nada se lo diga.
class JornadasAbiertasBanner extends StatelessWidget {
  final List<JornadaAbierta> jornadas;
  final VoidCallback onRevisar;
  final VoidCallback onDescartar;

  const JornadasAbiertasBanner({
    super.key,
    required this.jornadas,
    required this.onRevisar,
    required this.onDescartar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final varios = jornadas.length > 1;
    final minutos =
        jornadas.fold<int>(0, (suma, j) => suma + j.minutosRecuperados);

    return Card(
      color: tema.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: tema.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    varios
                        ? '${jornadas.length} días quedaron sin salida'
                        : '${_dia(jornadas.first.fecha)} quedó sin salida',
                    style: tema.textTheme.titleSmall?.copyWith(
                      color: tema.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              minutos > 0
                  ? 'Sin la hora de salida, ${varios ? 'esos días cuentan' : 'ese día cuenta'} '
                      'solo hasta la última marca: te faltan '
                      '${TimeUtils.formatDurationMinutes(minutos)} en el banco.'
                  : 'Sin la hora de salida no hay jornada que medir, así que '
                      '${varios ? 'esos días no cuentan' : 'ese día no cuenta'} completo.',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onTertiaryContainer,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDescartar,
                  child: const Text('Ahora no'),
                ),
                TextButton(
                  onPressed: onRevisar,
                  child: Text(varios ? 'Revisarlos' : 'Revisarlo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre la lista de días abiertos para cerrarlos uno a uno.
Future<void> mostrarJornadasAbiertas(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HojaJornadasAbiertas(),
    );

class _HojaJornadasAbiertas extends StatelessWidget {
  const _HojaJornadasAbiertas();

  @override
  Widget build(BuildContext context) {
    // Se escucha al provider en vez de recibir la lista ya hecha: al cerrar un
    // día la hoja se queda con los que faltan sin tener que abrirla de nuevo.
    final provider = context.watch<RegistroProvider>();
    final jornadas = provider.jornadasAbiertas;
    final tema = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Días sin salida',
                style: tema.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                jornadas.isEmpty
                    ? 'No queda ningún día abierto.'
                    : 'La app propone una hora, pero la buena la sabes tú: '
                        'revísala antes de aceptarla.',
                style: tema.textTheme.bodySmall,
              ),
            ),
            if (jornadas.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: jornadas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _FilaJornada(
                    jornada: jornadas[i],
                    onCerrar: (hora) =>
                        provider.cerrarJornadaAbierta(jornadas[i].fecha, hora),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(jornadas.isEmpty ? 'Cerrar' : 'Dejar el resto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaJornada extends StatelessWidget {
  final JornadaAbierta jornada;
  final ValueChanged<TimeOfDay> onCerrar;

  const _FilaJornada({required this.jornada, required this.onCerrar});

  Future<void> _elegirOtraHora(BuildContext context) async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeUtils.fromMinutes(jornada.minutoSugerido),
      helpText: 'Hora de salida',
    );
    if (elegida != null) onCerrar(elegida);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final registro = jornada.registro;
    final recuperados = jornada.minutosRecuperados;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dia(jornada.fecha), style: tema.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Entrada ${TimeUtils.formatHHmm(registro.entrada1)} · sin salida',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              jornada.desdePausa
                  ? 'Dejaste una pausa abierta a las ${jornada.horaSugerida} y '
                      'no marcaste la vuelta, así que es hasta ahí donde se '
                      'sabe que trabajaste.'
                  : 'Ese día te tocaba salir a las ${jornada.horaSugerida}.',
              style: tema.textTheme.bodySmall,
            ),
            if (recuperados > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Cerrarlo ahí devuelve '
                '${TimeUtils.formatDurationMinutes(recuperados)} al banco.',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _elegirOtraHora(context),
                  child: const Text('Otra hora'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: () =>
                      onCerrar(TimeUtils.fromMinutes(jornada.minutoSugerido)),
                  child: Text('Salí a las ${jornada.horaSugerida}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Martes 25 de agosto", que es como se nombra un día al hablar de él.
String _dia(String fecha) {
  try {
    final texto = DateFormat("EEEE d 'de' MMMM", 'es')
        .format(DateFormat('yyyy-MM-dd').parse(fecha));
    return texto[0].toUpperCase() + texto.substring(1);
  } catch (_) {
    return fecha;
  }
}
