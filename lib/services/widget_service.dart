import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/registro.dart';
import '../utils/time_utils.dart';

/// Cuánto se ve el fondo de pantalla a través del widget de inicio.
///
/// Ninguna opción llega a ser invisible del todo: un widget no puede saber
/// qué hay debajo, y sobre un fondo claro el texto blanco se perdería. La
/// más transparente conserva un velo mínimo, y los textos del layout llevan
/// sombra para sostener el resto.
enum FondoWidget {
  solido('solido', 'Sólido', 'El azul de la app, sin transparencia.'),
  translucido(
    'translucido',
    'Translúcido',
    'Deja ver el fondo de pantalla por detrás sin comprometer la lectura.',
  ),
  transparente(
    'transparente',
    'Transparente',
    'Casi todo fondo de pantalla. Sobre imágenes muy claras o con mucho '
        'detalle el texto se lee peor.',
  );

  const FondoWidget(this.clave, this.etiqueta, this.descripcion);

  /// Lo que viaja hasta Kotlin. Se manda la clave y no el índice para que
  /// reordenar el enum no le cambie el widget a nadie.
  final String clave;
  final String etiqueta;
  final String descripcion;

  static FondoWidget desdeClave(String? clave) => values.firstWhere(
        (fondo) => fondo.clave == clave,
        orElse: () => FondoWidget.solido,
      );
}

/// Lo que se le entrega al widget de la pantalla de inicio.
///
/// El tiempo trabajado no viaja ya calculado, sino partido en dos: los
/// minutos de los tramos ya cerrados y el minuto del día en que empezó el
/// tramo que sigue abierto. Así el widget puede sumar los minutos corridos
/// por su cuenta cada vez que Android lo redibuja, sin que el código nativo
/// tenga que repetir las reglas de qué tramo cuenta y cuál no.
@immutable
class WidgetResumen {
  /// Frase corta de estado: "Trabajando", "En almuerzo", "Festivo"...
  final String estado;

  /// Las cuatro marcas del día en una línea.
  final String marcas;

  /// Hora estimada (o real) de salida, ya formateada.
  final String salida;

  /// Minutos de los tramos cerrados.
  final int minutosBase;

  /// Minuto del día en que arrancó el tramo abierto, o -1 si no hay ninguno.
  final int abiertoDesdeMinutos;

  final int metaMinutos;

  /// Hora en que la app calculó esto, para que el widget no aparente estar
  /// más al día de lo que está.
  final String actualizado;

  const WidgetResumen({
    required this.estado,
    required this.marcas,
    required this.salida,
    required this.minutosBase,
    required this.abiertoDesdeMinutos,
    required this.metaMinutos,
    required this.actualizado,
  });

  bool get hayTramoAbierto => abiertoDesdeMinutos >= 0;

  Map<String, Object> aMapa() => {
        'estado': estado,
        'marcas': marcas,
        'salida': salida,
        'minutos_base': minutosBase,
        'abierto_desde': abiertoDesdeMinutos,
        'meta_minutos': metaMinutos,
        'actualizado': actualizado,
      };
}

/// Mantiene al día el widget de la pantalla de inicio de Android.
class WidgetService {
  WidgetService._internal();
  static final WidgetService instance = WidgetService._internal();

  /// Nombre completo de la clase Kotlin que dibuja el widget.
  static const String _proveedor =
      'com.torniquete.app.torniquete.TorniqueteWidgetProvider';

  /// Traduce el día en curso a lo que muestra el widget. Es una función pura
  /// para poder verificarla sin Android de por medio.
  static WidgetResumen resumir({
    required Registro? registro,
    required TimeOfDay? horaEstimadaSalida,
    required DateTime ahora,
  }) {
    final actualizado = TimeUtils.formatTimeOfDay(TimeOfDay.fromDateTime(ahora));

    if (registro == null) {
      return WidgetResumen(
        estado: 'Sin datos de hoy',
        marcas: '--:-- · --:-- · --:-- · --:--',
        salida: 'Abre la app para empezar',
        minutosBase: 0,
        abiertoDesdeMinutos: -1,
        metaMinutos: 0,
        actualizado: actualizado,
      );
    }

    final e1 = TimeUtils.parseTimeOfDay(registro.entrada1);
    final s1 = TimeUtils.parseTimeOfDay(registro.salida1);
    final e2 = TimeUtils.parseTimeOfDay(registro.entrada2);
    final sr = TimeUtils.parseTimeOfDay(registro.salidaReal);

    var base = 0;
    var abiertoDesde = -1;

    // Mismo criterio que ReportsService.minutosEnVivo: la mañana solo corre
    // en vivo mientras no exista ni la salida a almuerzo ni el regreso.
    if (e1 != null) {
      if (s1 != null) {
        final manana = TimeUtils.toMinutes(s1) - TimeUtils.toMinutes(e1);
        if (manana > 0) base += manana;
      } else if (e2 == null) {
        abiertoDesde = TimeUtils.toMinutes(e1);
      }
    }
    if (e2 != null) {
      if (sr != null) {
        final tarde = TimeUtils.toMinutes(sr) - TimeUtils.toMinutes(e2);
        if (tarde > 0) base += tarde;
      } else {
        abiertoDesde = TimeUtils.toMinutes(e2);
      }
    }

    return WidgetResumen(
      estado: _estado(registro, e1: e1, s1: s1, e2: e2, sr: sr),
      marcas: [registro.entrada1, registro.salida1, registro.entrada2,
              registro.salidaReal]
          .map(TimeUtils.formatHHmm)
          .join(' · '),
      salida: _salida(registro, sr: sr, horaEstimadaSalida: horaEstimadaSalida),
      minutosBase: base,
      abiertoDesdeMinutos: abiertoDesde,
      metaMinutos: registro.metaEfectivaMinutos,
      actualizado: actualizado,
    );
  }

  static String _estado(
    Registro registro, {
    TimeOfDay? e1,
    TimeOfDay? s1,
    TimeOfDay? e2,
    TimeOfDay? sr,
  }) {
    if (registro.tipoDia.esJustificado) return registro.tipoDia.etiqueta;
    if (sr != null) return 'Jornada cerrada';
    if (e2 != null) return 'Trabajando (tarde)';
    if (s1 != null) return 'En almuerzo';
    if (e1 != null) return 'Trabajando';
    return 'Sin marcar';
  }

  static String _salida(
    Registro registro, {
    TimeOfDay? sr,
    TimeOfDay? horaEstimadaSalida,
  }) {
    if (registro.tipoDia.esJustificado) return 'Día sin meta de horas';
    if (sr != null) return 'Saliste a las ${TimeUtils.formatTimeOfDay(sr)}';
    if (horaEstimadaSalida != null) {
      return 'Salida estimada ${TimeUtils.formatTimeOfDay(horaEstimadaSalida)}';
    }
    return 'Marca el regreso del almuerzo';
  }

  /// Escribe el resumen y le pide a Android que redibuje el widget.
  /// Nunca lanza: que el widget falle no puede tumbar la app.
  Future<void> actualizar(WidgetResumen resumen) async {
    try {
      for (final entrada in resumen.aMapa().entries) {
        final valor = entrada.value;
        if (valor is int) {
          await HomeWidget.saveWidgetData<int>(entrada.key, valor);
        } else {
          await HomeWidget.saveWidgetData<String>(entrada.key, '$valor');
        }
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: _proveedor);
    } catch (e) {
      debugPrint('No se pudo actualizar el widget de inicio: $e');
    }
  }

  /// Guarda el fondo elegido y repinta el widget para que se vea al momento.
  ///
  /// El valor se queda en las preferencias del widget, así que sobrevive a
  /// los redibujados que hace Android por su cuenta sin que la app tenga que
  /// reenviarlo cada vez.
  Future<void> actualizarFondo(FondoWidget fondo) async {
    try {
      await HomeWidget.saveWidgetData<String>('fondo_widget', fondo.clave);
      await HomeWidget.updateWidget(qualifiedAndroidName: _proveedor);
    } catch (e) {
      debugPrint('No se pudo cambiar el fondo del widget: $e');
    }
  }
}
