import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────
// MODELOS
// ─────────────────────────────────────────────

class Producto {
  final int? id;
  final String codigo;
  final String barra;
  final String desc;
  final String marca;
  final String mayor;
  final String minor;
  final String prov;
  final int stock;
  final int stockMinimo;

  const Producto({
    this.id,
    required this.codigo,
    required this.barra,
    required this.desc,
    required this.marca,
    required this.mayor,
    required this.minor,
    required this.prov,
    this.stock = 0,
    this.stockMinimo = 0,
  });

  bool get stockBajo => stockMinimo > 0 && stock <= stockMinimo && stock > 0;
  bool get sinStock => stock <= 0;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'codigo': codigo,
        'barra': barra,
        'desc': desc,
        'marca': marca,
        'mayor': mayor,
        'minor': minor,
        'prov': prov,
        'stock': stock,
        'stock_minimo': stockMinimo,
      };

  factory Producto.fromMap(Map<String, dynamic> m) => Producto(
        id: m['id'] as int?,
        codigo: m['codigo'] as String? ?? '',
        barra: m['barra'] as String? ?? '',
        desc: m['desc'] as String? ?? '',
        marca: m['marca'] as String? ?? '',
        mayor: m['mayor'] as String? ?? '0,00',
        minor: m['minor'] as String? ?? '0,00',
        prov: m['prov'] as String? ?? '',
        stock: m['stock'] as int? ?? 0,
        stockMinimo: m['stock_minimo'] as int? ?? 0,
      );

  Producto copyWith({
    int? id,
    String? codigo,
    String? barra,
    String? desc,
    String? marca,
    String? mayor,
    String? minor,
    String? prov,
    int? stock,
    int? stockMinimo,
  }) =>
      Producto(
        id: id ?? this.id,
        codigo: codigo ?? this.codigo,
        barra: barra ?? this.barra,
        desc: desc ?? this.desc,
        marca: marca ?? this.marca,
        mayor: mayor ?? this.mayor,
        minor: minor ?? this.minor,
        prov: prov ?? this.prov,
        stock: stock ?? this.stock,
        stockMinimo: stockMinimo ?? this.stockMinimo,
      );
}

class MovimientoStock {
  final int? id;
  final int productoId;
  final String productoDesc;
  final String tipo;
  final int cantidad;
  final String motivo;
  final DateTime fecha;

  const MovimientoStock({
    this.id,
    required this.productoId,
    required this.productoDesc,
    required this.tipo,
    required this.cantidad,
    required this.motivo,
    required this.fecha,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'producto_id': productoId,
        'producto_desc': productoDesc,
        'tipo': tipo,
        'cantidad': cantidad,
        'motivo': motivo,
        'fecha': fecha.toIso8601String(),
      };

  factory MovimientoStock.fromMap(Map<String, dynamic> m) => MovimientoStock(
        id: m['id'] as int?,
        productoId: m['producto_id'] as int,
        productoDesc: m['producto_desc'] as String? ?? '',
        tipo: m['tipo'] as String? ?? '',
        cantidad: m['cantidad'] as int? ?? 0,
        motivo: m['motivo'] as String? ?? '',
        fecha: DateTime.parse(m['fecha'] as String),
      );
}

class ArticuloCarrito {
  final Producto producto;
  int cantidad;

  ArticuloCarrito({required this.producto, this.cantidad = 1});

  double get precioDouble =>
      double.tryParse(producto.minor.replaceAll(',', '.')) ?? 0.0;
  double get subtotal => precioDouble * cantidad;
}

// ─────────────────────────────────────────────
// BASE DE DATOS
// ─────────────────────────────────────────────

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'torreon.db');
    return openDatabase(
      fullPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE productos (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            codigo       TEXT,
            barra        TEXT,
            desc         TEXT,
            marca        TEXT,
            mayor        TEXT,
            minor        TEXT,
            prov         TEXT,
            stock        INTEGER DEFAULT 0,
            stock_minimo INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_desc  ON productos(desc COLLATE NOCASE)');
        await db.execute('CREATE INDEX idx_barra ON productos(barra)');
        await db.execute('''
          CREATE TABLE movimientos_stock (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            producto_id   INTEGER NOT NULL,
            producto_desc TEXT,
            tipo          TEXT NOT NULL,
            cantidad      INTEGER NOT NULL,
            motivo        TEXT,
            fecha         TEXT NOT NULL,
            FOREIGN KEY (producto_id) REFERENCES productos(id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE productos ADD COLUMN stock INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE productos ADD COLUMN stock_minimo INTEGER DEFAULT 0');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS movimientos_stock (
              id            INTEGER PRIMARY KEY AUTOINCREMENT,
              producto_id   INTEGER NOT NULL,
              producto_desc TEXT,
              tipo          TEXT NOT NULL,
              cantidad      INTEGER NOT NULL,
              motivo        TEXT,
              fecha         TEXT NOT NULL,
              FOREIGN KEY (producto_id) REFERENCES productos(id)
            )
          ''');
        }
      },
    );
  }

  static Future<List<Producto>> buscar(String query,
      {int limit = 60, int offset = 0}) async {
    final database = await db;
    final q = '%$query%';
    final rows = await database.query(
      'productos',
      where: 'desc LIKE ? OR barra LIKE ? OR codigo LIKE ? OR marca LIKE ?',
      whereArgs: [q, q, q, q],
      orderBy: 'desc COLLATE NOCASE',
      limit: limit,
      offset: offset,
    );
    return rows.map(Producto.fromMap).toList();
  }

  static Future<int> contar({String? query}) async {
    final database = await db;
    if (query == null || query.isEmpty) {
      final result = await database.rawQuery('SELECT COUNT(*) as c FROM productos');
      return result.first['c'] as int;
    }
    final q = '%$query%';
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM productos WHERE desc LIKE ? OR barra LIKE ? OR codigo LIKE ? OR marca LIKE ?',
      [q, q, q, q],
    );
    return result.first['c'] as int;
  }

  static Future<Producto?> buscarPorBarra(String barra) async {
    final database = await db;
    final rows = await database.query(
      'productos',
      where: 'barra = ?',
      whereArgs: [barra],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Producto.fromMap(rows.first);
  }

  static Future<String> proximoCodigo() async {
    final database = await db;
    final result = await database.rawQuery(
      "SELECT MAX(CAST(codigo AS INTEGER)) as max_cod FROM productos WHERE codigo != '' AND codigo GLOB '[0-9]*'",
    );
    final maxCod = result.first['max_cod'];
    if (maxCod == null) return '1';
    return ((maxCod as int) + 1).toString();
  }

  static Future<void> insertar(Producto producto) async {
    final database = await db;
    await database.insert('productos', producto.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertarLote(List<Producto> productos) async {
    final database = await db;
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final prod in productos) {
        batch.insert('productos', prod.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> actualizar(Producto producto) async {
    final database = await db;
    await database.update(
      'productos',
      producto.toMap(),
      where: 'id = ?',
      whereArgs: [producto.id],
    );
  }

  static Future<void> eliminar(int id) async {
    final database = await db;
    await database.delete('productos', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> eliminarTodos() async {
    final database = await db;
    await database.delete('productos');
  }

  static Future<List<Producto>> todos() async {
    final database = await db;
    final rows = await database.query('productos', orderBy: 'desc COLLATE NOCASE');
    return rows.map(Producto.fromMap).toList();
  }

  static Future<void> ajustarStock(
    int productoId,
    int delta, {
    required String tipo,
    required String motivo,
    required String productoDesc,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE productos SET stock = MAX(0, stock + ?) WHERE id = ?',
        [delta, productoId],
      );
      await txn.insert('movimientos_stock', {
        'producto_id': productoId,
        'producto_desc': productoDesc,
        'tipo': tipo,
        'cantidad': delta,
        'motivo': motivo,
        'fecha': DateTime.now().toIso8601String(),
      });
    });
  }

  static Future<void> descontarVenta(List<ArticuloCarrito> items) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final item in items) {
        if (item.producto.id == null) continue;
        await txn.rawUpdate(
          'UPDATE productos SET stock = MAX(0, stock - ?) WHERE id = ?',
          [item.cantidad, item.producto.id],
        );
        await txn.insert('movimientos_stock', {
          'producto_id': item.producto.id,
          'producto_desc': item.producto.desc,
          'tipo': 'venta',
          'cantidad': -item.cantidad,
          'motivo': 'Venta',
          'fecha': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  static Future<List<Producto>> productosConStockBajo() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT * FROM productos WHERE stock_minimo > 0 AND stock <= stock_minimo ORDER BY desc COLLATE NOCASE',
    );
    return rows.map(Producto.fromMap).toList();
  }

  static Future<List<MovimientoStock>> movimientosRecientes({int limit = 100}) async {
    final database = await db;
    final rows = await database.query(
      'movimientos_stock',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return rows.map(MovimientoStock.fromMap).toList();
  }
}

// ─────────────────────────────────────────────
// IMPORTACIÓN EN ISOLATE
// ─────────────────────────────────────────────

class _ParseArgs {
  final String path;
  final String ext;
  const _ParseArgs(this.path, this.ext);
}

List<Producto> _parsearArchivo(_ParseArgs args) {
  final file = File(args.path);
  final List<Producto> productos = [];

  if (args.ext == 'xlsx') {
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    for (final table in excel.tables.keys) {
      final rows = excel.tables[table]!.rows;
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length >= 6) {
          // Ignorar filas vacías — la descripción es obligatoria
          final desc = row[2]?.value?.toString().trim() ?? '';
          if (desc.isEmpty) continue;
          productos.add(Producto(
            codigo: row[0]?.value?.toString() ?? '',
            barra: row[1]?.value?.toString() ?? '',
            desc: desc,
            marca: row[3]?.value?.toString() ?? '',
            mayor: (row[4]?.value?.toString() ?? '0,00').replaceAll('.', ','),
            minor: (row[5]?.value?.toString() ?? '0,00').replaceAll('.', ','),
            prov: row.length > 6 ? row[6]?.value?.toString() ?? '' : '',
          ));
        }
      }
      break;
    }
  } else if (args.ext == 'csv') {
    String input;
    try {
      input = file.readAsStringSync(encoding: utf8);
    } catch (_) {
      input = file.readAsStringSync(encoding: latin1);
    }
    final lineas = input.split('\n');
    for (var i = 1; i < lineas.length; i++) {
      final linea = lineas[i].trim();
      if (linea.isEmpty) continue;
      final campos = linea.split(';');
      if (campos.length >= 6) {
        productos.add(Producto(
          codigo: campos[0].trim(),
          barra: campos[1].trim(),
          desc: campos[2].trim(),
          marca: campos[3].trim(),
          mayor: campos[4].trim().replaceAll('.', ','),
          minor: campos[5].trim().replaceAll('.', ','),
          prov: campos.length > 6 ? campos[6].trim() : '',
        ));
      }
    }
  }

  return productos;
}

// ─────────────────────────────────────────────
// CONSTANTES
// ─────────────────────────────────────────────

const _kRojo = Color(0xFFB71C1C);
const _kVerde = Colors.green;

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────

void main() {
  runApp(const MaterialApp(
    home: ListaPreciosApp(),
    debugShowCheckedModeBanner: false,
  ));
}

// ─────────────────────────────────────────────
// PANTALLA PRINCIPAL
// ─────────────────────────────────────────────

class ListaPreciosApp extends StatefulWidget {
  const ListaPreciosApp({super.key});

  @override
  State<ListaPreciosApp> createState() => _ListaPreciosAppState();
}

class _ListaPreciosAppState extends State<ListaPreciosApp> {
  List<Producto> _lista = [];
  int _totalCount = 0;
  bool _cargando = false;
  bool _hayMas = true;
  int _offset = 0;
  static const int _pageSize = 60;
  int? _selectedId;
  final List<ArticuloCarrito> _carrito = [];

  final TextEditingController _searchController = TextEditingController();
  String _queryActual = '';
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _actualizarContador();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _actualizarContador() async {
    final total = await DatabaseService.contar();
    if (mounted) setState(() => _totalCount = total);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hayMas &&
        !_cargando) {
      _cargarPagina();
    }
  }

  Future<void> _cargarPagina({bool reset = false}) async {
    if (_cargando) return;
    if (_queryActual.isEmpty) {
      setState(() {
        _lista = [];
        _cargando = false;
        _selectedId = null;
      });
      return;
    }

    setState(() => _cargando = true);

    if (reset) {
      _offset = 0;
      _hayMas = true;
      _selectedId = null;
    }

    final query = _queryActual;
    final nuevos = await DatabaseService.buscar(query, limit: _pageSize, offset: _offset);
    final total = await DatabaseService.contar(query: query);

    setState(() {
      _lista = reset ? nuevos : [..._lista, ...nuevos];
      _totalCount = total;
      _offset += nuevos.length;
      _hayMas = nuevos.length == _pageSize;
      _cargando = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final trimmed = value.trim();
      setState(() => _queryActual = trimmed);
      if (trimmed.isEmpty) {
        setState(() {
          _lista = [];
          _selectedId = null;
          _hayMas = false;
        });
        _actualizarContador();
      } else {
        _cargarPagina(reset: true);
      }
    });
  }

  Future<void> _escanearEnBusqueda() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const EscanerPage()),
    );
    if (codigo == null || !mounted) return;

    final existente = await DatabaseService.buscarPorBarra(codigo);
    if (!mounted) return;

    if (existente != null) {
      _searchController.text = codigo;
      setState(() => _queryActual = codigo);
      _cargarPagina(reset: true);
    } else {
      _abrirFormulario(barraPrecargada: codigo);
    }
  }

  Future<void> _importarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
    );
    if (result == null) return;

    final path = result.files.single.path!;
    final ext = result.files.single.extension ?? '';

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Procesando archivo...'),
          ],
        ),
      ),
    );

    try {
      final productos = await compute(_parsearArchivo, _ParseArgs(path, ext));
      await DatabaseService.eliminarTodos();
      await DatabaseService.insertarLote(productos);

      if (mounted) {
        Navigator.of(context).pop();
        _searchController.clear();
        setState(() {
          _queryActual = '';
          _lista = [];
          _totalCount = productos.length;
          _selectedId = null;
          _offset = 0;
          _hayMas = false;
          _cargando = false;
        });
        _notificar('${productos.length} productos importados');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _notificar('Error al procesar el archivo');
      }
    }
  }

  Future<void> _compartirExcel() async {
    if (_totalCount == 0) {
      _notificar('No hay productos para exportar');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Generando Excel...'),
          ],
        ),
      ),
    );

    try {
      final todos = await DatabaseService.todos();
      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) excel.rename('Sheet1', 'Precios');
      excel.sheets.keys.where((n) => n != 'Precios').toList().forEach(excel.delete);
      final sheet = excel['Precios'];

      sheet.appendRow([
        TextCellValue('CODIGO INTERNO'),
        TextCellValue('CODIGO DE BARRAS'),
        TextCellValue('DESCRIPCION'),
        TextCellValue('MARCA'),
        TextCellValue('MAYOR'),
        TextCellValue('MINOR'),
        TextCellValue('PROVEEDOR'),
        TextCellValue('STOCK'),
        TextCellValue('STOCK MINIMO'),
      ]);

      for (final prod in todos) {
        sheet.appendRow([
          TextCellValue(prod.codigo),
          TextCellValue(prod.barra),
          TextCellValue(prod.desc),
          TextCellValue(prod.marca),
          TextCellValue(prod.mayor),
          TextCellValue(prod.minor),
          TextCellValue(prod.prov),
          TextCellValue(prod.stock.toString()),
          TextCellValue(prod.stockMinimo.toString()),
        ]);
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('bytes null');

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/Lista_Precios_Torreon.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        Navigator.of(context).pop();
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: 'Lista de precios El Torreon',
        ));
      }
    } catch (e, stack) {
      debugPrint('ERROR EXCEL: $e\n$stack');
      if (mounted) {
        Navigator.of(context).pop();
        _notificar('Error al generar el Excel');
      }
    }
  }

  Future<void> _eliminarProducto(Producto producto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminás "${producto.desc}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true && producto.id != null) {
      await DatabaseService.eliminar(producto.id!);
      await _cargarPagina(reset: true);
      await _actualizarContador();
    }
  }

  void _agregarAlCarrito(Producto prod) {
    final cantCtrl = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prod.desc,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\$${prod.minor}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: _kRojo)),
            if (prod.stock > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Stock disponible: ${prod.stock}',
                    style: TextStyle(
                        fontSize: 13,
                        color: prod.stockBajo ? Colors.orange : Colors.green)),
              ),
            if (prod.sinStock)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('⚠️ Sin stock',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: cantCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final cantidad = int.tryParse(cantCtrl.text) ?? 1;
              if (cantidad > 0) {
                setState(() {
                  final index =
                      _carrito.indexWhere((item) => item.producto.id == prod.id);
                  if (index >= 0) {
                    _carrito[index].cantidad += cantidad;
                  } else {
                    _carrito.add(ArticuloCarrito(producto: prod, cantidad: cantidad));
                  }
                  _selectedId = null;
                });
                Navigator.pop(ctx);
                _notificar('${cantidad}x ${prod.desc} agregado');
              }
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Agregar'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kVerde, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _notificar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _abrirFormulario({Producto? existente, String? barraPrecargada}) {
    final esNuevo = existente == null;
    final controllers = {
      'BARRA': TextEditingController(text: barraPrecargada ?? existente?.barra ?? ''),
      'DESC': TextEditingController(text: existente?.desc ?? ''),
      'MARCA': TextEditingController(text: existente?.marca ?? ''),
      'MAYOR': TextEditingController(text: existente?.mayor ?? ''),
      'MINOR': TextEditingController(text: existente?.minor ?? ''),
      'PROV': TextEditingController(text: existente?.prov ?? ''),
      'STOCK': TextEditingController(text: existente?.stock.toString() ?? '0'),
      'STOCK_MIN': TextEditingController(text: existente?.stockMinimo.toString() ?? '0'),
    };
    final nodes = List.generate(8, (_) => FocusNode());

    final Future<String> codigoFuturo = esNuevo
        ? DatabaseService.proximoCodigo()
        : Future.value(existente?.codigo ?? '');

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<String>(
        future: codigoFuturo,
        builder: (ctx, snapshot) {
          final codigoMostrado = snapshot.data ?? '...';
          return AlertDialog(
            title: Text(esNuevo ? 'Nuevo producto' : 'Editar producto'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Código interno',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[100],
                        prefixIcon: const Icon(Icons.tag),
                      ),
                      controller: TextEditingController(text: codigoMostrado),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controllers['BARRA']!,
                            focusNode: nodes[0],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Código de barras',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) =>
                                FocusScope.of(ctx).requestFocus(nodes[1]),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: _kRojo,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final codigo = await Navigator.push<String>(
                                ctx,
                                MaterialPageRoute(
                                    builder: (_) => const EscanerPage()),
                              );
                              if (codigo != null) {
                                controllers['BARRA']!.text = codigo;
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.qr_code_scanner,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _campoForm(controllers['DESC']!, nodes[1], nodes[2], 'Descripción'),
                  _campoForm(controllers['MARCA']!, nodes[2], nodes[3], 'Marca'),
                  _campoForm(controllers['MAYOR']!, nodes[3], nodes[4], 'Precio mayorista', isNum: true),
                  _campoForm(controllers['MINOR']!, nodes[4], nodes[5], 'Precio minorista', isNum: true),
                  _campoForm(controllers['PROV']!, nodes[5], nodes[6], 'Proveedor'),
                  _campoForm(controllers['STOCK']!, nodes[6], nodes[7], 'Stock actual', isNum: true),
                  _campoForm(controllers['STOCK_MIN']!, nodes[7], null, 'Stock mínimo', isNum: true),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _liberarFormulario(controllers, nodes);
                  Navigator.pop(ctx);
                },
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final mayorStr = controllers['MAYOR']!.text.replaceAll(',', '.');
                  final minorStr = controllers['MINOR']!.text.replaceAll(',', '.');
                  if (double.tryParse(mayorStr) == null ||
                      double.tryParse(minorStr) == null) {
                    _notificar('Los precios deben ser números válidos');
                    return;
                  }

                  final producto = Producto(
                    id: existente?.id,
                    codigo: esNuevo
                        ? await DatabaseService.proximoCodigo()
                        : existente?.codigo ?? '',
                    barra: controllers['BARRA']!.text.trim(),
                    desc: controllers['DESC']!.text.trim(),
                    marca: controllers['MARCA']!.text.trim(),
                    mayor: controllers['MAYOR']!.text.trim(),
                    minor: controllers['MINOR']!.text.trim(),
                    prov: controllers['PROV']!.text.trim(),
                    stock: int.tryParse(controllers['STOCK']!.text) ?? 0,
                    stockMinimo: int.tryParse(controllers['STOCK_MIN']!.text) ?? 0,
                  );

                  if (esNuevo) {
                    await DatabaseService.insertar(producto);
                  } else {
                    await DatabaseService.actualizar(producto);
                  }

                  _liberarFormulario(controllers, nodes);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _cargarPagina(reset: true);
                  await _actualizarContador();
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _liberarFormulario(
      Map<String, TextEditingController> controllers, List<FocusNode> nodes) {
    for (final c in controllers.values) {
      c.dispose();
    }
    for (final n in nodes) {
      n.dispose();
    }
  }

  Widget _campoForm(
    TextEditingController ctrl,
    FocusNode current,
    FocusNode? next,
    String label, {
    bool isNum = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        focusNode: current,
        keyboardType: isNum
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textInputAction: next != null ? TextInputAction.next : TextInputAction.done,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onSubmitted: (_) {
          if (next != null) FocusScope.of(current.context!).requestFocus(next);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitulo = _queryActual.isEmpty
        ? '$_totalCount productos cargados'
        : '${_lista.length} de $_totalCount resultados';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kRojo,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: const Text('El Torreón',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        leading: FutureBuilder<List<Producto>>(
          future: DatabaseService.productosConStockBajo(),
          builder: (ctx, snap) {
            final alertas = snap.data?.length ?? 0;
            return Stack(
              children: [
                Builder(
                  builder: (ctx2) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    onPressed: () => Scaffold.of(ctx2).openDrawer(),
                  ),
                ),
                if (alertas > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$alertas',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: _kRojo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('El Torreón',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Menú principal',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: _kRojo),
              title: const Text('Nuevo producto'),
              onTap: () {
                Navigator.pop(context);
                _abrirFormulario();
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2, color: _kRojo),
              title: const Text('Control de stock'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockPage()),
                );
                setState(() {});
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.black54),
              title: const Text('Exportar Excel'),
              onTap: () {
                Navigator.pop(context);
                _compartirExcel();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.black54),
              title: const Text('Importar archivo'),
              onTap: () {
                Navigator.pop(context);
                _importarArchivo();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar por descripción, código, marca...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _queryActual.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _kRojo,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _escanearEnBusqueda,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.qr_code_scanner,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitulo,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ),
          Expanded(
            child: _queryActual.isEmpty && _lista.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search, size: 64, color: Colors.black12),
                        SizedBox(height: 12),
                        Text('Buscá un producto o escaneá un código',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _lista.isEmpty && !_cargando
                    ? const Center(
                        child: Text('Sin resultados',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _lista.length + (_hayMas ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _lista.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final prod = _lista[index];
                          final isSelected = _selectedId == prod.id;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            color: isSelected ? Colors.red[50] : null,
                            child: ListTile(
                              onTap: () => setState(() {
                                _selectedId = isSelected ? null : prod.id;
                              }),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(prod.desc,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                  ),
                                  if (prod.sinStock)
                                    _badge('SIN STOCK', Colors.red)
                                  else if (prod.stockBajo)
                                    _badge('Stock: ${prod.stock}', Colors.orange),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('\$${prod.minor}',
                                      style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold)),
                                  Text('Mayor: \$${prod.mayor}  |  ${prod.marca}',
                                      style: const TextStyle(
                                          color: Colors.black54, fontSize: 12)),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: isSelected
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.add_shopping_cart,
                                              color: Colors.green),
                                          onPressed: () => _agregarAlCarrito(prod),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () =>
                                              _abrirFormulario(existente: prod),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () => _eliminarProducto(prod),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _carrito.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CarritoPage(
                            carrito: _carrito,
                            onUpdate: () => setState(() {}),
                            onNuevaCompra: () => setState(() {
                              _carrito.clear();
                              _queryActual = '';
                              _lista = [];
                              _searchController.clear();
                            }),
                          ))),
              label: Text('${_carrito.length} items'),
              icon: const Icon(Icons.shopping_cart),
              backgroundColor: _kVerde,
            )
          : null,
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────
// PANTALLA CARRITO
// ─────────────────────────────────────────────

class CarritoPage extends StatefulWidget {
  final List<ArticuloCarrito> carrito;
  final VoidCallback onUpdate;
  final VoidCallback onNuevaCompra;

  const CarritoPage({
    super.key,
    required this.carrito,
    required this.onUpdate,
    required this.onNuevaCompra,
  });

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  double get total =>
      widget.carrito.fold(0, (sum, item) => sum + item.subtotal);

  void _compartirCompra() {
    String m = "🛍️ *Compra El Torreón*\n\n";
    for (final item in widget.carrito) {
      m += "• ${item.cantidad}x ${item.producto.desc} (\$${item.producto.minor}) -> *\$${item.subtotal.toStringAsFixed(2).replaceAll('.', ',')}*\n";
    }
    m += "\n💰 *TOTAL: \$${total.toStringAsFixed(2).replaceAll('.', ',')}*";
    SharePlus.instance.share(ShareParams(text: m));
  }

  Future<void> _finalizarCompra() async {
    // Chequear stock insuficiente
    final sinStockSuf = widget.carrito
        .where((i) => i.producto.stock < i.cantidad)
        .toList();

    bool descontar = true;

    if (sinStockSuf.isNotEmpty && mounted) {
      final lista = sinStockSuf
          .map((i) => '• ${i.producto.desc}: pedido ${i.cantidad}, stock ${i.producto.stock}')
          .join('\n');

      final respuesta = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stock insuficiente'),
          content: Text(
              'Los siguientes productos no tienen stock suficiente:\n\n$lista\n\n¿Descontás igual?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No descontar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kRojo, foregroundColor: Colors.white),
              child: const Text('Descontar igual'),
            ),
          ],
        ),
      );
      descontar = respuesta ?? false;
    }

    if (descontar) {
      await DatabaseService.descontarVenta(widget.carrito);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Compra'),
        content: const Text('¿Qué querés hacer con la compra?'),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _compartirCompra();
              },
              icon: const Icon(Icons.share),
              label: const Text('Compartir compra'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kVerde, foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onNuevaCompra();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.shopping_cart_checkout),
              label: const Text('Nueva compra'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kRojo, foregroundColor: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Carrito', style: TextStyle(color: Colors.white)),
        backgroundColor: _kVerde,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: widget.carrito.length,
              itemBuilder: (ctx, i) {
                final item = widget.carrito[i];
                return ListTile(
                  title: Text(item.producto.desc,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '\$${item.producto.minor} x ${item.cantidad} = \$${item.subtotal.toStringAsFixed(2).replaceAll('.', ',')}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: () {
                            setState(() {
                              if (item.cantidad > 1) {
                                item.cantidad--;
                              } else {
                                widget.carrito.removeAt(i);
                              }
                            });
                            widget.onUpdate();
                          }),
                      Text('${item.cantidad}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.green),
                          onPressed: () {
                            setState(() => item.cantidad++);
                            widget.onUpdate();
                          }),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12, blurRadius: 10, spreadRadius: 2)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(
                          '\$${total.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed:
                          widget.carrito.isEmpty ? null : _finalizarCompra,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('FINALIZAR COMPRA',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kRojo,
                          foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PANTALLA STOCK
// ─────────────────────────────────────────────

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Producto> _todos = [];
  List<Producto> _alertas = [];
  List<MovimientoStock> _movimientos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final todos = await DatabaseService.todos();
    final alertas = await DatabaseService.productosConStockBajo();
    final movs = await DatabaseService.movimientosRecientes();
    setState(() {
      _todos = todos;
      _alertas = alertas;
      _movimientos = movs;
      _cargando = false;
    });
  }

  Future<void> _registrarEntrada(Producto prod) async {
    final cantCtrl = TextEditingController(text: '1');
    final motivoCtrl = TextEditingController(text: 'Compra a proveedor');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entrada: ${prod.desc}',
            style: const TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock actual: ${prod.stock}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: cantCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Cantidad a ingresar',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Motivo', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () async {
              final cantidad = int.tryParse(cantCtrl.text) ?? 0;
              if (cantidad > 0 && prod.id != null) {
                await DatabaseService.ajustarStock(
                  prod.id!,
                  cantidad,
                  tipo: 'entrada',
                  motivo: motivoCtrl.text,
                  productoDesc: prod.desc,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarDatos();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Ingresar'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kVerde, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _registrarAjuste(Producto prod) async {
    final cantCtrl = TextEditingController(text: prod.stock.toString());
    final motivoCtrl = TextEditingController(text: 'Ajuste de inventario');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajuste: ${prod.desc}',
            style: const TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock actual: ${prod.stock}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: cantCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Nuevo stock total',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Motivo', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () async {
              final nuevoStock = int.tryParse(cantCtrl.text) ?? 0;
              if (prod.id != null) {
                final delta = nuevoStock - prod.stock;
                await DatabaseService.ajustarStock(
                  prod.id!,
                  delta,
                  tipo: 'ajuste',
                  motivo: motivoCtrl.text,
                  productoDesc: prod.desc,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarDatos();
              }
            },
            icon: const Icon(Icons.tune),
            label: const Text('Ajustar'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildItemStock(Producto prod) {
    Color stockColor;
    if (prod.sinStock) {
      stockColor = Colors.red;
    } else if (prod.stockBajo) {
      stockColor = Colors.orange;
    } else {
      stockColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Info del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prod.desc,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${prod.marca}  |  Mínimo: ${prod.stockMinimo}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            // Stock actual
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${prod.stock}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: stockColor),
                ),
                const Text('unid.', style: TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(width: 4),
            // Botón entrada
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
              tooltip: 'Entrada',
              onPressed: () => _registrarEntrada(prod),
            ),
            // Botón ajuste
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.orange, size: 24),
              tooltip: 'Ajuste',
              onPressed: () => _registrarAjuste(prod),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovimiento(MovimientoStock mov) {
    IconData icon;
    Color color;
    switch (mov.tipo) {
      case 'entrada':
        icon = Icons.arrow_downward;
        color = Colors.green;
        break;
      case 'venta':
        icon = Icons.arrow_upward;
        color = Colors.red;
        break;
      default:
        icon = Icons.tune;
        color = Colors.orange;
    }

    final fecha =
        '${mov.fecha.day.toString().padLeft(2, '0')}/${mov.fecha.month.toString().padLeft(2, '0')}/${mov.fecha.year} '
        '${mov.fecha.hour.toString().padLeft(2, '0')}:${mov.fecha.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(mov.productoDesc,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('${mov.motivo}  •  $fecha',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(
        '${mov.cantidad > 0 ? '+' : ''}${mov.cantidad}',
        style:
            TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Control de Stock', style: TextStyle(color: Colors.white)),
        backgroundColor: _kRojo,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(icon: Icon(Icons.inventory_2), text: 'Todo'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 18),
                  const SizedBox(width: 4),
                  Text('Alertas (${_alertas.length})'),
                ],
              ),
            ),
            const Tab(icon: Icon(Icons.history), text: 'Historial'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _cargarDatos,
                  child: ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (_, i) => _buildItemStock(_todos[i]),
                  ),
                ),
                _alertas.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 64, color: Colors.green),
                            SizedBox(height: 12),
                            Text('¡Todo el stock está OK!',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _cargarDatos,
                        child: ListView.builder(
                          itemCount: _alertas.length,
                          itemBuilder: (_, i) => _buildItemStock(_alertas[i]),
                        ),
                      ),
                _movimientos.isEmpty
                    ? const Center(
                        child: Text('Sin movimientos registrados',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _movimientos.length,
                        itemBuilder: (_, i) =>
                            _buildMovimiento(_movimientos[i]),
                      ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// ESCANER
// ─────────────────────────────────────────────

class EscanerPage extends StatefulWidget {
  const EscanerPage({super.key});

  @override
  State<EscanerPage> createState() => _EscanerPageState();
}

class _EscanerPageState extends State<EscanerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _detectado = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: _kRojo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) async {
          if (_detectado) return;
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            _detectado = true;
            final nav = Navigator.of(context);
            await _controller.stop();
            nav.pop(barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}