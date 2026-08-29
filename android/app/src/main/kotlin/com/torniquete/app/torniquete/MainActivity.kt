package com.torniquete.app.torniquete

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Ademas de alojar la app, hace de puente con la vigilancia de llegada a la
 * sede: expone el canal con el que Dart configura la geocerca y recoge la
 * marca que el usuario acepto desde el aviso.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CANAL = "torniquete/geocerca"

        const val ACCION_MARCAR_LLEGADA = "com.torniquete.app.torniquete.MARCAR_LLEGADA"
        const val EXTRA_MARCA = "marca"
        const val EXTRA_MS = "marca_ms"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recogerMarcaAceptada(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        recogerMarcaAceptada(intent)
    }

    /**
     * Anota la marca que el usuario acepto en el aviso para que Dart la
     * registre en cuanto tenga la jornada de hoy cargada.
     *
     * La hora que se guarda es la del toque, que viaja en el propio intent:
     * entre tocar y que la app termine de arrancar pueden pasar varios
     * segundos, y la marca tiene que decir cuando se llego, no cuando se
     * termino de abrir la app.
     */
    private fun recogerMarcaAceptada(intent: Intent?) {
        if (intent?.action != ACCION_MARCAR_LLEGADA) return
        val tipo = intent.getStringExtra(EXTRA_MARCA) ?: return
        val cuando = intent.getLongExtra(EXTRA_MS, System.currentTimeMillis())
        GeocercaStore.anotarPendiente(this, tipo, cuando)
        GeocercaLlegada.cancelarAviso(this)
        // Se limpia para que volver a la app desde recientes no reviva la
        // misma marca una segunda vez.
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { llamada, respuesta ->
                when (llamada.method) {
                    "configurarSede" -> {
                        GeocercaStore.guardarSede(
                            context = this,
                            activa = llamada.argument<Boolean>("activa") ?: false,
                            latitud = llamada.argument<Double>("latitud"),
                            longitud = llamada.argument<Double>("longitud"),
                            radioMetros = llamada.argument<Int>("radio") ?: 200,
                            nombre = llamada.argument<String>("nombre"),
                            diasOficina = llamada.argument<List<*>>("dias"),
                        )
                        GeocercaLlegada.sincronizar(this) { respuesta.success(it) }
                    }

                    "actualizarDia" -> {
                        GeocercaStore.guardarDia(
                            context = this,
                            fecha = llamada.argument<String>("fecha") ?: GeocercaStore.hoy(),
                            marcaSugerida = llamada.argument<String>("marcaSugerida"),
                        )
                        respuesta.success(null)
                    }

                    "estado" -> respuesta.success(
                        mapOf(
                            "vigilando" to (
                                GeocercaStore.sedeActiva(this) &&
                                    GeocercaLlegada.puedeVigilar(this)
                                ),
                            "permisoDeFondo" to GeocercaLlegada.puedeVigilar(this),
                        ),
                    )

                    "consumirMarcaPendiente" -> {
                        val pendiente = GeocercaStore.leerPendiente(this)
                        GeocercaStore.borrarPendiente(this)
                        respuesta.success(
                            pendiente?.let { mapOf("tipo" to it.first, "milisegundos" to it.second) },
                        )
                    }

                    "cancelarAviso" -> {
                        GeocercaLlegada.cancelarAviso(this)
                        respuesta.success(null)
                    }

                    else -> respuesta.notImplemented()
                }
            }
    }
}
