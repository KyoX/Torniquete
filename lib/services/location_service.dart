import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/geo_utils.dart';
import 'prefs_service.dart';

/// Resultado de pedirle al usuario el permiso de ubicación.
enum PermisoUbicacion {
  concedido,
  denegado,

  /// El usuario marcó "no volver a preguntar": hay que abrir los ajustes.
  denegadoParaSiempre,

  /// El GPS del teléfono está apagado.
  servicioApagado,
}

/// Resultado de pedir la ubicación "todo el tiempo", la única con la que
/// Android dispara una geocerca teniendo la app cerrada.
enum PermisoDeFondo {
  concedido,

  /// El usuario solo dio "mientras se usa la app". Desde Android 11 subirlo a
  /// "todo el tiempo" no se puede pedir con un diálogo: hay que mandarlo a los
  /// ajustes del sistema.
  soloEnUso,

  /// Ni siquiera hay permiso de ubicación normal.
  sinPermiso,

  servicioApagado,
}

/// La sede —principal o secundaria— contra la que resultó evaluada una
/// marca, junto a la distancia y el radio de esa sede en concreto.
@immutable
class EvaluacionSede {
  final EvaluacionGeocerca evaluacion;

  /// Nombre de la sede que produjo esta evaluación, o null si no tiene uno
  /// guardado.
  final String? nombre;

  const EvaluacionSede({required this.evaluacion, this.nombre});
}

/// Envuelve el acceso al GPS. Todo es opcional: si el permiso no está
/// concedido o el GPS falla, [capturar] devuelve null y la app sigue
/// funcionando igual que antes.
class LocationService {
  LocationService._internal();
  static final LocationService instance = LocationService._internal();

  /// true si la app ya puede leer la ubicación sin volver a preguntar.
  Future<bool> tienePermiso() async {
    final permiso = await Geolocator.checkPermission();
    return permiso == LocationPermission.always ||
        permiso == LocationPermission.whileInUse;
  }

  Future<bool> servicioActivo() => Geolocator.isLocationServiceEnabled();

  /// true si la app puede leer la ubicación aunque esté cerrada.
  Future<bool> tienePermisoDeFondo() async =>
      await Geolocator.checkPermission() == LocationPermission.always;

  /// Pide la ubicación "todo el tiempo". Primero asegura el permiso normal y
  /// solo después intenta subirlo, que es el orden que exige Android: pedir
  /// el de fondo sin tener el de primer plano se rechaza sin preguntar nada.
  Future<PermisoDeFondo> solicitarPermisoDeFondo() async {
    switch (await solicitarPermiso()) {
      case PermisoUbicacion.concedido:
        break;
      case PermisoUbicacion.servicioApagado:
        return PermisoDeFondo.servicioApagado;
      case PermisoUbicacion.denegado:
      case PermisoUbicacion.denegadoParaSiempre:
        return PermisoDeFondo.sinPermiso;
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.whileInUse) {
      // En Android 10 esta segunda petición sí muestra la opción "todo el
      // tiempo"; de Android 11 en adelante el sistema la deniega en el acto y
      // la respuesta es la misma que ya teníamos, que es justo lo que hace
      // que haya que ofrecer los ajustes.
      permiso = await Geolocator.requestPermission();
    }
    return permiso == LocationPermission.always
        ? PermisoDeFondo.concedido
        : PermisoDeFondo.soloEnUso;
  }

  /// Pide el permiso al sistema (muestra el diálogo de Android si aplica).
  Future<PermisoUbicacion> solicitarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PermisoUbicacion.servicioApagado;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    switch (permiso) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return PermisoUbicacion.concedido;
      case LocationPermission.deniedForever:
        return PermisoUbicacion.denegadoParaSiempre;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return PermisoUbicacion.denegado;
    }
  }

  Future<void> abrirAjustesDeLaApp() => Geolocator.openAppSettings();

  Future<void> abrirAjustesDeUbicacion() => Geolocator.openLocationSettings();

  /// Abre unas coordenadas en la app de mapas del teléfono. Primero intenta
  /// el esquema `geo:` (deja elegir Google Maps, Waze, etc.) y si no hay
  /// ninguna app de mapas cae al mapa web. Devuelve false si no se pudo
  /// abrir nada, para que la pantalla ofrezca copiar el enlace.
  Future<bool> abrirEnMapas({
    required double latitud,
    required double longitud,
    String? etiqueta,
  }) async {
    final marca = etiqueta == null || etiqueta.isEmpty
        ? '$latitud,$longitud'
        : '$latitud,$longitud(${Uri.encodeComponent(etiqueta)})';
    final geo = Uri.parse('geo:$latitud,$longitud?q=$marca');
    final web = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitud,$longitud');

    for (final destino in [geo, web]) {
      try {
        if (await canLaunchUrl(destino) &&
            await launchUrl(destino,
                mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('No se pudo abrir $destino: $e');
      }
    }
    return false;
  }

  /// Compara unas coordenadas contra la geocerca de la sede. Devuelve null
  /// si la vigilancia está apagada o si todavía no se guardó dónde queda.
  EvaluacionGeocerca? evaluarSede(
    SedeConfig sede, {
    required double latitud,
    required double longitud,
  }) {
    if (!sede.vigente) return null;
    return GeoUtils.evaluar(
      sedeLatitud: sede.latitud,
      sedeLongitud: sede.longitud,
      radioMetros: sede.radioMetros,
      latitud: latitud,
      longitud: longitud,
    );
  }

  /// Compara unas coordenadas contra las sedes vigentes —la principal y,
  /// si la hay, la segunda— y devuelve la que resulte "dentro" del radio, o
  /// si ninguna lo está, la más cercana. Null si ninguna de las dos tiene
  /// coordenadas guardadas.
  EvaluacionSede? evaluarSedes(
    SedeConfig sede, {
    SedeSecundaria? sede2,
    required double latitud,
    required double longitud,
  }) {
    final candidatas = <EvaluacionSede>[];

    final principal = evaluarSede(sede, latitud: latitud, longitud: longitud);
    if (principal != null) {
      candidatas.add(EvaluacionSede(evaluacion: principal, nombre: sede.nombre));
    }
    if (sede2 != null && sede2.vigente) {
      final evaluacion = GeoUtils.evaluar(
        sedeLatitud: sede2.latitud,
        sedeLongitud: sede2.longitud,
        radioMetros: sede2.radioMetros,
        latitud: latitud,
        longitud: longitud,
      );
      if (evaluacion != null) {
        candidatas.add(EvaluacionSede(evaluacion: evaluacion, nombre: sede2.nombre));
      }
    }
    if (candidatas.isEmpty) return null;

    final dentro = candidatas.where((c) => c.evaluacion.dentro);
    if (dentro.isNotEmpty) return dentro.first;

    candidatas.sort(
      (a, b) => a.evaluacion.distanciaMetros.compareTo(b.evaluacion.distanciaMetros),
    );
    return candidatas.first;
  }

  /// Obtiene la posición actual. Devuelve null si no hay permiso, el GPS
  /// está apagado o no se consiguió una lectura a tiempo.
  Future<Position?> capturar({
    Duration limite = const Duration(seconds: 15),
  }) async {
    try {
      if (!await tienePermiso()) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: limite,
        ),
      );
    } catch (e) {
      debugPrint('No se pudo obtener la ubicación exacta: $e');
      // Mejor una posición reciente del sistema que ninguna evidencia.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (e2) {
        debugPrint('Tampoco hay última ubicación conocida: $e2');
        return null;
      }
    }
  }
}
