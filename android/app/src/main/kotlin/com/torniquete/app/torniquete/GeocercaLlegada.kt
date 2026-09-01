package com.torniquete.app.torniquete

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Vigilancia de la sede: la llegada y la salida.
 *
 * Se apoya en las geocercas del propio sistema (GeofencingClient) en lugar de
 * mantener vivo un stream de posiciones: Android ya vigila la zona por su
 * cuenta, con el gasto de bateria repartido entre todas las apps que lo pidan,
 * y el aviso llega aunque la app este cerrada. El precio es que hay que
 * registrar la zona otra vez despues de cada reinicio, de lo que se encarga
 * [GeocercaReceiver].
 */
object GeocercaLlegada {
    private const val TAG = "GeocercaLlegada"

    /** La sede principal que el usuario configuro. */
    const val ID_SEDE = "torniquete_sede"

    /** La segunda sede, opcional: otra oficina, un coworking, una sucursal. */
    const val ID_SEDE2 = "torniquete_sede2"

    const val CANAL_ID = "torniquete_llegada"
    private const val CANAL_NOMBRE = "Llegada al trabajo"
    private const val CANAL_DESCRIPCION =
        "Pregunta si quieres marcar cuando llegas a la sede"

    /**
     * La salida tiene su propio canal para que se pueda silenciar sin perder
     * la llegada: son dos preguntas distintas y hay quien solo quiere una.
     */
    const val CANAL_SALIDA_ID = "torniquete_salida_sede"
    private const val CANAL_SALIDA_NOMBRE = "Salida de la sede"
    private const val CANAL_SALIDA_DESCRIPCION =
        "Pregunta si quieres cerrar la jornada cuando te vas de la sede"

    const val NOTIFICACION_ID = 3001
    const val NOTIFICACION_SALIDA_ID = 3002

    /**
     * Cuanto hay que quedarse dentro del radio antes de que salte el aviso.
     *
     * Con el disparo inmediato bastaba pasar por enfrente en el bus para
     * gastar el aviso del dia; minuto y medio distingue "llegue" de "pase
     * cerca" sin hacerse notar, porque de todos modos se tarda mas que eso en
     * subir a la oficina.
     */
    private const val PERMANENCIA_MS = 90_000

    private fun cliente(context: Context): GeofencingClient =
        LocationServices.getGeofencingClient(context.applicationContext)

    /** El PendingIntent que Android dispara al cumplirse la permanencia. */
    private fun disparador(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, GeocercaReceiver::class.java)
            .setAction(GeocercaReceiver.ACCION_GEOCERCA)
        // Mutable es obligatorio: Android escribe en el intent el evento de la
        // geocerca antes de entregarlo.
        return PendingIntent.getBroadcast(
            context.applicationContext,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    /**
     * True si el sistema dejaria vigilar la zona ahora mismo. Desde Android 10
     * una geocerca solo dispara con el permiso de ubicacion "todo el tiempo",
     * que es justo el que no se puede conceder desde un dialogo normal.
     */
    fun puedeVigilar(context: Context): Boolean {
        val fina = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!fina) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Deja la vigilancia como corresponda al estado guardado: la registra si
     * la sede esta activa y hay permiso, y la quita si no.
     *
     * [alTerminar] recibe si al final quedo una zona vigilada de verdad. El
     * registro es asincrono, asi que quien necesite responderle al usuario
     * tiene que esperar a esta llamada y no al retorno del metodo. Es
     * idempotente a proposito: se llama al guardar la sede, al arrancar la app
     * y despues de cada reinicio del telefono, y siempre deja lo mismo.
     */
    fun sincronizar(context: Context, alTerminar: ((Boolean) -> Unit)? = null) {
        val hayAlgunaSede = GeocercaStore.sedeActiva(context) || GeocercaStore.sede2Activa(context)
        if (!hayAlgunaSede || !puedeVigilar(context)) {
            cancelar(context)
            alTerminar?.invoke(false)
            return
        }
        registrar(context, alTerminar)
    }

    private fun geocercaDe(id: String, latitud: Double, longitud: Double, radioMetros: Int): Geofence =
        Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(latitud, longitud, radioMetros.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            // La entrada se registra tambien porque hay fabricantes que no
            // entregan la permanencia si no se pidio; el receptor filtra igual.
            // La salida es la que cierra la jornada: es el unico momento en
            // que el sistema puede saber que el usuario se fue del trabajo.
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or
                    Geofence.GEOFENCE_TRANSITION_DWELL or
                    Geofence.GEOFENCE_TRANSITION_EXIT,
            )
            .setLoiteringDelay(PERMANENCIA_MS)
            .build()

    // El permiso se comprueba en puedeVigilar(), que es lo unico por lo que
    // se llega hasta aqui; lint no sabe seguir esa indireccion.
    @SuppressLint("MissingPermission")
    private fun registrar(context: Context, alTerminar: ((Boolean) -> Unit)?) {
        val builder = GeofencingRequest.Builder()
            // Si al configurar la sede el usuario ya esta dentro, se le avisa
            // sin tener que salir y volver a entrar. La salida se deja fuera
            // del disparo inicial a proposito: registrar la geocerca estando
            // lejos de la oficina —que es lo normal— dispararia una salida
            // en cada arranque de la app.
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_DWELL)

        if (GeocercaStore.sedeActiva(context)) {
            builder.addGeofence(
                geocercaDe(
                    ID_SEDE,
                    GeocercaStore.latitud(context),
                    GeocercaStore.longitud(context),
                    GeocercaStore.radioMetros(context),
                ),
            )
        }
        if (GeocercaStore.sede2Activa(context)) {
            builder.addGeofence(
                geocercaDe(
                    ID_SEDE2,
                    GeocercaStore.latitud2(context),
                    GeocercaStore.longitud2(context),
                    GeocercaStore.radioMetros2(context),
                ),
            )
        }
        val peticion = builder.build()

        try {
            cliente(context).addGeofences(peticion, disparador(context))
                .addOnSuccessListener { alTerminar?.invoke(true) }
                .addOnFailureListener { e ->
                    Log.w(TAG, "Android rechazo la geocerca de la sede", e)
                    alTerminar?.invoke(false)
                }
        } catch (e: SecurityException) {
            Log.w(TAG, "Sin permiso para vigilar la sede", e)
            alTerminar?.invoke(false)
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo registrar la geocerca de la sede", e)
            alTerminar?.invoke(false)
        }
    }

    fun cancelar(context: Context) {
        try {
            cliente(context).removeGeofences(disparador(context))
        } catch (e: Exception) {
            Log.w(TAG, "No se pudo quitar la geocerca de la sede", e)
        }
    }

    // --- Aviso --------------------------------------------------------------

    /**
     * Lanza la pregunta de si marcar, si es que hay algo que marcar y no se
     * pregunto ya hoy por lo mismo.
     *
     * [sedeId] es la geocerca que disparo el evento —la principal o la
     * segunda— y solo se usa para nombrar el sitio en el texto del aviso.
     */
    // areNotificationsEnabled() ya descarto el caso sin permiso, y notify()
    // esta ademas envuelto en su propio catch.
    @SuppressLint("MissingPermission")
    fun avisar(context: Context, sedeId: String) {
        val tipo = GeocercaStore.marcaAOfrecer(context) ?: return
        if (GeocercaStore.yaAvisado(context, tipo)) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        crearCanal(context)

        val donde =
            GeocercaStore.nombreDeSede(context, sedeId)?.takeIf { it.isNotBlank() } ?: "la sede"
        // La otra marca posible es reanudar: se dejo una pausa abierta y el
        // telefono ha vuelto a la sede. No se dice "almuerzo" porque la pausa
        // puede haber sido cualquier cosa; eso lo decide Dart por la hora.
        val esEntrada = tipo == GeocercaStore.MARCA_ENTRADA
        val titulo = if (esEntrada) "¿Llegaste al trabajo?" else "¿Vuelves al trabajo?"
        val cuerpo = if (esEntrada) {
            "Estás en $donde. ¿Marco tu entrada?"
        } else {
            "Estás en $donde. Dejaste una pausa abierta, ¿la cierro?"
        }
        val accion = if (esEntrada) "Marcar entrada" else "Continuar"
        // La llegada se da por ocurrida cuando salta el aviso, que es cuando
        // se cumplio la permanencia dentro del radio.
        val cuando = System.currentTimeMillis()

        val notificacion = NotificationCompat.Builder(context, CANAL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(abrirApp(context, null, cuando))
            .addAction(0, accion, abrirApp(context, tipo, cuando))
            .addAction(0, "Ahora no", descartar(context, GeocercaReceiver.ACCION_DESCARTAR))
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICACION_ID, notificacion)
            GeocercaStore.anotarAviso(context, tipo)
        } catch (e: SecurityException) {
            Log.w(TAG, "Sin permiso para notificar la llegada", e)
        }
    }

    /**
     * Pregunta si cerrar la jornada al salir del radio de la sede.
     *
     * Solo se pregunta a partir de la hora que Dart dejo escrita —cerca ya de
     * la salida estimada—, porque el mismo evento lo dispara cualquier
     * diligencia a media mañana y la pregunta es una sola al dia.
     */
    @SuppressLint("MissingPermission")
    fun avisarSalida(context: Context, sedeId: String) {
        val tipo = GeocercaStore.marcaSalidaAOfrecer(context) ?: return
        if (GeocercaStore.yaAvisado(context, tipo)) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        crearCanalSalida(context)

        val donde =
            GeocercaStore.nombreDeSede(context, sedeId)?.takeIf { it.isNotBlank() } ?: "la sede"
        // El momento del evento, no el del toque: la hora que vale es aquella
        // en la que el telefono salio del radio, y el aviso puede quedarse un
        // buen rato en la barra antes de que alguien lo mire.
        val cuando = System.currentTimeMillis()
        val hora = SimpleDateFormat("HH:mm", Locale.US).format(Date(cuando))
        val cuerpo = "Saliste de $donde a las $hora. ¿Marco esa hora como tu salida?"

        val notificacion = NotificationCompat.Builder(context, CANAL_SALIDA_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("¿Terminaste tu jornada?")
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(abrirApp(context, null, cuando))
            .addAction(0, "Marcar salida", abrirApp(context, tipo, cuando))
            .addAction(0, "Todavia no", descartar(context, GeocercaReceiver.ACCION_DESCARTAR_SALIDA))
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICACION_SALIDA_ID, notificacion)
            GeocercaStore.anotarAviso(context, tipo)
        } catch (e: SecurityException) {
            Log.w(TAG, "Sin permiso para notificar la salida", e)
        }
    }

    /** Retira los avisos, por ejemplo cuando la marca ya quedo registrada. */
    fun cancelarAviso(context: Context) {
        NotificationManagerCompat.from(context).apply {
            cancel(NOTIFICACION_ID)
            cancel(NOTIFICACION_SALIDA_ID)
        }
    }

    private fun crearCanal(context: Context) =
        crearCanal(context, CANAL_ID, CANAL_NOMBRE, CANAL_DESCRIPCION)

    private fun crearCanalSalida(context: Context) =
        crearCanal(context, CANAL_SALIDA_ID, CANAL_SALIDA_NOMBRE, CANAL_SALIDA_DESCRIPCION)

    private fun crearCanal(context: Context, id: String, nombre: String, descripcion: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            id,
            nombre,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = descripcion }
        context.getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(canal)
    }

    /**
     * Abre la app y, si [tipo] no es null, le deja anotada la marca aceptada
     * con [cuandoMs] como hora del hecho.
     *
     * La hora viaja dentro del intent y no se lee al abrir la app: entre que
     * el aviso salta y alguien lo toca pueden pasar minutos —o el trayecto
     * entero de vuelta a casa—, y lo que hay que registrar es cuando se llego
     * o se salio, no cuando se miro el telefono.
     *
     * La marca no se escribe desde aqui porque la base de datos y las reglas
     * de la jornada viven en Dart: duplicarlas en Kotlin seria tener dos
     * versiones de la verdad. Como el toque en la accion es una interaccion
     * del usuario, abrir la actividad esta permitido aunque la app llevara
     * dias cerrada.
     */
    private fun abrirApp(context: Context, tipo: String?, cuandoMs: Long): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (tipo != null) {
            intent.action = MainActivity.ACCION_MARCAR
            intent.putExtra(MainActivity.EXTRA_MARCA, tipo)
            intent.putExtra(MainActivity.EXTRA_MS, cuandoMs)
        }
        // Cada marca necesita su propio codigo de peticion: con uno
        // compartido, el PendingIntent de la salida sobrescribiria los extras
        // del de la llegada que siguiera vivo en la barra.
        val codigo = when (tipo) {
            null -> 0
            GeocercaStore.MARCA_SALIDA_REAL -> 3
            else -> 1
        }
        return PendingIntent.getActivity(
            context.applicationContext,
            codigo,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun descartar(context: Context, accion: String): PendingIntent {
        val intent = Intent(context.applicationContext, GeocercaReceiver::class.java)
            .setAction(accion)
        return PendingIntent.getBroadcast(
            context.applicationContext,
            if (accion == GeocercaReceiver.ACCION_DESCARTAR_SALIDA) 4 else 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
