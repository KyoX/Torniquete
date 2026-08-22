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
  estimada de salida. El contador corre en vivo desde la entrada de la mañana y
  la pantalla se refresca sola cada 30 segundos mientras la app está abierta;
  si queda abierta pasada la medianoche, detecta el cambio de día y recarga.
- **Confirmar salida**: botón para registrar la hora real de salida cuando se
  trabaja más tiempo del estimado.
- **Recordatorio de salida**: notificación local 5 minutos antes de la hora estimada
  de salida.
- **Recordatorios de marca** (opcionales, apagados por defecto): avisos a la hora que
  elijas para no olvidar marcar la entrada, la salida a almuerzo y el regreso. Suenan
  solo de lunes a viernes y el aviso del día se omite si esa marca ya está hecha.
  En vez de una alarma diaria repetida se dejan programadas las próximas diez citas,
  que se recalculan cada vez que se abre la app o se registra una marca.
- **Tipos de día**: cada día puede marcarse como *festivo*, *vacaciones*,
  *incapacidad* o *permiso*, desde el chip bajo la fecha en el dashboard o al editar
  un día del historial. Un día así no exige meta de horas: no genera déficit en el
  banco y, si se trabaja en él, todo lo trabajado cuenta como tiempo extra. Los
  reportes lo separan de los días laborales en blanco y la proyección del mes deja
  de contar su meta.
- **Banco de horas accionable**: además del balance acumulado, la pestaña
  *Banco de horas* dice qué hacer con él. Si hay déficit, reparte las horas
  pendientes entre el plazo que elijas (5, 10, 15 o 20 días laborales) y da la
  fecha límite; si hay saldo a favor, lo traduce a días de compensatorio. Los
  **canjes** (horas gastadas en un compensatorio) y los **ajustes** (saldo traído
  de antes de instalar la app, horas reconocidas por la empresa) se anotan a mano
  y el saldo distingue lo que viene de los días trabajados de lo que se anotó.
- **Exportar y respaldar**: desde Ajustes se exporta el historial a **CSV** para
  abrirlo en Excel, se crea un **respaldo completo en JSON** (días, ubicaciones,
  movimientos del banco y configuración) y se restaura desde uno. Restaurar
  reemplaza todo el contenido de la app dentro de una transacción, así que si algo
  falla a mitad la base de datos queda como estaba.
- **Widget de inicio y ficha de Ajustes rápidos**: el widget muestra el progreso del
  día, la hora estimada de salida y las cuatro marcas sin abrir la app; la ficha de
  Ajustes rápidos muestra lo mismo al desplegar la barra de notificaciones. El tiempo
  trabajado no viaja calculado: la app entrega los minutos ya cerrados y el minuto en
  que empezó el tramo abierto, y el código nativo suma los minutos corridos, así que
  la cifra no se congela entre una actualización y otra. Aun así Android no redibuja
  los widgets más de una vez cada media hora, por lo que el widget indica cuándo se
  refrescaron los datos por última vez.
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
- **Geocerca de la sede** (opcional): guarda dónde queda el trabajo —un toque en
  *Usar mi ubicación actual*— y un radio de tolerancia, y la app avisa cuando una
  marca se registra lejos de ahí. Es solo un aviso: la marca se guarda igual, porque
  la app no puede distinguir una visita a cliente de un GPS desviado. El alfiler de
  la marca cambia de color y el detalle indica la distancia exacta. El radio mínimo
  es de 50 m a propósito: dentro de un edificio el GPS se desvía decenas de metros y
  un radio corto produciría falsas alertas.

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
- `flutter_local_notifications` + `timezone` + `flutter_timezone` para
  recordatorios en la zona horaria real del teléfono
- `geolocator` para la evidencia opcional de ubicación y la geocerca de la sede
- `url_launcher` para abrir las coordenadas en una app de mapas
- `home_widget` para alimentar el widget de inicio y la ficha de Ajustes rápidos
- `share_plus` + `path_provider` para compartir el CSV y el respaldo
- `file_picker` para elegir el archivo al restaurar

## Estructura

```text
lib/
  models/       # Registro, TipoDia, MovimientoBanco y UbicacionMarca
  providers/    # AppProvider (config) y RegistroProvider (estado del día)
  services/     # DB, preferencias, notificaciones, ubicación, reportes,
                # respaldo/exportación y datos del widget
  screens/      # Onboarding, dashboard, historial, editar día, ajustes y reportes
  widgets/      # Componentes reutilizables del dashboard
  utils/        # Cálculos puros de tiempo y de distancia geográfica
android/app/src/main/kotlin/  # Widget de inicio y ficha de Ajustes rápidos
```

La lógica que se puede probar sin Android vive en funciones puras
(`ReportsService`, `TimeUtils`, `GeoUtils`, `BackupService.construirCsv`,
`WidgetService.resumir`), que es lo que cubren las pruebas de `test/`.

## Getting Started

```bash
flutter pub get
flutter run
```

Requiere el SDK de Dart `^3.13.0` (ver `pubspec.yaml`).
