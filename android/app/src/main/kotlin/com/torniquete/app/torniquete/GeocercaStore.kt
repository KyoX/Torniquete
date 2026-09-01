package com.torniquete.app.torniquete

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Lo poco que el lado nativo necesita saber para decidir si avisar al llegar
 * a la sede, guardado en sus propias preferencias.
 *
 * Es un archivo aparte del de Flutter a proposito: aqui escriben el receptor
 * de la geocerca y la actividad, que corren sin motor de Dart vivo, y acoplar
 * eso al formato interno de shared_preferences seria pedir que se rompa a la
 * primera actualizacion del plugin.
 *
 * La regla de que marca toca no vive aqui: la calcula Dart y la deja escrita
 * en [MARCA_SUGERIDA] cada vez que el dia cambia, para que exista una sola
 * definicion de "que falta marcar" en toda la app.
 */
object GeocercaStore {
    private const val ARCHIVO = "torniquete_geocerca"

    private const val ACTIVA = "activa"
    private const val LATITUD = "latitud"
    private const val LONGITUD = "longitud"
    private const val RADIO = "radio_m"
    private const val NOMBRE = "nombre"
    private const val DIAS = "dias_oficina"

    /**
     * Segunda sede, opcional: otra oficina, un coworking, una sucursal. No
     * tiene sus propios dias: usa [DIAS], que son "los dias que se trabaja
     * fuera de casa" y no una jornada aparte por sede.
     */
    private const val ACTIVA2 = "activa2"
    private const val LATITUD2 = "latitud2"
    private const val LONGITUD2 = "longitud2"
    private const val RADIO2 = "radio2_m"
    private const val NOMBRE2 = "nombre2"

    private const val FECHA = "fecha"
    private const val MARCA_SUGERIDA = "marca_sugerida"
    private const val MARCA_SALIDA = "marca_salida"
    private const val SALIDA_DESDE = "salida_desde"

    /** Marca de "no hay hora", para distinguirla de la medianoche. */
    private const val SIN_HORA = -1

    private const val AVISO_FECHA = "aviso_fecha"
    private const val AVISO_TIPO = "aviso_tipo"

    private const val PENDIENTE_TIPO = "pendiente_tipo"
    private const val PENDIENTE_MS = "pendiente_ms"

    /** Marcas que los avisos saben registrar. Coinciden con MarcaTipo en Dart. */
    const val MARCA_ENTRADA = "entrada1"
    const val MARCA_REANUDAR = "reanudar"
    const val MARCA_SALIDA_REAL = "salidaReal"

    /**
     * De lunes a viernes, en la misma mascara de bits que se guarda.
     *
     * Es el valor que rige mientras Dart no haya escrito el suyo, cosa que
     * pasa entre actualizar la app y abrirla por primera vez.
     */
    private const val DIAS_POR_DEFECTO = 0b0011111

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)

    // --- Sede vigilada ------------------------------------------------------

    fun guardarSede(
        context: Context,
        activa: Boolean,
        latitud: Double?,
        longitud: Double?,
        radioMetros: Int,
        nombre: String?,
        diasOficina: List<*>?,
    ) {
        prefs(context).edit().apply {
            putBoolean(ACTIVA, activa)
            if (latitud != null && longitud != null) {
                putFloat(LATITUD, latitud.toFloat())
                putFloat(LONGITUD, longitud.toFloat())
            }
            putInt(RADIO, radioMetros)
            putInt(DIAS, mascaraDeDias(diasOficina))
            if (nombre.isNullOrBlank()) remove(NOMBRE) else putString(NOMBRE, nombre.trim())
        }.apply()
    }

    /**
     * Empaqueta los dias que llegan de Dart (1 = lunes ... 7 = domingo) en una
     * mascara de bits. Una lista vacia es una eleccion legitima —"ningun
     * dia"— y se guarda como cero; solo la ausencia de lista cae al valor por
     * defecto.
     */
    private fun mascaraDeDias(dias: List<*>?): Int {
        if (dias == null) return DIAS_POR_DEFECTO
        var mascara = 0
        for (valor in dias) {
            val dia = (valor as? Number)?.toInt() ?: continue
            if (dia in 1..7) mascara = mascara or (1 shl (dia - 1))
        }
        return mascara
    }

    /**
     * True si hoy toca ir a la sede. Con trabajo hibrido, pasar por delante
     * de la oficina un dia de teletrabajo no es motivo para preguntar si se
     * marca la entrada.
     */
    fun esDiaDeOficina(context: Context): Boolean {
        val mascara = prefs(context).getInt(DIAS, DIAS_POR_DEFECTO)
        return (mascara and (1 shl (diaDeLaSemana() - 1))) != 0
    }

    /** El dia de hoy en la numeracion de Dart: 1 = lunes ... 7 = domingo. */
    private fun diaDeLaSemana(): Int {
        val dia = Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
        return if (dia == Calendar.SUNDAY) 7 else dia - 1
    }

    fun sedeActiva(context: Context): Boolean =
        prefs(context).getBoolean(ACTIVA, false) && tieneCoordenadas(context)

    fun tieneCoordenadas(context: Context): Boolean {
        val p = prefs(context)
        return p.contains(LATITUD) && p.contains(LONGITUD)
    }

    fun latitud(context: Context): Double = prefs(context).getFloat(LATITUD, 0f).toDouble()

    fun longitud(context: Context): Double = prefs(context).getFloat(LONGITUD, 0f).toDouble()

    fun radioMetros(context: Context): Int = prefs(context).getInt(RADIO, 200)

    fun nombreSede(context: Context): String? = prefs(context).getString(NOMBRE, null)

    // --- Segunda sede ---------------------------------------------------

    fun guardarSede2(
        context: Context,
        activa: Boolean,
        latitud: Double?,
        longitud: Double?,
        radioMetros: Int,
        nombre: String?,
    ) {
        prefs(context).edit().apply {
            putBoolean(ACTIVA2, activa)
            if (latitud != null && longitud != null) {
                putFloat(LATITUD2, latitud.toFloat())
                putFloat(LONGITUD2, longitud.toFloat())
            }
            putInt(RADIO2, radioMetros)
            if (nombre.isNullOrBlank()) remove(NOMBRE2) else putString(NOMBRE2, nombre.trim())
        }.apply()
    }

    fun sede2Activa(context: Context): Boolean =
        prefs(context).getBoolean(ACTIVA2, false) && tieneCoordenadas2(context)

    fun tieneCoordenadas2(context: Context): Boolean {
        val p = prefs(context)
        return p.contains(LATITUD2) && p.contains(LONGITUD2)
    }

    fun latitud2(context: Context): Double = prefs(context).getFloat(LATITUD2, 0f).toDouble()

    fun longitud2(context: Context): Double = prefs(context).getFloat(LONGITUD2, 0f).toDouble()

    fun radioMetros2(context: Context): Int = prefs(context).getInt(RADIO2, 200)

    fun nombreSede2(context: Context): String? = prefs(context).getString(NOMBRE2, null)

    /** El nombre de la sede que disparo el evento, sea la principal o la segunda. */
    fun nombreDeSede(context: Context, idSede: String): String? =
        if (idSede == GeocercaLlegada.ID_SEDE2) nombreSede2(context) else nombreSede(context)

    // --- Estado del dia -----------------------------------------------------

    fun guardarDia(
        context: Context,
        fecha: String,
        marcaSugerida: String?,
        marcaSalida: String?,
        salidaDesdeMinuto: Int?,
    ) {
        prefs(context).edit()
            .putString(FECHA, fecha)
            .putString(MARCA_SUGERIDA, marcaSugerida ?: "")
            .putString(MARCA_SALIDA, marcaSalida ?: "")
            .putInt(SALIDA_DESDE, salidaDesdeMinuto ?: SIN_HORA)
            .apply()
    }

    /**
     * Que marca ofrecer ahora mismo, o null si no hay ninguna pendiente.
     *
     * Si lo ultimo que dejo escrito Dart es de otro dia, es que la app no se
     * ha abierto hoy: entonces no hay ninguna marca hecha todavia y lo que
     * toca es la entrada.
     *
     * El filtro por dia va aqui y no al registrar la geocerca porque una
     * geocerca se registra una vez y vive hasta el siguiente reinicio: lo que
     * cambia cada madrugada es si hoy toca oficina, y eso solo se puede mirar
     * en el momento de la llegada.
     */
    fun marcaAOfrecer(context: Context): String? {
        if (!esDiaDeOficina(context)) return null
        val p = prefs(context)
        if (p.getString(FECHA, null) != hoy()) return MARCA_ENTRADA
        return p.getString(MARCA_SUGERIDA, "")?.takeIf { it.isNotEmpty() }
    }

    /**
     * Que marca ofrecer al salir del radio, o null si no hay ninguna.
     *
     * Al contrario que en la llegada, aqui no hay valor por defecto: si lo
     * ultimo escrito por Dart no es de hoy, la app no se ha abierto en todo
     * el dia y no hay forma de saber si la jornada llego a empezar.
     * Preguntar por una salida que quiza nunca tuvo entrada seria peor que
     * callarse.
     *
     * El umbral horario tambien lo pone Dart: depende de la meta del dia, de
     * las pausas y del descuento de almuerzo, que aqui no se conocen. Antes
     * de esa hora se ignora la salida, porque cualquier diligencia a media
     * mañana dispara el mismo evento que irse a casa.
     */
    fun marcaSalidaAOfrecer(context: Context): String? {
        if (!esDiaDeOficina(context)) return null
        val p = prefs(context)
        if (p.getString(FECHA, null) != hoy()) return null
        val tipo = p.getString(MARCA_SALIDA, "")?.takeIf { it.isNotEmpty() } ?: return null
        val desde = p.getInt(SALIDA_DESDE, SIN_HORA)
        if (desde == SIN_HORA || minutoDelDia() < desde) return null
        return tipo
    }

    private fun minutoDelDia(): Int {
        val ahora = Calendar.getInstance()
        return ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
    }

    // --- Antirrepeticion ----------------------------------------------------

    /**
     * True si hoy ya se aviso de esta marca. El aviso se da una sola vez por
     * dia y por tipo: quien entra y sale del edificio varias veces no tiene
     * por que recibir la misma pregunta cada vez.
     */
    fun yaAvisado(context: Context, tipo: String): Boolean {
        val p = prefs(context)
        return p.getString(AVISO_FECHA, null) == hoy() && p.getString(AVISO_TIPO, null) == tipo
    }

    fun anotarAviso(context: Context, tipo: String) {
        prefs(context).edit()
            .putString(AVISO_FECHA, hoy())
            .putString(AVISO_TIPO, tipo)
            .apply()
    }

    // --- Marca elegida en el aviso -----------------------------------------

    /**
     * Deja anotado que el usuario acepto marcar, con la hora del toque y no
     * la del momento en que Dart llegue a leerlo: entre una y otra puede
     * pasar lo que tarde la app en arrancar.
     */
    fun anotarPendiente(context: Context, tipo: String, cuandoMs: Long) {
        prefs(context).edit()
            .putString(PENDIENTE_TIPO, tipo)
            .putLong(PENDIENTE_MS, cuandoMs)
            .apply()
    }

    fun leerPendiente(context: Context): Pair<String, Long>? {
        val p = prefs(context)
        val tipo = p.getString(PENDIENTE_TIPO, null) ?: return null
        return tipo to p.getLong(PENDIENTE_MS, 0L)
    }

    fun borrarPendiente(context: Context) {
        prefs(context).edit().remove(PENDIENTE_TIPO).remove(PENDIENTE_MS).apply()
    }

    fun hoy(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
}
