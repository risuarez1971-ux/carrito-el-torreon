import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_lib;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// --- MODELOS ---

class Producto {
  final int? id;
  final String codigo;
  final String barra;
  final String desc;
  final String marca;
  final String mayor;
  final String minor;
  final String prov;

  const Producto({
    this.id,
    required this.codigo,
    required this.barra,
    required this.desc,
    required this.marca,
    required this.mayor,
    required this.minor,
    required this.prov,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'codigo': codigo,
        'barra': barra,
        'desc': desc,
        'marca': marca,
        'mayor': mayor,
        'minor': minor,
        'prov': prov,
      };

  factory Producto.fromMap(Map<String, dynamic> m) => Producto(
        id: m['id'] as int?,
        codigo: m['codigo']?.toString() ?? '',
        barra: m['barra']?.toString() ?? '',
        desc: m['desc']?.toString() ?? '',
        marca: m['marca']?.toString() ?? '',
        mayor: m['mayor']?.toString() ?? '0,00',
        minor: m['minor']?.toString() ?? '0,00',
        prov: m['prov']?.toString() ?? '',
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

// --- BASE DE DATOS ---

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path_lib.join(dbPath, 'torreon.db'); // FIX #1 aplicado
    return openDatabase(
      fullPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE productos (
            id    INTEGER PRIMARY KEY AUTOINCREMENT,
            codigo TEXT,
            barra  TEXT,
            desc   TEXT,
            marca  TEXT,
            mayor  TEXT,
            minor  TEXT,
            prov   TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_desc  ON productos(desc COLLATE NOCASE)');
        await db.execute('CREATE INDEX idx_barra ON productos(barra)');
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
      final result =
          await database.rawQuery('SELECT COUNT(*) as c FROM productos');
      return result.first['c'] as int;
    }
    final q = '%$query%';
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM productos WHERE desc LIKE ? OR barra LIKE ? OR codigo LIKE ? OR marca LIKE ?',
      [q, q, q, q],
    );
    return result.first['c'] as int;
  }

  static Future<void> insertarLote(List<Producto> ps) async {
    final d = await db;
    await d.transaction((txn) async {
      final b = txn.batch();
      for (final prod in ps) { // FIX #1 aplicado: 'p' → 'prod'
        b.insert('productos', prod.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await b.commit(noResult: true);
    });
  }

  static Future<void> insertar(Producto prod) async => // FIX #1: 'p' → 'prod'
      (await db).insert('productos', prod.toMap());
  static Future<void> actualizar(Producto prod) async => // FIX #1: 'p' → 'prod'
      (await db).update('productos', prod.toMap(),
          where: 'id = ?', whereArgs: [prod.id]);
  static Future<void> eliminar(int id) async =>
      (await db).delete('productos', where: 'id = ?', whereArgs: [id]);
  static Future<void> eliminarTodos() async =>
      (await db).delete('productos');
  static Future<List<Producto>> todos() async =>
      (await db)
          .query('productos', orderBy: 'desc COLLATE NOCASE')
          .then((r) => r.map(Producto.fromMap).toList());
}

// --- UI PRINCIPAL ---

const _kRojo = Color(0xFFB71C1C);

void main() => runApp(const MaterialApp(
    home: ListaPreciosApp(), debugShowCheckedModeBanner: false));

class ListaPreciosApp extends StatefulWidget {
  const ListaPreciosApp({super.key});
  @override
  State<ListaPreciosApp> createState() => _ListaPreciosAppState();
}

class _ListaPreciosAppState extends State<ListaPreciosApp> {
  List<Producto> _lista = [];
  final List<ArticuloCarrito> _carrito = [];
  int _totalDbCount = 0;
  bool _cargando = false;
  bool _hayMas = true;
  int _offset = 0;
  int? _selectedId;
  String _queryActual = '';
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _actualizarContador();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          _hayMas &&
          !_cargando) {
        _cargarPagina();
      }
    });
  }

  // FIX #2: dispose correcto — cancela debounce y libera controladores
  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _actualizarContador() async {
    final t = await DatabaseService.contar();
    if (mounted) setState(() => _totalDbCount = t);
  }

  Future<void> _cargarPagina({bool reset = false}) async {
    if (_queryActual.isEmpty) {
      setState(() {
        _lista = [];
        _cargando = false;
      });
      return;
    }
    if (reset) {
      _offset = 0;
      _hayMas = true;
      _selectedId = null;
    }
    if (_cargando) return;

    setState(() => _cargando = true);
    final nuevos = await DatabaseService.buscar(_queryActual,
        limit: 60, offset: _offset);

    // FIX #3: si devuelve menos de 60, ya no hay más — evita petición extra vacía
    setState(() {
      _lista = reset ? nuevos : [..._lista, ...nuevos];
      _offset += nuevos.length;
      _hayMas = nuevos.length == 60; // solo hay más si vino la página completa
      _cargando = false;
    });
  }

  void _agregarAlCarrito(Producto prod) { // FIX #1: 'p' → 'prod'
    setState(() {
      final index =
          _carrito.indexWhere((item) => item.producto.id == prod.id);
      if (index >= 0) {
        _carrito[index].cantidad++;
      } else {
        _carrito.add(ArticuloCarrito(producto: prod));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${prod.desc} agregado'),
      duration: const Duration(seconds: 1),
      backgroundColor: Colors.green,
    ));
  }

  // --- MÉTODOS DE SOPORTE ---

  Future<void> _importarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (result == null) return;

    setState(() => _cargando = true);
    try {
      final file = File(result.files.single.path!);
      final extension = result.files.single.extension;
      List<Producto> productos = [];

      if (extension == 'xlsx') {
        final excel = Excel.decodeBytes(file.readAsBytesSync());
        for (var table in excel.tables.keys) {
          final rows = excel.tables[table]!.rows;
          for (var i = 1; i < rows.length; i++) {
            final row = rows[i];
            if (row.length >= 6) {
              productos.add(Producto(
                codigo: row[0]?.value?.toString() ?? '',
                barra: row[1]?.value?.toString() ?? '',
                desc: row[2]?.value?.toString() ?? '',
                marca: row[3]?.value?.toString() ?? '',
                mayor: row[4]?.value?.toString().replaceAll('.', ',') ??
                    '0,00',
                minor: row[5]?.value?.toString().replaceAll('.', ',') ??
                    '0,00',
                prov: row.length > 6
                    ? row[6]?.value?.toString() ?? ''
                    : '',
              ));
            }
          }
        }
      } else if (extension == 'csv') {
        // FIX #4: CSV ahora implementado (separador ';' — estándar Argentina)
        final lines = file.readAsLinesSync();
        for (var i = 1; i < lines.length; i++) {
          final cols = lines[i].split(';');
          if (cols.length >= 6) {
            productos.add(Producto(
              codigo: cols[0].trim(),
              barra:  cols[1].trim(),
              desc:   cols[2].trim(),
              marca:  cols[3].trim(),
              mayor:  cols[4].trim().replaceAll('.', ','),
              minor:  cols[5].trim().replaceAll('.', ','),
              prov:   cols.length > 6 ? cols[6].trim() : '',
            ));
          }
        }
      } else {
        // FIX #4: formato no soportado — avisa al usuario
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Formato no soportado. Usá .xlsx o .csv')),
          );
        }
        setState(() => _cargando = false);
        return;
      }

      if (productos.isNotEmpty) {
        await DatabaseService.eliminarTodos();
        await DatabaseService.insertarLote(productos);
        await _actualizarContador();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${productos.length} productos importados')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El archivo no contiene datos válidos')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al importar: $e')));
      }
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _compartirExcel() async {
    final productos = await DatabaseService.todos();
    if (productos.isEmpty) return;

    final excel = Excel.createExcel();
    final sheet = excel['Precios'];
    sheet.appendRow([
      TextCellValue('Código'),
      TextCellValue('Barra'),
      TextCellValue('Descripción'),
      TextCellValue('Marca'),
      TextCellValue('Mayor'),
      TextCellValue('Minor'),
      TextCellValue('Prov'),
    ]);

    for (final prod in productos) { // FIX #1: 'p' → 'prod'
      sheet.appendRow([
        TextCellValue(prod.codigo),
        TextCellValue(prod.barra),
        TextCellValue(prod.desc),
        TextCellValue(prod.marca),
        TextCellValue(prod.mayor),
        TextCellValue(prod.minor),
        TextCellValue(prod.prov),
      ]);
    }

    final directory = await getTemporaryDirectory();
    final path = path_lib.join(directory.path, "Precios_Torreon.xlsx"); // FIX #1 aplicado
    final file = File(path)..writeAsBytesSync(excel.encode()!);

    await Share.shareXFiles([XFile(file.path)],
        text: 'Lista de Precios Abastecimiento El Torreón');
  }

  void _abrirFormulario({Producto? existente}) {
    final codCtrl = TextEditingController(text: existente?.codigo ?? '');
    final barCtrl = TextEditingController(text: existente?.barra ?? '');
    final desCtrl = TextEditingController(text: existente?.desc ?? '');
    final marCtrl = TextEditingController(text: existente?.marca ?? '');
    final mayCtrl = TextEditingController(text: existente?.mayor ?? '');
    final minCtrl = TextEditingController(text: existente?.minor ?? '');
    final proCtrl = TextEditingController(text: existente?.prov ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existente == null ? 'Nuevo Producto' : 'Editar Producto'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: codCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Código')),
              TextField(
                  controller: barCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Barra')),
              TextField(
                  controller: desCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Descripción')),
              TextField(
                  controller: marCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Marca')),
              TextField(
                  controller: mayCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Precio Mayor')),
              TextField(
                  controller: minCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Precio Minor')),
              TextField(
                  controller: proCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Proveedor')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              // FIX #1: variable local renombrada a 'nuevo' para evitar shadowing
              final nuevo = Producto(
                id: existente?.id,
                codigo: codCtrl.text,
                barra: barCtrl.text,
                desc: desCtrl.text,
                marca: marCtrl.text,
                mayor: mayCtrl.text,
                minor: minCtrl.text,
                prov: proCtrl.text,
              );
              try {
                if (existente == null) {
                  await DatabaseService.insertar(nuevo);
                } else {
                  await DatabaseService.actualizar(nuevo);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _actualizarContador();
                _cargarPagina(reset: true);
              } catch (e) {
                // FIX #5: manejo de error en guardar
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error al guardar: $e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Precios El Torreón',
                style: TextStyle(fontSize: 16, color: Colors.white)),
            Text(
                _queryActual.isEmpty
                    ? '$_totalDbCount productos'
                    : '${_lista.length} resultados',
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: _kRojo,
        actions: [
          IconButton(
              icon: const Icon(Icons.share), onPressed: _compartirExcel),
          IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _importarArchivo),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _abrirFormulario()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _queryActual.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(
                                    () => _queryActual = '');
                                _cargarPagina(reset: true);
                              })
                          : null,
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                          const Duration(milliseconds: 300), () {
                        if (!mounted) return; // FIX #2: guard extra
                        setState(() => _queryActual = v.trim());
                        _cargarPagina(reset: true);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: _kRojo),
                  icon: const Icon(Icons.qr_code_scanner,
                      color: Colors.white),
                  onPressed: () async {
                    final codigo = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EscanerPage()));
                    if (codigo != null) {
                      _searchController.text = codigo;
                      setState(() => _queryActual = codigo);
                      _cargarPagina(reset: true);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _lista.isEmpty && !_cargando
                ? Center(
                    child: Text(
                      _queryActual.isEmpty
                          ? 'Buscá un producto para empezar'
                          : 'Sin resultados para "$_queryActual"', // FIX: mensaje más útil
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _lista.length + (_hayMas ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _lista.length) {
                        return const Center(
                            child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator()));
                      }
                      final prod = _lista[i]; // FIX #1: 'p' → 'prod'
                      // FIX #6: comparación segura con null check
                      final isSelected =
                          prod.id != null && _selectedId == prod.id;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        color: isSelected ? Colors.red[50] : null,
                        child: ListTile(
                          onTap: () => setState(() =>
                              _selectedId = isSelected ? null : prod.id),
                          title: Text(prod.desc,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text('\$${prod.minor}',
                              style: const TextStyle(
                                  color: _kRojo,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          trailing: isSelected
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.add_shopping_cart,
                                      color: Colors.green),
                                  onPressed: () =>
                                      _agregarAlCarrito(prod))
                              : IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () =>
                                      _abrirFormulario(existente: prod)),
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
                            onNuevaCompra: () {
                              setState(() {
                                _carrito.clear();
                                _queryActual = '';
                                _lista = [];
                                _searchController.clear();
                              });
                            },
                          ))),
              label: Text('${_carrito.length} items'),
              icon: const Icon(Icons.shopping_cart),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }
}

// --- PÁGINA DEL CARRITO ---

class CarritoPage extends StatefulWidget {
  final List<ArticuloCarrito> carrito;
  final VoidCallback onUpdate;
  final VoidCallback onNuevaCompra;
  const CarritoPage(
      {super.key, required this.carrito, required this.onUpdate, required this.onNuevaCompra});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  double get total =>
      widget.carrito.fold(0, (sum, item) => sum + item.subtotal);

  void _compartirWhatsApp() {
    String m = "🛍️ *Pedido El Torreón*\n\n";
    for (var item in widget.carrito) {
      m +=
          "• ${item.cantidad}x ${item.producto.desc} (\$${item.producto.minor}) -> *\$${item.subtotal.toStringAsFixed(2).replaceAll('.', ',')}*\n";
    }
    m +=
        "\n💰 *TOTAL: \$${total.toStringAsFixed(2).replaceAll('.', ',')}*";
    Share.share(m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Carrito',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
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
                  title: Text(item.producto.desc),
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
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
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
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 2)
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
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
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
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: widget.carrito.isEmpty
                        ? null
                        : _compartirWhatsApp,
                    icon: const Icon(Icons.send),
                    label: const Text('COMPARTIR PEDIDO (WhatsApp)'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('¿Nueva compra?'),
                          content: const Text(
                              'Se va a vaciar el carrito y volver al buscador.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                widget.onNuevaCompra();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _kRojo,
                                  foregroundColor: Colors.white),
                              child: const Text('Sí, nueva compra'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text('FINALIZAR / NUEVA COMPRA'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kRojo,
                        foregroundColor: Colors.white),
                  ),
                )
              ],
            ),
          ))
        ],
      ),
    );
  }
}

// --- ESCANER ---

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
          title: const Text('Escanear Barra',
              style: TextStyle(color: Colors.white)),
          backgroundColor: _kRojo,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) async {
          if (_detectado) return;
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            _detectado = true;
            final rawValue = barcodes.first.rawValue;
            // Capturar el navigator ANTES del await evita usar
            // BuildContext a través de un gap asíncrono
            final nav = Navigator.of(context);
            await _controller.stop();
            nav.pop(rawValue);
          }
        },
      ),
    );
  }
}