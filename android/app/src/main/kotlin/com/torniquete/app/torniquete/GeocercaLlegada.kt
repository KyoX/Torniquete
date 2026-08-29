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
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Vigilancia de llegada a la sede.
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

    /** Una sola zona vigilada: la sede que el usuario configuro. */
    const val ID_SEDE = "torniquete_sede"

    const val CANAL_ID = "torniquete_llegada"
    private const val CANAL_NOMBRE = "Llegada al trabajo"
    private const val CANAL_DESCRIPCION =
        "Pregunta si quieres marcar cuando llegas a la sede"

    const val NOTIFICACION_ID = 3001

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
        if (!GeocercaStore.sedeActiva(context) || !puedeVigilar(context)) {
            cancelar(context)
            alTerminar?.invoke(false)
            return
        }
        registrar(context, alTerminar)
    }

    // El permiso se comprueba en puedeVigilar(), que es lo unico por lo que
    // se llega hasta aqui; lint no sabe seguir esa indireccion.
    @SuppressLint("MissingPermission")
    private fun registrar(context: Context, alTerminar: ((Boolean) -> Unit)?) {
        val geocerca = Geofence.Builder()
            .setRequestId(ID_SEDE)
            .setCircularRegion(
                GeocercaStore.latitud(context),
                GeocercaStore.longitud(context),
                GeocercaStore.radioMetros(context).toFloat(),
            )
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            // La entrada se registra tambien porque hay fabricantes que no
            // entregan la permanencia si no se pidio; el receptor filtra igual.
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_DWELL,
            )
            .setLoiteringDelay(PERMANENCIA_MS)
            .build()

        val peticion = GeofencingRequest.Builder()
            // Si al configurar la sede el usuario ya esta dentro, se le avisa
            // sin tener que salir y volver a entrar.
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_DWELL)
            .addGeofence(geocerca)
            .build()

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
     */
    // areNotificationsEnabled() ya descarto el caso sin permiso, y notify()
    // esta ademas envuelto en su propio catch.
    @SuppressLint("MissingPermission")
    fun avisar(context: Context) {
        val tipo = GeocercaStore.marcaAOfrecer(context) ?: return
        if (GeocercaStore.yaAvisado(context, tipo)) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        crearCanal(context)

        val donde = GeocercaStore.nombreSede(context)?.takeIf { it.isNotBlank() } ?: "la sede"
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

        val notificacion = NotificationCompat.Builder(context, CANAL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(abrirApp(context, null))
            .addAction(0, accion, abrirApp(context, tipo))
            .addAction(0, "Ahora no", descartar(context))
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICACION_ID, notificacion)
            GeocercaStore.anotarAviso(context, tipo)
        } catch (e: SecurityException) {
            Log.w(TAG, "Sin permiso para notificar la llegada", e)
        }
    }

    /** Retira el aviso, por ejemplo cuando la marca ya quedo registrada. */
    fun cancelarAviso(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICACION_ID)
    }

    private fun crearCanal(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            CANAL_ID,
            CANAL_NOMBRE,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = CANAL_DESCRIPCION }
        context.getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(canal)
    }

    /**
     * Abre la app y, si [tipo] no es null, le deja anotada la marca aceptada.
     *
     * La marca no se escribe desde aqui porque la base de datos y las reglas
     * de la jornada viven en Dart: duplicarlas en Kotlin seria tener dos
     * versiones de la verdad. Como el toque en la accion es una interaccion
     * del usuario, abrir la actividad esta permitido aunque la app llevara
     * dias cerrada.
     */
    private fun abrirApp(context: Context, tipo: String?): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (tipo != null) {
            intent.action = MainActivity.ACCION_MARCAR_LLEGADA
            intent.putExtra(MainActivity.EXTRA_MARCA, tipo)
            intent.putExtra(MainActivity.EXTRA_MS, System.currentTimeMillis())
        }
        return PendingIntent.getActivity(
            context.applicationContext,
            if (tipo == null) 0 else 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun descartar(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, GeocercaReceiver::class.java)
            .setAction(GeocercaReceiver.ACCION_DESCARTAR)
        return PendingIntent.getBroadcast(
            context.applicationContext,
            2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
