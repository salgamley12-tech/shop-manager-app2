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
      version: 2,
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

  Future<void> addEntry({
    required String kind,
    required String partyName,
    int? partyId,
    required double amount,
    required double paid,
    String note = '',
  }) async {
    final database = await db;
    await database.insert('entries', {
      'kind': kind,
      'party_id': partyId,
      'party_name': partyName,
      'amount': amount,
      'paid': paid,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
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
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدير المحل'),
          centerTitle: true,
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
                    const Text('• سجل كل بيع وشراء بدقة\n• ر��قب ديون العملاء والموردين\n• أضف الأصناف قبل تسجيل المبيعات\n• استخدم التقارير لتتبع الأداء اليومي'),
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
              setState(() {});
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
              setState(() {});
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
              'لا توجد حركات مسجلة\nاضغط على زر + في شاشة الحركة لبدء السجل',
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

            return ListTile(
              leading: CircleAvatar(
                child: Icon(kind == 'بيع' ? Icons.south_west : Icons.north_east),
              ),
              title: Text('$kind — ${entry['party_name']}'),
              subtitle: Text(
                '${DateFormat('yyyy/MM/dd  HH:mm').format(createdAt)}${note.isEmpty ? '' : ' • $note'}',
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

// Reminder: next step can add a dedicated sale entry form tied to products and a stock update routine.
