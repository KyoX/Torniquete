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

- **Marcación de horarios**: registra la entrada, las pausas del día y la salida
  real, con opción de edición manual. Los botones son *Entrada*, **Pausa** y
  **Continuar**, y se pueden usar tantas veces como haga falta: un día con una
  diligencia a media mañana y luego el almuerzo son dos pausas, no una elección
  entre las dos. Cuál de ellas fue el almuerzo no se marca, se deduce de la hora
  (ver más abajo), así que al pausar no hay nada que decidir.
- **Meta de horas configurable**: metas distintas para lunes a jueves y para viernes,
  definidas en el onboarding inicial.
- **Progreso del día**: calcula minutos trabajados, progreso hacia la meta y hora
  estimada de salida. El contador corre en vivo desde la entrada de la mañana y
  la pantalla se refresca sola cada 30 segundos mientras la app está abierta;
  si queda abierta pasada la medianoche, detecta el cambio de día y recarga.
- **Almuerzo descontado** (opcional, en cero por defecto): hay empresas que
  descuentan un almuerzo fijo *salgas o no a comer*, y entonces saltarse el
  almuerzo no adelanta la salida. Con los minutos configurados en *Ajustes →
  Almuerzo descontado*, la app los resta del día aunque no se marque ninguna
  pausa para almorzar. Es un **mínimo**: si el almuerzo real dura más, se descuenta el que
  de verdad se tomó; si dura menos —o no se sale— se completa hasta el mínimo.
  El descuento pendiente se va acreditando minuto a minuto mientras se almuerza,
  para que el progreso no pegue un salto en cada marca. Cada día guarda el
  descuento con el que se trabajó, igual que guarda su meta de horas: cambiar el
  ajuste afecta al día en curso y a los siguientes, nunca a los ya cerrados.

  Contra ese descuento solo cuenta lo que se estuvo fuera **entre las 11:30 y las
  14:00**, que es la franja en que la app da una pausa por almuerzo. Sin esa
  condición, media hora de diligencias a las nueve y media daría por cumplido un
  descuento que la empresa va a hacer igual, y la app adelantaría la hora de
  salida media hora de más. Si una pausa cruza el borde de la franja solo cuenta
  el trozo de dentro. La franja está fijada en el código
  (`PausasService.inicioAlmuerzo` / `finAlmuerzo`), no es un ajuste.

  Para quien descubre el ajuste después de meses usando la app —su empresa
  llevaba descontando el almuerzo todo ese tiempo y el banco de horas guardado
  está de más— existe *Aplicar al historial*, que recalcula los días ya
  guardados con el descuento vigente. Es la única operación de la app que
  reescribe el pasado, así que va detrás de una confirmación que dice cuántos
  días cambian de horas y **cuánto se mueve el banco** antes de tocar nada. El
  día de hoy queda fuera: ya sigue el ajuste por su cuenta. Funciona en los dos
  sentidos, así que bajar el descuento devuelve las horas.

  La hora estimada de salida es la entrada más la meta del día, más todo lo que
  se ha estado de pausa, más el almuerzo que la empresa descuenta y todavía no
  se ha tomado: cada pausa empuja la salida hacia adelante justo lo que duró.
  Mientras una pausa sigue abierta la hora se va corriendo minuto a minuto —es
  una estimación de *si vuelves ya y no paras más*— y se corrige sola al
  continuar.
- **Jornada corrida**: quien no para en todo el día puede cerrarlo con solo la
  entrada y la salida real, sin ninguna pausa. El botón *Confirmar salida*
  aparece en cuanto hay entrada, y el día cuenta como un único tramo.
- **Pausa sin cerrar**: quien se va y no marca la vuelta deja de contar en el
  momento de la pausa, aunque después confirme la salida. Es la lectura
  conservadora, y la misma tanto si el día sigue corriendo como si se cerró
  después.
- **Confirmar salida**: botón para registrar la hora real de salida cuando se
  trabaja más tiempo del estimado.
- **Recordatorio de salida**: notificación local 5 minutos antes de la hora estimada
  de salida.
- **Recordatorios de marca** (opcionales, apagados por defecto): avisos a la hora que
  elijas para no olvidar marcar la entrada, la pausa del almuerzo y la vuelta. Suenan
  solo de lunes a viernes y el aviso del día se omite si esa marca ya está hecha.
  En vez de una alarma diaria repetida se dejan programadas las próximas diez citas,
  que se recalculan cada vez que se abre la app o se registra una marca.
- **Tipos de día**: cada día puede marcarse como *festivo*, *vacaciones*,
  *incapacidad* o *permiso*, desde el chip bajo la fecha en el dashboard o al editar
  un día del historial. Un día así no exige meta de horas: no genera déficit en el
  banco y, si se trabaja en él, todo lo trabajado cuenta como tiempo extra. Los
  reportes lo separan de los días laborales en blanco y la proyección del mes deja
  de contar su meta.
- **Asuetos de El Salvador**: la app conoce el calendario de asuetos de ley y no te
  exige horas en ellos. La Semana Santa se calcula a partir de la Pascua, así que el
  calendario no hay que actualizarlo cada año. En Ajustes se elige el régimen —*sector
  privado* (Código de Trabajo, Art. 190) o *sector público*, que suma el 3 y el 5 de
  agosto— y se puede apagar por completo. Cuando cae un asueto el dashboard lo sugiere
  en vez de marcarlo solo: hay quien trabaja los asuetos, y en ese caso las horas del
  día son tiempo extra, no una ausencia. *Revisar el historial* busca días ya guardados
  que cayeron en asueto y quedaron sin horas, sin tocar aquellos en los que sí se
  trabajó. Las fiestas patronales y los días que dé la empresa siguen siendo manuales.
- **Banco de horas accionable**: además del balance acumulado, la pestaña
  *Banco de horas* dice qué hacer con él. Si hay déficit, reparte las horas
  pendientes entre el plazo que elijas (5, 10, 15 o 20 días laborales) y da la
  fecha límite; si hay saldo a favor, lo traduce a días de compensatorio. Los
  **canjes** (horas gastadas en un compensatorio) y los **ajustes** (saldo traído
  de antes de instalar la app, horas reconocidas por la empresa) se anotan a mano
  y el saldo distingue lo que viene de los días trabajados de lo que se anotó.
- **Reporte para comprobar el horario (PDF y Excel)**: cuando hay que demostrarle
  a alguien —jefatura, recursos humanos, un cliente— que sí se cumplieron las horas,
  el botón *Exportar* de la pantalla de Reportes (o el de Ajustes) genera un
  documento del periodo que se elija: este mes, el mes pasado, los últimos 15 o 30
  días, todo el historial o un rango de fechas a mano. El **PDF** trae portada con
  el nombre y el periodo, los totales (trabajado, exigido, diferencia y porcentaje
  de cumplimiento), el detalle día por día con las marcas, el tiempo en pausa y el
  estado de cada día, y los resúmenes semanal, mensual y de movimientos del banco. El **.xlsx**
  lleva lo mismo repartido en cinco hojas (*Resumen*, *Detalle diario*, *Semanal*,
  *Mensual*, *Banco de horas*) con las horas en celdas **numéricas**, para que quien
  reciba el archivo pueda sumar y filtrar por su cuenta. Ambos salen de los mismos
  cálculos que las pantallas, así que nunca dicen cosas distintas.
- **Tema claro u oscuro**: desde *Ajustes → Apariencia* se elige si la app se ve
  clara, oscura o como esté el teléfono (esto último es lo que hace por defecto).
  La elección se recuerda y se lee antes de pintar la primera pantalla, para que
  quien use el tema oscuro no vea un destello blanco al abrir. El widget de inicio
  no sigue este ajuste: tiene el suyo propio, más abajo.
- **Exportar y respaldar**: desde Ajustes se exporta el historial a **CSV** —el
  volcado crudo, fila por día— para abrirlo en Excel, se crea un **respaldo completo
  en JSON** (días, ubicaciones, movimientos del banco y configuración) y se restaura
  desde uno. Restaurar reemplaza todo el contenido de la app dentro de una
  transacción, así que si algo falla a mitad la base de datos queda como estaba.
- **Widget de inicio y ficha de Ajustes rápidos**: el widget muestra el progreso del
  día, la hora estimada de salida, la entrada, las pausas y la salida sin abrir la
  app; la ficha de
  Ajustes rápidos muestra lo mismo al desplegar la barra de notificaciones. El tiempo
  trabajado no viaja calculado: la app entrega los minutos ya cerrados y el minuto en
  que empezó el tramo abierto, y el código nativo suma los minutos corridos, así que
  la cifra no se congela entre una actualización y otra. Aun así Android no redibuja
  los widgets más de una vez cada media hora, por lo que el widget indica cuándo se
  refrescaron los datos por última vez. Desde *Ajustes → Apariencia* se elige cuánto
  se transparenta: **sólido**, **translúcido** o **transparente**. Ninguna opción
  llega a ser invisible del todo y los textos llevan sombra siempre, porque un widget
  no puede saber qué fondo de pantalla tiene debajo: sin ese velo mínimo, el texto
  blanco desaparecería sobre una imagen clara.
- **Historial editable**: cada día del historial se puede editar —corregir la
  entrada, la salida real y las horas de cada pausa, y añadir o borrar pausas— o
  reiniciar por completo (borra todas sus marcas). También se
  puede agregar un registro para un día pasado que no tenga marcas (por ejemplo,
  tras reiniciarlo por error).
- **Reportes**: cumplimiento diario, semanal y mensual, proyección de cumplimiento
  de la meta del mes y balance histórico acumulado de horas, con exportación a PDF
  y Excel del periodo que se elija.
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
- **Aviso al llegar al trabajo** (opcional, apagado por defecto): con la sede ya
  guardada, *Ajustes → Sede → Avisarme al llegar para marcar* le pide a Android que
  vigile ese radio. Al quedarse dentro llega una notificación que pregunta si marcar
  —*la entrada* o *continuar la pausa que quedó abierta*, según lo que falte ese
  día— con un botón para hacerlo y otro para dejarlo pasar. Aceptar abre la app y
  registra la marca con **la hora del toque**, no con la de cuando la app terminó de
  abrirse.

  La vigilancia la hace el sistema (`GeofencingClient` de Google Play Services), no
  la app: el aviso llega aunque Torniquete esté cerrado, sin notificación persistente
  ni consumo extra de batería. A cambio Android exige el permiso de ubicación
  **"Permitir todo el tiempo"**, que desde Android 11 solo se concede desde los
  ajustes del sistema; la tarjeta de Sede dice en todo momento si el sistema está
  vigilando de verdad y ofrece el atajo para concederlo. Como las geocercas se
  pierden al reiniciar el teléfono y al actualizar la app, se vuelven a registrar en
  el arranque y cada vez que la app pasa a primer plano.

  Se pregunta **una sola vez al día por cada marca** y solo tras minuto y medio
  dentro del radio, para que pasar cerca camino a otro sitio no gaste el aviso. Los
  días festivos, de vacaciones, incapacidad o permiso no preguntan nada, y una
  jornada ya cerrada tampoco se reabre por volver a pasar por la sede. El regreso
  solo se ofrece si hay una pausa abierta: sin esa condición, volver al
  radio a media mañana se leería como un regreso y preguntaría a destiempo.
- **Días de oficina**: con trabajo híbrido, pasar por delante de la oficina un día
  de teletrabajo no es motivo para preguntar si se marca la entrada. Los días en los
  que sí se va —de lunes a viernes por defecto— se eligen en la misma tarjeta de
  Sede y solo condicionan este aviso: desde casa se trabaja y se marca igual, así
  que el resto de la app no cambia. El filtro se aplica **en el momento de la
  llegada** y no al registrar la geocerca, porque una geocerca se registra una vez y
  vive hasta el siguiente reinicio, mientras que lo que cambia cada madrugada es si
  hoy toca oficina. Dejar la semana sin ningún día marcado retira la geocerca en vez
  de dejar a Android despertando a la app para un aviso que nunca va a salir.

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
pendiente en amarillo, en vez de verde y naranja. Sobre el fondo azul noche del
tema oscuro esos dos tonos no se leen, así que los estados se piden con
`AppColors.cumplidoDe(context)` y sus hermanas, que devuelven la versión clara
del mismo color cuando el tema es oscuro: el significado no cambia, solo el
tono.

La variante oscura mantiene los mismos colores sobre fondo azul noche.

## Stack

- Flutter / Dart
- `provider` para gestión de estado
- `sqflite` para persistencia local de registros
- `shared_preferences` para configuración del usuario
- `flutter_local_notifications` + `timezone` + `flutter_timezone` para
  recordatorios en la zona horaria real del teléfono
- `geolocator` para la evidencia opcional de ubicación y los permisos de la sede
- `play-services-location` (Kotlin) para que el propio Android vigile la llegada
  al trabajo con la app cerrada
- `url_launcher` para abrir las coordenadas en una app de mapas
- `home_widget` para alimentar el widget de inicio y la ficha de Ajustes rápidos
- `pdf` para el reporte de cumplimiento en PDF y `excel` para el .xlsx
- `share_plus` + `path_provider` para compartir los reportes, el CSV y el respaldo
- `file_picker` para elegir el archivo al restaurar
- `flutter_localizations` + `intl` para que la app y los diálogos de Material
  (calendario, reloj, menús de texto) estén siempre en español, sin importar el
  idioma del teléfono

## Estructura

```text
lib/
  models/       # Registro, TipoDia, MovimientoBanco y UbicacionMarca
  providers/    # AppProvider (config) y RegistroProvider (estado del día)
  services/     # DB, preferencias, notificaciones, ubicación, reportes,
                # exportación (PDF/Excel), respaldo y datos del widget
  screens/      # Onboarding, dashboard, historial, editar día, ajustes y reportes
  widgets/      # Componentes reutilizables del dashboard
  utils/        # Cálculos puros de tiempo, distancia geográfica y asuetos
android/app/src/main/kotlin/  # Widget de inicio, ficha de Ajustes rápidos y
                              # vigilancia de llegada a la sede
```

La regla de qué marca ofrecer al llegar (`RegistroProvider.marcaSugeridaAlLlegar`)
vive solo en Dart: el lado nativo no la recalcula, lee el resultado que la app le
deja escrito cada vez que cambia el día. Así la vigilancia puede preguntar lo
correcto sin un motor de Dart vivo y sigue existiendo una sola definición de "qué
falta marcar".

La lógica que se puede probar sin Android vive en funciones puras
(`ReportsService`, `TimeUtils`, `GeoUtils`, `FestivosSV`,
`RegistroProvider.marcaSugeridaAlLlegar`, `ReportsService.descuentoPendiente`,
`DescuentoAlmuerzoService.revisar`, `SedeConfig.diasOficinaLegible`,
`PausasService` (minutos de pausa, franja del almuerzo) y `Pausa.parsear`,
`BackupService.construirCsv`, `ExportService.construirPdf` /
`construirXlsx`, `WidgetService.resumir`), que es lo que cubren las
pruebas de `test/`.

## Getting Started

```bash
flutter pub get
flutter run
```

Requiere el SDK de Dart `^3.13.0` (ver `pubspec.yaml`).
