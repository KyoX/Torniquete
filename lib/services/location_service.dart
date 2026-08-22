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
