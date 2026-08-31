import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/pausa.dart';
import '../models/registro.dart';
import '../utils/time_utils.dart';
import 'pausas_service.dart';
import 'reports_service.dart';

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

  /// La entrada, las pausas y la salida del día en una línea.
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

  /// El `MarcaTipo.name` que ofrecería el botón de marcar rápido del widget
  /// y de la ficha de Ajustes rápidos, o vacío si hoy no hay ninguna marca
  /// pendiente.
  final String accionTipo;

  /// La etiqueta de ese botón ("Marcar entrada", "Pausa", "Continuar").
  final String accionEtiqueta;

  const WidgetResumen({
    required this.estado,
    required this.marcas,
    required this.salida,
    required this.minutosBase,
    required this.abiertoDesdeMinutos,
    required this.metaMinutos,
    required this.actualizado,
    this.accionTipo = '',
    this.accionEtiqueta = '',
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
        'accion_tipo': accionTipo,
        'accion_etiqueta': accionEtiqueta,
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
        marcas: '--:-- · --:-- · --:--',
        salida: 'Abre la app para empezar',
        minutosBase: 0,
        abiertoDesdeMinutos: -1,
        metaMinutos: 0,
        actualizado: actualizado,
      );
    }

    final minutosAhora = TimeUtils.toMinutes(TimeOfDay.fromDateTime(ahora));
    final entrada = TimeUtils.parseTimeOfDay(registro.entrada1);
    final salida = TimeUtils.parseTimeOfDay(registro.salidaReal);
    final pausaAbierta = registro.pausaAbierta;

    // El tramo abierto arranca donde terminó la última pausa, o en la propia
    // entrada si todavía no se ha parado. No hay ninguno si el día no ha
    // empezado, si ya se cerró o si se está de pausa ahora mismo.
    int? abiertoDesde;
    if (entrada != null && salida == null && pausaAbierta == null) {
      abiertoDesde = registro.pausas.fold<int>(
        TimeUtils.toMinutes(entrada),
        (ultimo, pausa) {
          final fin = pausa.finMinutos;
          return fin != null && fin > ultimo ? fin : ultimo;
        },
      );
    }

    // Lo ya consolidado llega hasta donde arranca el tramo abierto; si no hay
    // ninguno, hasta el cierre del día o hasta ahora mismo si se está de
    // pausa. Así el widget solo tiene que sumar los minutos corridos desde
    // [abiertoDesde] sin conocer ninguna regla de la jornada.
    //
    // Con tramo abierto el total va sin recortar en cero, a diferencia del
    // resto de la app: el widget le suma después los minutos corridos, y
    // recortarlo aquí le regalaría al día el almuerzo que la empresa
    // descuenta y todavía no se ha tomado.
    final base = abiertoDesde != null
        ? abiertoDesde -
            TimeUtils.toMinutes(entrada!) -
            PausasService.minutosPausados(registro.pausas, hasta: abiertoDesde) -
            ReportsService.descuentoPendiente(registro, minutosAhora: minutosAhora)
        : ReportsService.minutosEnVivo(registro, minutosAhora);

    final accion = _accion(registro, pausaAbierta: pausaAbierta);

    return WidgetResumen(
      estado: _estado(registro),
      marcas: [
        TimeUtils.formatHHmm(registro.entrada1),
        PausasService.resumen(registro.pausas, hasta: minutosAhora),
        TimeUtils.formatHHmm(registro.salidaReal),
      ].join(' · '),
      salida: _salida(registro, sr: salida, horaEstimadaSalida: horaEstimadaSalida),
      minutosBase: base,
      abiertoDesdeMinutos: abiertoDesde ?? -1,
      metaMinutos: registro.metaEfectivaMinutos,
      accionTipo: accion.tipo,
      accionEtiqueta: accion.etiqueta,
      actualizado: actualizado,
    );
  }

  /// Qué botón de marcar rápido ofrecer, si alguno. Un día justificado o ya
  /// cerrado no ofrece nada: no hay ninguna marca que le haga falta.
  ///
  /// Es una regla aparte de [RegistroProvider.marcaSugeridaAlLlegar] y
  /// [RegistroProvider.marcaSugeridaAlSalir]: esas dos son para el aviso de
  /// la sede y dependen de estar cerca de ella, mientras que el widget y la
  /// ficha ofrecen lo próximo que falte sin que importe dónde está el
  /// teléfono.
  static ({String tipo, String etiqueta}) _accion(
    Registro registro, {
    required Pausa? pausaAbierta,
  }) {
    if (registro.tipoDia.esJustificado || registro.salidaReal != null) {
      return (tipo: '', etiqueta: '');
    }
    if (registro.entrada1 == null) return (tipo: 'entrada1', etiqueta: 'Marcar entrada');
    if (pausaAbierta != null) return (tipo: 'reanudar', etiqueta: 'Continuar');
    return (tipo: 'pausa', etiqueta: 'Pausa');
  }

  static String _estado(Registro registro) {
    if (registro.tipoDia.esJustificado) return registro.tipoDia.etiqueta;
    if (registro.salidaReal != null) return 'Jornada cerrada';
    final abierta = registro.pausaAbierta;
    if (abierta != null) {
      return abierta == registro.almuerzo ? 'En almuerzo' : 'En pausa';
    }
    if (registro.entrada1 != null) return 'Trabajando';
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
    return 'Marca tu entrada para empezar';
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
