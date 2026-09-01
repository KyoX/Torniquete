import 'package:workmanager/workmanager.dart';

import 'backup_service.dart';
import 'prefs_service.dart';

/// Nombre único de la tarea periódica: sirve a la vez de identificador para
/// registrarla y cancelarla, y de filtro para reconocerla en
/// [respaldoAutomaticoCallbackDispatcher] si algún día se agregan más tareas.
const String tareaRespaldoAutomatico = 'torniquete.respaldo_automatico';

/// Punto de entrada que Android reactiva en un isolate nuevo, sin árbol de
/// widgets ni el resto del estado de la app, cuando toca la tarea periódica.
/// Tiene que ser una función de nivel superior marcada con
/// `@pragma('vm:entry-point')`: Workmanager la busca por su nombre desde
/// fuera de Dart, y el tree-shaking la eliminaría sin esa marca porque nada
/// dentro de la app la llama directamente.
@pragma('vm:entry-point')
void respaldoAutomaticoCallbackDispatcher() {
  Workmanager().executeTask((tarea, _) async {
    if (tarea != tareaRespaldoAutomatico) return true;
    // El ajuste pudo apagarse después de programar la tarea y antes de que
    // corriera: WorkManager no siempre cancela a tiempo, así que se vuelve a
    // comprobar aquí antes de escribir nada.
    final activo = await PrefsService().getRespaldoAutomaticoActivo();
    if (!activo) return true;
    try {
      await BackupService.instance.crearRespaldoAutomatico();
    } catch (_) {
      // No hay a quién avisar desde un isolate en segundo plano; el
      // siguiente ciclo semanal lo vuelve a intentar.
    }
    return true;
  });
}

/// Registra y cancela la tarea semanal de respaldo automático.
class BackupScheduler {
  BackupScheduler._internal();
  static final BackupScheduler instance = BackupScheduler._internal();

  bool _inicializado = false;

  Future<void> _asegurarInicializado() async {
    if (_inicializado) return;
    await Workmanager().initialize(respaldoAutomaticoCallbackDispatcher);
    _inicializado = true;
  }

  Future<void> activar() async {
    await _asegurarInicializado();
    await Workmanager().registerPeriodicTask(
      tareaRespaldoAutomatico,
      tareaRespaldoAutomatico,
      frequency: const Duration(days: 7),
      // No aporta arrancar el respaldo con la batería casi agotada: puede
      // esperar al siguiente ciclo sin que se note.
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Se llama al arrancar la app si el ajuste sigue activo: por si Android
  /// perdió el registro de la tarea (una reinstalación, un dato de la app
  /// borrado a mano), sin depender solo de lo que quedó programado la
  /// primera vez que se activó.
  Future<void> reactivarSiCorresponde() async {
    if (await PrefsService().getRespaldoAutomaticoActivo()) await activar();
  }

  Future<void> desactivar() async {
    await _asegurarInicializado();
    await Workmanager().cancelByUniqueName(tareaRespaldoAutomatico);
  }
}
