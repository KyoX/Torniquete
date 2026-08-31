import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../services/db_service.dart';

/// Cómo se pide una página del historial. Es un parámetro y no una llamada
/// directa a la base para que las pruebas puedan ejercitar la paginación sin
/// una base de datos detrás.
typedef CargarHistorial = Future<List<Registro>> Function({
  int limit,
  String? antesDe,
  Set<TipoDia> tipos,
});

/// Qué trozo del historial se está viendo y cómo se pide el siguiente.
///
/// El historial se traía entero de golpe con un tope de 60 días, así que a
/// los tres meses de uso los días más viejos dejaban de existir para la app:
/// no había manera de llegar a ellos para corregir uno. Ahora la lista crece
/// por páginas conforme se baja, se puede filtrar por tipo de día y se puede
/// saltar directo a un mes en vez de recorrer todos los de en medio.
///
/// Vive lo que vive la pantalla de Historial —se crea y se descarta con
/// ella—, a diferencia de los otros dos providers, que son de toda la app.
class HistorialProvider extends ChangeNotifier {
  HistorialProvider({
    CargarHistorial? cargar,
    this.tamanoPagina = 30,
  }) : _cargar = cargar ?? DbService.instance.getHistorial;

  final CargarHistorial _cargar;

  /// Cuántos días trae cada página.
  final int tamanoPagina;

  static final DateFormat _clave = DateFormat('yyyy-MM-dd');

  final List<Registro> _dias = [];

  /// Los días cargados hasta ahora, del más reciente al más antiguo.
  List<Registro> get dias => List.unmodifiable(_dias);

  bool _cargando = false;
  bool get cargando => _cargando;

  bool _hayMas = true;

  /// Si queda historial por debajo de lo ya cargado.
  bool get hayMas => _hayMas;

  Set<TipoDia> _tipos = const {};

  /// Tipos de día que se muestran. Vacío son todos.
  Set<TipoDia> get tipos => _tipos;

  DateTime? _mes;

  /// El mes al que se saltó, si se saltó a alguno. Null es "desde hoy".
  DateTime? get mes => _mes;

  /// Si hay algo puesto que esté escondiendo días.
  bool get filtrado => _tipos.isNotEmpty || _mes != null;

  /// Cada consulta que arranca de cero sube la generación, para descartar la
  /// respuesta de la anterior si llega tarde: sin esto, tocar dos filtros
  /// seguidos puede dejar en pantalla el resultado del primero.
  int _generacion = 0;

  bool _dispuesto = false;

  @override
  void dispose() {
    _dispuesto = true;
    super.dispose();
  }

  /// Una carga puede terminar con la pantalla ya cerrada.
  void _avisar() {
    if (!_dispuesto) notifyListeners();
  }

  /// Vuelve a pedir lo que hay en pantalla.
  ///
  /// Se piden tantos días como ya había cargados, no una página: después de
  /// editar un día de hace tres meses, devolver la lista al principio
  /// obligaría a bajar otra vez hasta él.
  Future<void> recargar() =>
      _cargarDesdeArriba(_dias.length > tamanoPagina ? _dias.length : tamanoPagina);

  Future<void> filtrarPor(Set<TipoDia> tipos) {
    _tipos = Set.unmodifiable(tipos);
    return _cargarDesdeArriba(tamanoPagina);
  }

  /// Empieza la lista en el último día de [mes] y sigue hacia atrás.
  Future<void> irAlMes(DateTime mes) {
    _mes = DateTime(mes.year, mes.month);
    return _cargarDesdeArriba(tamanoPagina);
  }

  /// Deshace el salto de mes: la lista vuelve a empezar por el día más
  /// reciente que haya.
  Future<void> quitarMes() {
    _mes = null;
    return _cargarDesdeArriba(tamanoPagina);
  }

  /// Deja la lista donde [dia] se pueda ver: quita los tipos y se planta en
  /// su mes. Es para después de guardar un día que el filtro dejaba fuera.
  Future<void> mostrarMesDe(DateTime dia) {
    _tipos = const {};
    _mes = DateTime(dia.year, dia.month);
    return _cargarDesdeArriba(tamanoPagina);
  }

  Future<void> limpiarFiltros() {
    _tipos = const {};
    _mes = null;
    return _cargarDesdeArriba(tamanoPagina);
  }

  /// Añade la página siguiente al final de la lista.
  Future<void> cargarMas() async {
    if (_cargando || !_hayMas || _dias.isEmpty) return;
    final generacion = _generacion;
    _cargando = true;
    _avisar();

    final pagina = await _pedir(limit: tamanoPagina, antesDe: _dias.last.fecha);
    if (generacion != _generacion) return;

    _dias.addAll(pagina);
    _hayMas = pagina.length == tamanoPagina;
    _cargando = false;
    _avisar();
  }

  Future<void> _cargarDesdeArriba(int cuantos) async {
    final generacion = ++_generacion;
    _dias.clear();
    _hayMas = true;
    _cargando = true;
    _avisar();

    final pagina = await _pedir(limit: cuantos, antesDe: _corteDelMes);
    if (generacion != _generacion) return;

    _dias.addAll(pagina);
    // Una página incompleta significa que ya no queda nada debajo.
    _hayMas = pagina.length == cuantos;
    _cargando = false;
    _avisar();
  }

  Future<List<Registro>> _pedir({
    required int limit,
    required String? antesDe,
  }) async {
    try {
      return await _cargar(limit: limit, antesDe: antesDe, tipos: _tipos);
    } catch (e) {
      // Una lista que se queda girando para siempre es peor que una lista
      // corta: se corta aquí y el usuario puede seguir usando la pantalla.
      debugPrint('No se pudo leer el historial: $e');
      return const [];
    }
  }

  /// Corte superior de la primera página cuando se saltó a un mes: el primer
  /// día del mes siguiente, que al ser exclusivo deja arriba el último día
  /// del mes elegido.
  String? get _corteDelMes {
    final mes = _mes;
    if (mes == null) return null;
    return _clave.format(DateTime(mes.year, mes.month + 1));
  }
}
