import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'prefs_service.dart';

/// Lo que el sistema está vigilando ahora mismo. Lo usa el diagnóstico de
/// Ajustes para no limitarse a decir que el interruptor está encendido.
@immutable
class EstadoGeocerca {
  /// True si hay una zona registrada en Android esperando la llegada.
  final bool vigilando;

  /// True si la app tiene la ubicación concedida "todo el tiempo", sin la
  /// cual Android nunca dispara una geocerca con la app cerrada.
  final bool permisoDeFondo;

  const EstadoGeocerca({
    required this.vigilando,
    required this.permisoDeFondo,
  });

  static const apagada = EstadoGeocerca(vigilando: false, permisoDeFondo: false);
}

/// Una marca que el usuario aceptó desde un aviso de la sede, todavía sin
/// registrar en la jornada.
@immutable
class MarcaAceptada {
  /// El nombre del `MarcaTipo` correspondiente ('entrada1', 'reanudar' o
  /// 'salidaReal').
  final String tipo;

  /// Cuándo ocurrió lo que el aviso preguntaba —la llegada a la sede o la
  /// salida de ella—, que es la hora que debe quedar registrada y no la del
  /// momento en que la app terminó de arrancar.
  final DateTime cuando;

  const MarcaAceptada({required this.tipo, required this.cuando});
}

/// Puente con la vigilancia nativa de la sede: la llegada y la salida.
///
/// El trabajo de verdad lo hace Android: se le pide vigilar un círculo con
/// `GeofencingClient` y es él quien despierta a la app cuando el teléfono se
/// queda dentro. Aquí solo se le mantiene al día la configuración de la sede
/// y qué marca falta hoy, para que el aviso pueda preguntar lo correcto sin
/// arrancar Flutter.
///
/// Todo es tolerante al fallo: fuera de Android —y en las pruebas, donde no
/// hay canal al otro lado— cada método se comporta como si la vigilancia
/// estuviera apagada, en vez de tumbar la marcación por un aviso opcional.
class GeocercaService {
  GeocercaService._internal();
  static final GeocercaService instance = GeocercaService._internal();

  @visibleForTesting
  static const MethodChannel canal = MethodChannel('torniquete/geocerca');

  bool get _disponible => defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _invocar<T>(String metodo, [Map<String, dynamic>? argumentos]) async {
    if (!_disponible) return null;
    try {
      return await canal.invokeMethod<T>(metodo, argumentos);
    } catch (e) {
      debugPrint('La vigilancia de llegada rechazó "$metodo": $e');
      return null;
    }
  }

  /// Le pasa al sistema la sede a vigilar. Devuelve true si al terminar hay
  /// una zona registrada de verdad: apagar el interruptor, borrar la sede,
  /// dejar la semana sin días de oficina o que falte el permiso de fondo
  /// devuelven false.
  ///
  /// Los días de oficina viajan junto a la sede porque quien decide si hoy
  /// toca preguntar es el propio receptor, con la app cerrada y sin forma de
  /// consultar nada a Dart.
  Future<bool> configurarSede(SedeConfig sede) async {
    final registrada = await _invocar<bool>('configurarSede', {
      'activa': sede.vigilanciaLlegadaVigente,
      'latitud': sede.latitud,
      'longitud': sede.longitud,
      'radio': sede.radioMetros,
      'nombre': sede.nombre,
      'dias': (sede.diasOficina.toList()..sort()),
    });
    return registrada ?? false;
  }

  /// Deja escrito qué marca ofrecería cada aviso si la llegada —o la
  /// salida— ocurriera ahora.
  ///
  /// La regla de qué falta marcar se calcula en Dart y viaja ya resuelta: el
  /// lado nativo tiene que poder preguntar lo correcto sin un motor de Dart
  /// vivo, y duplicar allí las reglas de la jornada sería tener dos versiones
  /// de la misma verdad.
  ///
  /// [salidaDesdeMinuto] es el minuto del día a partir del cual la pregunta
  /// de salida tiene sentido. Sin él, salir del radio a media mañana gastaría
  /// la pregunta del día; el lado nativo no puede calcularlo porque depende
  /// de la meta, de las pausas y del descuento de almuerzo.
  Future<void> actualizarDia({
    required String fecha,
    required String? marcaSugerida,
    String? marcaSalida,
    int? salidaDesdeMinuto,
  }) =>
      _invocar<void>('actualizarDia', {
        'fecha': fecha,
        'marcaSugerida': marcaSugerida,
        'marcaSalida': marcaSalida,
        'salidaDesde': salidaDesdeMinuto,
      });

  Future<EstadoGeocerca> estado() async {
    final mapa = await _invocar<Map<Object?, Object?>>('estado');
    if (mapa == null) return EstadoGeocerca.apagada;
    return EstadoGeocerca(
      vigilando: mapa['vigilando'] == true,
      permisoDeFondo: mapa['permisoDeFondo'] == true,
    );
  }

  /// Recoge la marca que el usuario aceptó en el aviso, si hay alguna. La
  /// entrega una sola vez: el lado nativo la borra al leerla.
  Future<MarcaAceptada?> consumirMarcaPendiente() async {
    final mapa =
        await _invocar<Map<Object?, Object?>>('consumirMarcaPendiente');
    final tipo = mapa?['tipo'];
    if (tipo is! String || tipo.isEmpty) return null;
    final milisegundos = mapa?['milisegundos'];
    return MarcaAceptada(
      tipo: tipo,
      cuando: milisegundos is int
          ? DateTime.fromMillisecondsSinceEpoch(milisegundos)
          : DateTime.now(),
    );
  }

  /// Retira los avisos de la sede que puedan seguir en la barra, por ejemplo
  /// porque la marca acabó de registrarse desde la propia app.
  Future<void> cancelarAviso() => _invocar<void>('cancelarAviso');
}
