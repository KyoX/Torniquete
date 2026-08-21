# Torniquete

Aplicación Flutter para el control de la jornada laboral: marca entrada, salida a
almorzar, regreso y salida, y sigue tu progreso frente a la meta de horas del día.

[![Descargar APK](https://img.shields.io/badge/Descargar-APK-brightgreen?logo=android)](https://github.com/KyoX/Torniquete/releases/download/latest/torniquete-latest.apk)

Cada push a `main` compila el APK automáticamente y lo publica en un
[Release de GitHub](https://github.com/KyoX/Torniquete/releases/tag/latest), así el enlace
de arriba siempre apunta a la última versión disponible. El APK se firma siempre con la
misma clave de release, así que instalar una versión nueva sobre una anterior no da error
de firma.

## Problemas al instalar el APK

Como la app no viene de Play Store, Android puede mostrar advertencias al instalarla:

- **"Play Protect nunca vio antes una app de este desarrollador"**: es normal para
  cualquier app fuera de Play Store con un certificado nuevo. Solo hay que tocar
  **"Instalar de todas formas"**.
- **"No se instaló la app" (sin más detalle, incluso después de tocar "Instalar de
  todas formas")**: esto pasa cuando Google Play Protect rechaza la instalación en
  segundo plano por la misma falta de reputación del certificado. Para instalarla:
  1. Abre **Play Store** → foto de perfil → **Play Protect** → ⚙️ (Ajustes).
  2. Desactiva **"Escanear apps con Play Protect"**.
  3. Instala el APK de nuevo.
  4. Puedes volver a activar el escaneo después; no es necesario dejarlo apagado.

## Funcionalidades

- **Marcación de horarios**: registra entrada mañana, salida almuerzo, entrada tarde
  y salida real, con opción de edición manual.
- **Meta de horas configurable**: metas distintas para lunes a jueves y para viernes,
  definidas en el onboarding inicial.
- **Progreso del día**: calcula minutos trabajados, progreso hacia la meta y hora
  estimada de salida.
- **Confirmar salida**: botón para registrar la hora real de salida cuando se
  trabaja más tiempo del estimado.
- **Recordatorio de salida**: notificación local 5 minutos antes de la hora estimada
  de salida.
- **Historial editable**: cada día del historial se puede editar (corregir cualquiera
  de las 4 marcas) o reiniciar por completo (borra todas sus marcas). También se
  puede agregar un registro para un día pasado que no tenga marcas (por ejemplo,
  tras reiniciarlo por error).
- **Reportes**: cumplimiento diario, semanal y mensual, proyección de cumplimiento
  de la meta del mes y balance histórico acumulado de horas.
- **Guardar ubicación** (opcional, desactivada por defecto): al activarla en Ajustes
  se pide el permiso de ubicación y, desde ese momento, cada marca guarda también
  las coordenadas donde se registró. Sirve como evidencia ante una auditoría de que
  sí se llegó al lugar de trabajo. Las coordenadas se guardan solo en el teléfono,
  se consultan tocando el pin azul junto a cada marca (en el día actual o en
  "Editar día") y pueden borrarse en cualquier momento desde Ajustes. El detalle
  de cada marca incluye **"Abrir en Maps"**, que muestra el punto exacto en la app
  de mapas del teléfono con el nombre de la marca como etiqueta; si no hay ninguna
  app de mapas instalada abre el mapa web y, como último recurso, copia el enlace.
  Cuando la hora se corrige a mano, la ubicación queda marcada como manual y el
  detalle advierte que corresponde al momento de la edición, no a la hora escrita.

## Identidad visual

La app usa la paleta corporativa: **azul** como color principal, **blanco** y
**amarillo** como secundarios. Todo está centralizado en
[`lib/theme/app_theme.dart`](lib/theme/app_theme.dart) (`AppColors` para los
tonos y `AppTheme.claro` / `AppTheme.oscuro` para los temas), así que cambiar
un tono se hace en un solo sitio.

| Uso | Color |
| --- | --- |
| Principal (barras, botones, iconos) | `#0D3C7E` |
| Degradado del banner | `#0D3C7E` → `#1B5AAE` |
| Acento (hora de salida, progreso, FAB) | `#F5A623` |
| Fondo / tarjetas | `#F4F6FA` / blanco |

Los estados también siguen la marca: un día cumplido se marca en azul y uno
pendiente en amarillo, en vez de verde y naranja. La app fija el tema claro
(`ThemeMode.light` en [`lib/main.dart`](lib/main.dart)); cambiarlo a
`ThemeMode.system` habilita la variante oscura, que mantiene los mismos
colores sobre fondo azul noche.

## Stack

- Flutter / Dart
- `provider` para gestión de estado
- `sqflite` para persistencia local de registros
- `shared_preferences` para configuración del usuario
- `flutter_local_notifications` + `timezone` para recordatorios
- `geolocator` para la evidencia opcional de ubicación
- `url_launcher` para abrir las coordenadas en una app de mapas

## Estructura

```text
lib/
  models/       # Registro (marcas y metas del día) y UbicacionMarca
  providers/    # AppProvider (config) y RegistroProvider (estado del día)
  services/     # DB, preferencias, notificaciones, ubicación y reportes
  screens/      # Onboarding, dashboard, historial, editar día, ajustes y reportes
  widgets/      # Componentes reutilizables del dashboard
```

## Getting Started

```bash
flutter pub get
flutter run
```

Requiere el SDK de Dart `^3.13.0` (ver `pubspec.yaml`).
