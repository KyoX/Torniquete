import 'package:local_auth/local_auth.dart';

/// Pide la huella o el PIN/patrón que el usuario ya tiene configurado en el
/// teléfono. No guarda ninguna credencial propia: si el teléfono no tiene
/// ningún bloqueo configurado, autenticar no es posible.
class LockService {
  LockService._internal();
  static final LockService instance = LockService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Si el teléfono tiene algo con qué autenticar (huella, PIN, patrón o
  /// contraseña). Sin esto, activar el bloqueo en Ajustes dejaría a alguien
  /// sin forma de entrar a su propia app.
  Future<bool> puedeAutenticar() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// True si el usuario pasó la verificación. False tanto si la rechazó
  /// como si algo en el sistema falló al pedirla.
  Future<bool> autenticar() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Confirma tu identidad para abrir Torniquete',
        options: const AuthenticationOptions(
          // false: además de huella/rostro, acepta el PIN, el patrón o la
          // contraseña del teléfono. Exigir solo biometría dejaría fuera a
          // quien no la tenga configurada.
          biometricOnly: false,
          // Sigue esperando aunque la app pierda el foco un instante (por
          // ejemplo, al bajar la barra de notificaciones) en vez de cancelar
          // la verificación a medias.
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
