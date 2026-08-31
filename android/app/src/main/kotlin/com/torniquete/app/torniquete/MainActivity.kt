package com.torniquete.app.torniquete

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Ademas de alojar la app, hace de puente con la vigilancia de la sede:
 * expone el canal con el que Dart configura la geocerca y recoge la marca que
 * el usuario acepto desde el aviso de llegada, el de salida, el widget de
 * inicio o la ficha de Ajustes rapidos.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CANAL = "torniquete/geocerca"

        const val ACCION_MARCAR = "com.torniquete.app.torniquete.MARCAR"
        const val EXTRA_MARCA = "marca"
        const val EXTRA_MS = "marca_ms"

        /**
         * Intent que abre la app dejando anotada la marca [tipo] como
         * aceptada, sin hora: el widget y la ficha no la llevan a proposito,
         * porque a ambos Android solo los redibuja cada media hora y la hora
         * de ese ultimo dibujado no es la del toque real. Sin
         * [EXTRA_MS], [recogerMarcaAceptada] cae a la hora en que la app
         * termina de abrirse, que es la unica que se conoce de verdad.
         */
        fun intentParaMarcar(context: Context, tipo: String): Intent =
            Intent(context.applicationContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .setAction(ACCION_MARCAR)
                .putExtra(EXTRA_MARCA, tipo)

        /**
         * La misma marca, ya envuelta para un `RemoteViews.setOnClickPendingIntent`.
         * [requestCode] tiene que ser distinto por cada superficie que la
         * use (widget, ficha): comparten intent y accion, y un mismo codigo
         * haria que la ultima en pedir su PendingIntent le pisara los
         * extras a la otra.
         */
        fun pendingIntentParaMarcar(
            context: Context,
            tipo: String,
            requestCode: Int,
        ): PendingIntent = PendingIntent.getActivity(
            context.applicationContext,
            requestCode,
            intentParaMarcar(context, tipo),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
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
     * La hora que se guarda es la del hecho —la llegada a la sede o la salida
     * de ella— y viaja dentro del propio intent: entre que el aviso salta,
     * alguien lo toca y la app termina de arrancar puede pasar de todo, y la
     * marca tiene que decir cuando ocurrio, no cuando se abrio la app.
     */
    private fun recogerMarcaAceptada(intent: Intent?) {
        if (intent?.action != ACCION_MARCAR) return
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
                            marcaSalida = llamada.argument<String>("marcaSalida"),
                            salidaDesdeMinuto = llamada.argument<Int>("salidaDesde"),
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
