package com.torniquete.app.torniquete

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.Calendar

/**
 * Ficha de Ajustes rapidos: al desplegar la barra de notificaciones muestra
 * cuanto se lleva trabajado hoy y la hora estimada de salida, y al tocarla
 * marca de una vez la unica accion que hoy hace falta —entrada, pausa o
 * continuar—, o simplemente abre la app si no hay ninguna pendiente.
 *
 * Lee los mismos datos que el widget de inicio (los que escribe WidgetService
 * desde Dart), asi que las dos superficies nunca se contradicen.
 */
class TorniqueteTileService : TileService() {

    companion object {
        /** Ver [TorniqueteWidgetProvider.CODIGO_BOTON_ACCION]: misma razon. */
        private const val CODIGO_MARCAR = 11
    }

    /** Lo que tocar la ficha dejaria marcado, o null si hoy no hace falta. */
    private var accionTipo: String? = null

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val datos = HomeWidgetPlugin.getData(this)

        val base = datos.getInt("minutos_base", 0)
        val abiertoDesde = datos.getInt("abierto_desde", -1)
        val trabajado = base + minutosCorridos(abiertoDesde)
        val estado = datos.getString("estado", null)
        val accionEtiqueta = datos.getString("accion_etiqueta", null)
        accionTipo = datos.getString("accion_tipo", null)?.takeIf { it.isNotEmpty() }

        // El subtitulo solo existe desde Android 10; antes hay que meterlo
        // todo en la etiqueta o no se veria.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.label = formatearDuracion(trabajado)
            tile.subtitle = accionEtiqueta
                ?: datos.getString("salida", null)
                ?: estado
                ?: "Torniquete"
        } else {
            val sufijo = accionEtiqueta ?: estado ?: "Torniquete"
            tile.label = "${formatearDuracion(trabajado)} · $sufijo"
        }

        tile.contentDescription = listOfNotNull(
            estado,
            datos.getString("salida", null),
            accionEtiqueta?.let { "Toca para $it" },
        ).joinToString(". ")

        // Activa mientras haya una jornada corriendo, para que se note de un
        // vistazo si falta cerrar el dia.
        tile.state = if (abiertoDesde >= 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.icon = Icon.createWithResource(this, R.mipmap.ic_launcher)
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val tipo = accionTipo
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = if (tipo != null) {
                MainActivity.pendingIntentParaMarcar(this, tipo, CODIGO_MARCAR)
            } else {
                HomeWidgetLaunchIntent.getActivity(this, MainActivity::class.java)
            }
            startActivityAndCollapse(pendingIntent)
        } else {
            // En Android 13 y anteriores solo existe la variante con Intent,
            // ya marcada como obsoleta en las versiones nuevas.
            val intent = if (tipo != null) {
                MainActivity.intentParaMarcar(this, tipo)
            } else {
                android.content.Intent(this, MainActivity::class.java)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    /** Ver [TorniqueteWidgetProvider.minutosCorridos]: misma regla. */
    private fun minutosCorridos(abiertoDesde: Int): Int {
        if (abiertoDesde < 0) return 0
        val ahora = Calendar.getInstance()
        val minutoActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        return (minutoActual - abiertoDesde).coerceAtLeast(0)
    }

    private fun formatearDuracion(minutos: Int): String {
        val seguro = minutos.coerceAtLeast(0)
        return "${seguro / 60}h ${(seguro % 60).toString().padStart(2, '0')}m"
    }
}
