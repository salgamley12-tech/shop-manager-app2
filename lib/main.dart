import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() => runApp(const ShopManagerApp());

class ShopManagerApp extends StatelessWidget {
  const ShopManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدير المحل',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
      ),
      home: const HomePage(),
    );
  }
}

class StoreDb {
  StoreDb._();
  static final StoreDb instance = StoreDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'shop_manager.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        purchase_price REAL NOT NULL DEFAULT 0,
        sale_price REAL NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        barcode TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        party_id INTEGER,
        party_name TEXT NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit_price REAL NOT NULL DEFAULT 0,
        amount REAL NOT NULL,
        paid REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          purchase_price REAL NOT NULL DEFAULT 0,
          sale_price REAL NOT NULL DEFAULT 0,
          stock REAL NOT NULL DEFAULT 0,
          barcode TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    if (oldVersion < 3) {
      final info = await db.rawQuery('PRAGMA table_info(entries)');
      final columns = info.map((e) => e['name'] as String).toList();
      if (!columns.contains('product_id')) {
        await db.execute('ALTER TABLE entries ADD COLUMN product_id INTEGER');
      }
      if (!columns.contains('product_name')) {
        await db.execute("ALTER TABLE entries ADD COLUMN product_name TEXT NOT NULL DEFAULT ''");
      }
      if (!columns.contains('quantity')) {
        await db.execute('ALTER TABLE entries ADD COLUMN quantity REAL NOT NULL DEFAULT 0');
      }
      if (!columns.contains('unit_price')) {
        await db.execute('ALTER TABLE entries ADD COLUMN unit_price REAL NOT NULL DEFAULT 0');
      }
    }
  }

  Future<List<Map<String, Object?>>> listParties(String kind) async {
    final database = await db;
    return database.query(
      'parties',
      where: 'kind = ?',
      whereArgs: [kind],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<void> addParty(String name, String phone, String kind) async {
    final database = await db;
    await database.insert('parties', {
      'name': name.trim(),
      'phone': phone.trim(),
      'kind': kind,
    });
  }

  Future<List<Map<String, Object?>>> listProducts() async {
    final database = await db;
    return database.query('products', orderBy: 'name COLLATE NOCASE');
  }

  Future<void> addProduct({
    required String name,
    required double purchasePrice,
    required double salePrice,
    required double stock,
    required String barcode,
  }) async {
    final database = await db;
    await database.insert('products', {
      'name': name.trim(),
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'stock': stock,
      'barcode': barcode.trim(),
    });
  }

  Future<void> addProductMovement({
    required String kind,
    required int productId,
    required int? partyId,
    required String partyName,
    required double quantity,
    required double unitPrice,
    required double paid,
    String note = '',
  }) async {
    final database = await db;
    final productRow = (await database.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    )).first;

    final currentStock = (productRow['stock'] as num?) ?? 0;
    final newStock = kind == 'بيع' ? currentStock - quantity : currentStock + quantity;

    if (newStock < 0) {
      throw Exception('الكمية المطلوبة أكبر من المخزون الحالي');
    }

    await database.transaction((txn) async {
      final totalAmount = quantity * unitPrice;
      await txn.insert('entries', {
        'kind': kind,
        'party_id': partyId,
        'party_name': partyName,
        'product_id': productId,
        'product_name': productRow['name'],
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': totalAmount,
        'paid': paid,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });

      await txn.update(
        'products',
        {'stock': newStock},
        where: 'id = ?',
        whereArgs: [productId],
      );
    });
  }

  Future<List<Map<String, Object?>>> getEntries() async {
    final database = await db;
    return database.query('entries', orderBy: 'id DESC');
  }

  Future<List<Map<String, Object?>>> getSummary() async {
    final database = await db;

    final sales = await database.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM entries WHERE kind = 'بيع'",
    );
    final purchases = await database.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM entries WHERE kind = 'شراء'",
    );
    final dueCustomers = await database.rawQuery(
      "SELECT COALESCE(SUM(amount - paid), 0) AS total FROM entries WHERE kind = 'بيع'",
    );
    final dueSuppliers = await database.rawQuery(
      "SELECT COALESCE(SUM(amount - paid), 0) AS total FROM entries WHERE kind = 'شراء'",
    );

    return [
      sales.first,
      purchases.first,
      dueCustomers.first,
      dueSuppliers.first,
    ];
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const DashboardPage(),
      const PartiesPage(kind: 'عميل'),
      const PartiesPage(kind: 'مورد'),
      const ProductsPage(),
      const EntriesPage(),
    ];

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدير المحل'),
          centerTitle: true,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (value) async {
                if (value == 'sale') {
                  await showSaleForm(context);
                } else if (value == 'purchase') {
                  await showPurchaseForm(context);
                }
                if (mounted) setState(() {});
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'sale', child: Text('بيع جديد')),
                PopupMenuItem(value: 'purchase', child: Text('شراء جديد')),
              ],
            ),
          ],
        ),
        body: pages[_selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (value) => setState(() => _selectedIndex = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'العملاء'),
            NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'الموردون'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'المخزن'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'الحركات'),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  String formatMoney(dynamic value) {
    final numValue = (value is num) ? value : 0;
    return NumberFormat('#,##0.##').format(numValue);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.getSummary(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final cards = [
          {'label': 'إجمالي المبيعات', 'value': data[0]['total'], 'icon': Icons.trending_up},
          {'label': 'إجمالي المشتريات', 'value': data[1]['total'], 'icon': Icons.shopping_bag_outlined},
          {'label': 'ديون العملاء', 'value': data[2]['total'], 'icon': Icons.person_outline},
          {'label': 'مستحقات الموردين', 'value': data[3]['total'], 'icon': Icons.local_shipping_outlined},
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'ملخص النشاط',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemBuilder: (context, index) {
                final card = cards[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(card['icon'] as IconData, color: Theme.of(context).colorScheme.primary),
                        Text(card['label'] as String),
                        Text(
                          formatMoney(card['value']),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملاحظات مهمة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('• سجل كل بيع وشراء بدقة\n• راقب ديون العملاء والموردين\n• أضف الأصناف قبل تسجيل المبيعات\n• استخدم التقارير لتتبع الأداء اليومي'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PartiesPage extends StatefulWidget {
  const PartiesPage({super.key, required this.kind});
  final String kind;

  @override
  State<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends State<PartiesPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.listParties(widget.kind),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final parties = snapshot.data!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await showPartyForm(context, widget.kind);
              if (mounted) setState(() {});
            },
            child: const Icon(Icons.person_add_alt_1),
          ),
          body: parties.isEmpty
              ? Center(
                  child: Text(
                    'لا يوجد ${widget.kind}ون بعد\nاضغط + لإضافة ${widget.kind}',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: parties.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final party = parties[index];
                    final name = party['name'] as String;
                    final phone = party['phone'] as String;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          widget.kind == 'عميل' ? Icons.person : Icons.local_shipping,
                        ),
                      ),
                      title: Text(name),
                      subtitle: Text(phone.isEmpty ? 'بدون رقم هاتف' : phone),
                    );
                  },
                ),
        );
      },
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.listProducts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await showProductForm(context);
              if (mounted) setState(() {});
            },
            child: const Icon(Icons.add_shopping_cart),
          ),
          body: products.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد أصناف بعد\nاضغط + لإضافة منتج جديد',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final stock = (product['stock'] as num?) ?? 0;
                    final purchase = (product['purchase_price'] as num?) ?? 0;
                    final sale = (product['sale_price'] as num?) ?? 0;
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                      title: Text(product['name'] as String),
                      subtitle: Text(
                        'شراء: ${NumberFormat('#,##0.##').format(purchase)} • بيع: ${NumberFormat('#,##0.##').format(sale)} • الكمية: ${NumberFormat('#,##0.##').format(stock)}',
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class EntriesPage extends StatelessWidget {
  const EntriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.getEntries(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snapshot.data!;

        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد حركات مسجلة\nاضغط على زر + في الأعلى لبدء السجل',
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final kind = entry['kind'] as String;
            final amount = (entry['amount'] as num?) ?? 0;
            final paid = (entry['paid'] as num?) ?? 0;
            final createdAt = DateTime.tryParse(entry['created_at'] as String) ?? DateTime.now();
            final note = (entry['note'] as String?) ?? '';
            final productName = (entry['product_name'] as String?) ?? '';

            return ListTile(
              leading: CircleAvatar(
                child: Icon(kind == 'بيع' ? Icons.south_west : Icons.north_east),
              ),
              title: Text('$kind — ${entry['party_name']}'),
              subtitle: Text(
                '${DateFormat('yyyy/MM/dd  HH:mm').format(createdAt)}${productName.isEmpty ? '' : ' • $productName'}${note.isEmpty ? '' : ' • $note'}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat('#,##0.##').format(amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'مدفوع: ${NumberFormat('#,##0.##').format(paid)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> showPartyForm(BuildContext context, String kind) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('إضافة $kind'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'أدخل الاسم';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await StoreDb.instance.addParty(
                nameController.text,
                phoneController.text,
                kind,
              );
              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  phoneController.dispose();
}

Future<void> showProductForm(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final purchaseController = TextEditingController();
  final saleController = TextEditingController();
  final stockController = TextEditingController();
  final barcodeController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('إضافة صنف جديد'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم الصنف'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'أدخل اسم الصنف';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: purchaseController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'سعر الشراء'),
                  validator: (value) {
                    if ((double.tryParse(value ?? '') ?? 0) < 0) {
                      return 'أدخل سعر شراء صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: saleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'سعر البيع'),
                  validator: (value) {
                    if ((double.tryParse(value ?? '') ?? 0) < 0) {
                      return 'أدخل سعر بيع صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: stockController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية الحالية'),
                  validator: (value) {
                    if ((double.tryParse(value ?? '') ?? 0) < 0) {
                      return 'أدخل كمية صحيحة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: barcodeController,
                  decoration: const InputDecoration(labelText: 'باركود (اختياري)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              await StoreDb.instance.addProduct(
                name: nameController.text,
                purchasePrice: double.parse(purchaseController.text),
                salePrice: double.parse(saleController.text),
                stock: double.parse(stockController.text),
                barcode: barcodeController.text,
              );

              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  purchaseController.dispose();
  saleController.dispose();
  stockController.dispose();
  barcodeController.dispose();
}

Future<void> showSaleForm(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final quantityController = TextEditingController(text: '1');
  final unitPriceController = TextEditingController();
  final paidController = TextEditingController();
  final noteController = TextEditingController();

  int? selectedPartyId;
  int? selectedProductId;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (stateContext, setDialogState) {
          return AlertDialog(
            title: const Text('بيع جديد'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: StoreDb.instance.listParties('عميل'),
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const [];
                        return DropdownButtonFormField<int>(
                          value: selectedPartyId,
                          decoration: const InputDecoration(labelText: 'العميل'),
                          items: [
                            const DropdownMenuItem<int>(value: -1, child: Text('اختر عميل')),
                            ...items.map((e) => DropdownMenuItem<int>(
                              value: (e['id'] as int),
                              child: Text(e['name'] as String),
                            )),
                          ],
                          onChanged: (value) => setDialogState(() => selectedPartyId = value == -1 ? null : value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: StoreDb.instance.listProducts(),
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const [];
                        return DropdownButtonFormField<int>(
                          value: selectedProductId,
                          decoration: const InputDecoration(labelText: 'الصنف'),
                          items: [
                            const DropdownMenuItem<int>(value: -1, child: Text('اختر صنف')),
                            ...items.map((e) => DropdownMenuItem<int>(
                              value: (e['id'] as int),
                              child: Text(e['name'] as String),
                            )),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedProductId = value == -1 ? null : value;
                              if (selectedProductId != null) {
                                final product = items.firstWhere((item) => (item['id'] as int) == selectedProductId);
                                unitPriceController.text = ((product['sale_price'] as num?) ?? 0).toString();
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الكمية'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '') ?? 0;
                        return parsed > 0 ? null : 'أدخل كمية صحيحة';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: unitPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '') ?? 0;
                        return parsed >= 0 ? null : 'أدخل سعر صحيح';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: paidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'المبلغ المدفوع'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (selectedPartyId == null || selectedPartyId == -1) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('اختَر عميلًا أولاً')),
                    );
                    return;
                  }
                  if (selectedProductId == null || selectedProductId == -1) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('اختَر صنفًا أولاً')),
                    );
                    return;
                  }

                  final productRow = (await StoreDb.instance.listProducts())
                      .firstWhere((row) => (row['id'] as int) == selectedProductId);
                  final stock = (productRow['stock'] as num?) ?? 0;
                  final quantity = double.parse(quantityController.text);
                  final unitPrice = double.parse(unitPriceController.text);
                  final paid = double.parse(paidController.text.isEmpty ? '0' : paidController.text);

                  if (quantity > stock) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('الكمية المطلوبة أكبر من المخزون')),
                    );
                    return;
                  }

                  final partyName = ((await StoreDb.instance.listParties('عميل')).firstWhere((row) => (row['id'] as int) == selectedPartyId))['name'] as String;

                  try {
                    await StoreDb.instance.addProductMovement(
                      kind: 'بيع',
                      productId: selectedProductId!,
                      partyId: selectedPartyId,
                      partyName: partyName,
                      quantity: quantity,
                      unitPrice: unitPrice,
                      paid: paid,
                      note: noteController.text,
                    );
                    if (context.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    },
  );

  quantityController.dispose();
  unitPriceController.dispose();
  paidController.dispose();
  noteController.dispose();
}

Future<void> showPurchaseForm(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final quantityController = TextEditingController(text: '1');
  final unitPriceController = TextEditingController();
  final paidController = TextEditingController();
  final noteController = TextEditingController();

  int? selectedPartyId;
  int? selectedProductId;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (stateContext, setDialogState) {
          return AlertDialog(
            title: const Text('شراء جديد'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: StoreDb.instance.listParties('مورد'),
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const [];
                        return DropdownButtonFormField<int>(
                          value: selectedPartyId,
                          decoration: const InputDecoration(labelText: 'المورد'),
                          items: [
                            const DropdownMenuItem<int>(value: -1, child: Text('اختر مورد')),
                            ...items.map((e) => DropdownMenuItem<int>(
                              value: (e['id'] as int),
                              child: Text(e['name'] as String),
                            )),
                          ],
                          onChanged: (value) => setDialogState(() => selectedPartyId = value == -1 ? null : value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: StoreDb.instance.listProducts(),
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const [];
                        return DropdownButtonFormField<int>(
                          value: selectedProductId,
                          decoration: const InputDecoration(labelText: 'الصنف'),
                          items: [
                            const DropdownMenuItem<int>(value: -1, child: Text('اختر صنف')),
                            ...items.map((e) => DropdownMenuItem<int>(
                              value: (e['id'] as int),
                              child: Text(e['name'] as String),
                            )),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedProductId = value == -1 ? null : value;
                              if (selectedProductId != null) {
                                final product = items.firstWhere((item) => (item['id'] as int) == selectedProductId);
                                unitPriceController.text = ((product['purchase_price'] as num?) ?? 0).toString();
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الكمية'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '') ?? 0;
                        return parsed > 0 ? null : 'أدخل كمية صحيحة';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: unitPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '') ?? 0;
                        return parsed >= 0 ? null : 'أدخل سعر صحيح';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: paidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'المبلغ المدفوع'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (selectedPartyId == null || selectedPartyId == -1) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('اختَر موردًا أولاً')),
                    );
                    return;
                  }
                  if (selectedProductId == null || selectedProductId == -1) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('اختَر صنفًا أولاً')),
                    );
                    return;
                  }

                  final productName = ((await StoreDb.instance.listProducts()).firstWhere((row) => (row['id'] as int) == selectedProductId))['name'] as String;
                  final partyName = ((await StoreDb.instance.listParties('مورد')).firstWhere((row) => (row['id'] as int) == selectedPartyId))['name'] as String;
                  final quantity = double.parse(quantityController.text);
                  final unitPrice = double.parse(unitPriceController.text);
                  final paid = double.parse(paidController.text.isEmpty ? '0' : paidController.text);

                  try {
                    await StoreDb.instance.addProductMovement(
                      kind: 'شراء',
                      productId: selectedProductId!,
                      partyId: selectedPartyId,
                      partyName: partyName,
                      quantity: quantity,
                      unitPrice: unitPrice,
                      paid: paid,
                      note: noteController.text,
                    );
                    if (context.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    },
  );

  quantityController.dispose();
  unitPriceController.dispose();
  paidController.dispose();
  noteController.dispose();
}
