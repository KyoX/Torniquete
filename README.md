# Torniquete

Aplicación Flutter para el control de la jornada laboral: marca entrada, salida a
almorzar, regreso y salida, y sigue tu progreso frente a la meta de horas del día.

[![Descargar APK](https://img.shields.io/badge/Descargar-APK-brightgreen?logo=android)](https://github.com/KyoX/Torniquete/releases/latest/download/torniquete-latest.apk)

Cada push a `main` compila el APK automáticamente y lo publica en un
[Release de GitHub](https://github.com/KyoX/Torniquete/releases/tag/latest), así el enlace
de arriba siempre apunta a la última versión disponible.

## Funcionalidades

- **Marcación de horarios**: registra entrada mañana, salida almuerzo, entrada tarde
  y salida real, con opción de edición manual.
- **Meta de horas configurable**: metas distintas para lunes a jueves y para viernes,
  definidas en el onboarding inicial.
- **Progreso del día**: calcula minutos trabajados, progreso hacia la meta y hora
  estimada de salida.
- **Recordatorio de salida**: notificación local 5 minutos antes de la hora estimada
  de salida.
- **Historial y reportes**: vistas de historial diario, mensual, balance y proyección
  de horas.

## Stack

- Flutter / Dart
- `provider` para gestión de estado
- `sqflite` para persistencia local de registros
- `shared_preferences` para configuración del usuario
- `flutter_local_notifications` + `timezone` para recordatorios

## Estructura

```text
lib/
  models/       # Registro (marcas y metas del día)
  providers/    # AppProvider (config) y RegistroProvider (estado del día)
  services/     # DB, preferencias, notificaciones y reportes
  screens/      # Onboarding, dashboard, historial, ajustes y reportes
  widgets/      # Componentes reutilizables del dashboard
```

## Getting Started

```bash
flutter pub get
flutter run
```

Requiere el SDK de Dart `^3.13.0` (ver `pubspec.yaml`).
