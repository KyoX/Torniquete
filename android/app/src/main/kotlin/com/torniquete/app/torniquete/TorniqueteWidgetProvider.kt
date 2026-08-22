package com.torniquete.app.torniquete

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * Widget de la pantalla de inicio: progreso del dia y hora estimada de salida.
 *
 * La app no guarda el tiempo trabajado ya sumado, sino los minutos de los
 * tramos cerrados (`minutos_base`) y el minuto del dia en que arranco el tramo
 * que sigue abierto (`abierto_desde`, o -1 si no hay ninguno). Asi este
 * proveedor puede sumar los minutos corridos cada vez que Android lo redibuja
 * sin repetir aqui las reglas de que tramo cuenta, que viven en Dart.
 *
 * Android no redibuja los widgets mas de una vez cada media hora, asi que la
 * cifra puede quedarse corta hasta 30 minutos: por eso se muestra siempre la
 * hora del ultimo calculo, para no aparentar estar mas al dia de lo que esta.
 */
class TorniqueteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val base = widgetData.getInt("minutos_base", 0)
        val abiertoDesde = widgetData.getInt("abierto_desde", -1)
        val meta = widgetData.getInt("meta_minutos", 0)

        val trabajado = base + minutosCorridos(abiertoDesde)
        val progreso = if (meta > 0) {
            ((trabajado * 100) / meta).coerceIn(0, 100)
        } else {
            0
        }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_torniquete).apply {
                setTextViewText(
                    R.id.widget_estado,
                    widgetData.getString("estado", null) ?: "Sin datos",
                )
                setTextViewText(
                    R.id.widget_actualizado,
                    widgetData.getString("actualizado", null)?.let { "act. $it" } ?: "",
                )
                setTextViewText(
                    R.id.widget_trabajado,
                    if (meta > 0) {
                        "${formatearDuracion(trabajado)} / ${formatearDuracion(meta)}"
                    } else {
                        formatearDuracion(trabajado)
                    },
                )
                setProgressBar(R.id.widget_progreso, 100, progreso, false)
                setTextViewText(R.id.widget_salida, widgetData.getString("salida", null) ?: "")
                setTextViewText(R.id.widget_marcas, widgetData.getString("marcas", null) ?: "")

                // Tocar cualquier parte del widget abre la app.
                setOnClickPendingIntent(
                    R.id.widget_raiz,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Minutos transcurridos desde [abiertoDesde] (minuto del dia) hasta ahora.
     * Devuelve 0 si no hay tramo abierto o si la marca es del futuro, para que
     * un reloj desajustado no reste tiempo trabajado.
     */
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
