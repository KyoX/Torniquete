package com.torniquete.app.torniquete

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/**
 * Recibe todo lo que le pasa a la geocerca de la sede sin que la app este
 * abierta: la llegada y la salida que disparan los avisos, el "ahora no" de
 * cada uno y el reinicio del telefono, que borra las geocercas registradas y
 * obliga a volver a pedirlas.
 */
class GeocercaReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeocercaReceiver"

        const val ACCION_GEOCERCA = "com.torniquete.app.torniquete.GEOCERCA"
        const val ACCION_DESCARTAR = "com.torniquete.app.torniquete.DESCARTAR_LLEGADA"
        const val ACCION_DESCARTAR_SALIDA = "com.torniquete.app.torniquete.DESCARTAR_SALIDA"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACCION_GEOCERCA -> alCruzarLaSede(context, intent)
            ACCION_DESCARTAR -> descartar(context, GeocercaLlegada.NOTIFICACION_ID)
            ACCION_DESCARTAR_SALIDA ->
                descartar(context, GeocercaLlegada.NOTIFICACION_SALIDA_ID)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> GeocercaLlegada.sincronizar(context)
        }
    }

    private fun alCruzarLaSede(context: Context, intent: Intent) {
        val evento = GeofencingEvent.fromIntent(intent) ?: return
        if (evento.hasError()) {
            Log.w(TAG, "Evento de geocerca con error: ${evento.errorCode}")
            return
        }
        if (evento.triggeringGeofences?.none { it.requestId == GeocercaLlegada.ID_SEDE } == true) {
            return
        }
        // De la llegada solo interesa la permanencia. La entrada llega tambien
        // porque se registro para no depender de que el fabricante entregue la
        // otra, pero avisar con ella convertiria cualquier paso cerca en el
        // aviso del dia. La salida no tiene ese problema: es un solo instante,
        // y ademas solo se pregunta cerca de la hora de salida.
        when (evento.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_DWELL -> GeocercaLlegada.avisar(context)
            Geofence.GEOFENCE_TRANSITION_EXIT -> GeocercaLlegada.avisarSalida(context)
        }
    }

    /**
     * "Ahora no": se quita el aviso y no se vuelve a preguntar por esa misma
     * marca en lo que queda del dia. Quien lo lanzo ya dejo anotado el aviso,
     * asi que basta con cerrarlo.
     */
    private fun descartar(context: Context, notificacion: Int) {
        NotificationManagerCompat.from(context).cancel(notificacion)
    }
}
