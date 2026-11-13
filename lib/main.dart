import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

void main() => runApp(const ShopManagerApp());

class ShopManagerApp extends StatelessWidget {
  const ShopManagerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'مدير المحل',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)), useMaterial3: true, fontFamily: 'Roboto'),
        home: const HomePage(),
      );
}

class StoreDb {
  StoreDb._();
  static final StoreDb instance = StoreDb._();
  Database? _db;
  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'shop_manager.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE parties(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT \'\', kind TEXT NOT NULL)');
      await db.execute('CREATE TABLE entries(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, party_id INTEGER, party_name TEXT NOT NULL, amount REAL NOT NULL, paid REAL NOT NULL, note TEXT NOT NULL DEFAULT \'\', created_at TEXT NOT NULL)');
    });
    return _db!;
  }
  Future<List<Map<String, Object?>>> parties(String kind) async => (await db).query('parties', where: 'kind = ?', whereArgs: [kind], orderBy: 'name COLLATE NOCASE');
  Future<void> addParty(String name, String phone, String kind) async => (await db).insert('parties', {'name': name.trim(), 'phone': phone.trim(), 'kind': kind});
  Future<List<Map<String, Object?>>> entries() async => (await db).query('entries', orderBy: 'id DESC');
  Future<void> addEntry({required String kind, required String name, int? partyId, required double amount, required double paid, required String note}) async => (await db).insert('entries', {'kind': kind, 'party_id': partyId, 'party_name': name, 'amount': amount, 'paid': paid, 'note': note, 'created_at': DateTime.now().toIso8601String()});
  Future<List<Map<String, Object?>>> summary() async {
    final d = await db;
    final sales = await d.rawQuery("SELECT COALESCE(SUM(amount),0) total FROM entries WHERE kind='بيع'");
    final purchases = await d.rawQuery("SELECT COALESCE(SUM(amount),0) total FROM entries WHERE kind='شراء'");
    final dueCustomers = await d.rawQuery("SELECT COALESCE(SUM(amount-paid),0) total FROM entries WHERE kind='بيع'");
    final dueSuppliers = await d.rawQuery("SELECT COALESCE(SUM(amount-paid),0) total FROM entries WHERE kind='شراء'");
    return [sales.first, purchases.first, dueCustomers.first, dueSuppliers.first];
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  int refresh = 0;
  void reload() => setState(() => refresh++);
  @override
  Widget build(BuildContext context) {
    final pages = [Dashboard(key: ValueKey('d$refresh')), PartyPage(kind: 'عميل', key: ValueKey('c$refresh')), PartyPage(kind: 'مورد', key: ValueKey('s$refresh')), EntriesPage(key: ValueKey('e$refresh'))];
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('مدير المحل'), centerTitle: true),
      body: pages[tab],
      floatingActionButton: tab == 3 ? FloatingActionButton.extended(onPressed: () async { await showEntryForm(context); reload(); }, icon: const Icon(Icons.add), label: const Text('حركة جديدة')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'), NavigationDestination(icon: Icon(Icons.people_outline), label: 'العملاء'), NavigationDestination(icon: Icon(Icons.local_shipping_outlined), label: 'الموردون'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'الحركات')]),
    ));
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  String money(Object? value) => '${NumberFormat('#,##0.##').format((value as num?) ?? 0)}';
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.summary(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final labels = ['إجمالي المبيعات', 'إجمالي المشتريات', 'ديون العملاء', 'مستحقات الموردين'];
    final icons = [Icons.trending_up, Icons.shopping_bag_outlined, Icons.person_search, Icons.local_shipping];
    return ListView(padding: const EdgeInsets.all(16), children: [Text('ملخص النشاط', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 12), GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: labels.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.35, crossAxisSpacing: 12, mainAxisSpacing: 12), itemBuilder: (_, i) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icons[i], color: Theme.of(context).colorScheme.primary), Text(labels[i]), Text(money(snap.data![i]['total']), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))]))))]);
  });
}

class PartyPage extends StatefulWidget {
  const PartyPage({required this.kind, super.key});
  final String kind;
  @override
  State<PartyPage> createState() => _PartyPageState();
}
class _PartyPageState extends State<PartyPage> {
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.parties(widget.kind), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final people = snap.data!;
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton(onPressed: () async { await showPartyForm(context, widget.kind); setState(() {}); }, child: const Icon(Icons.person_add_alt_1)), body: people.isEmpty ? Center(child: Text('لا يوجد ${widget.kind}ون بعد\nاضغط + لإضافة ${widget.kind}', textAlign: TextAlign.center)) : ListView.builder(itemCount: people.length, itemBuilder: (_, i) { final person = people[i]; return ListTile(leading: CircleAvatar(child: Icon(widget.kind == 'عميل' ? Icons.person : Icons.local_shipping)), title: Text(person['name'] as String), subtitle: Text((person['phone'] as String).isEmpty ? 'بدون رقم هاتف' : person['phone'] as String)); }));
  });
}

class EntriesPage extends StatelessWidget {
  const EntriesPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.entries(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snap.data!;
    if (rows.isEmpty) return const Center(child: Text('لا توجد حركات مسجلة\nاستخدم زر «حركة جديدة» للبدء', textAlign: TextAlign.center));
    return ListView.separated(padding: const EdgeInsets.only(bottom: 88), itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) { final row = rows[i]; final kind = row['kind'] as String; final amount = row['amount'] as num; final paid = row['paid'] as num; final date = DateTime.tryParse(row['created_at'] as String); return ListTile(leading: CircleAvatar(child: Icon(kind == 'بيع' ? Icons.south_west : Icons.north_east)), title: Text('$kind — ${row['party_name']}'), subtitle: Text('${date == null ? '' : DateFormat('yyyy/MM/dd  HH:mm').format(date)}  •  مدفوع ${NumberFormat('#,##0.##').format(paid)}  •  متبقٍ ${NumberFormat('#,##0.##').format(amount - paid)}'), trailing: Text(NumberFormat('#,##0.##').format(amount), style: const TextStyle(fontWeight: FontWeight.bold))); });
  });
}

Future<void> showPartyForm(BuildContext context, String kind) async {
  final form = GlobalKey<FormState>(); final name = TextEditingController(); final phone = TextEditingController();
  await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text('إضافة $kind'), content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم'), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل الاسم' : null), TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)'))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { if (!form.currentState!.validate()) return; await StoreDb.instance.addParty(name.text, phone.text, kind); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('حفظ'))]));
  name.dispose(); phone.dispose();
}

Future<void> showEntryForm(BuildContext context) async {
  final form = GlobalKey<FormState>(); final amount = TextEditingController(); final paid = TextEditingController(text: '0'); final note = TextEditingController();
  String kind = 'بيع'; int? partyId; String partyName = 'زبون نقدي';
  await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(title: const Text('تسجيل حركة'), content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: kind, decoration: const InputDecoration(labelText: 'نوع الحركة'), items: const [DropdownMenuItem(value: 'بيع', child: Text('بيع')), DropdownMenuItem(value: 'شراء', child: Text('شراء'))], onChanged: (v) { if (v != null) setDialog(() { kind = v; partyId = null; partyName = v == 'بيع' ? 'زبون نقدي' : 'مورد نقدي'; }); }), FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.parties(kind == 'بيع' ? 'عميل' : 'مورد'), builder: (_, snap) { final list = snap.data ?? []; return DropdownButtonFormField<int?>(value: partyId, decoration: InputDecoration(labelText: kind == 'بيع' ? 'العميل (اختياري)' : 'المورد (اختياري)'), items: [const DropdownMenuItem<int?>(value: null, child: Text('نقدي / غير محدد')), ...list.map((x) => DropdownMenuItem<int?>(value: x['id'] as int, child: Text(x['name'] as String)))], onChanged: (v) => setDialog(() { partyId = v; if (v != null) partyName = list.firstWhere((x) => x['id'] == v)['name'] as String; else partyName = kind == 'بيع' ? 'زبون نقدي' : 'مورد نقدي'; })); }), TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ الإجمالي'), validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'أدخل مبلغًا صحيحًا' : null), TextFormField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ المدفوع'), validator: (v) { final a = double.tryParse(amount.text) ?? 0; final b = double.tryParse(v ?? '') ?? -1; return b < 0 || b > a ? 'تحقق من المبلغ المدفوع' : null; }), TextFormField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'))]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () async { if (!form.currentState!.validate()) return; await StoreDb.instance.addEntry(kind: kind, name: partyName, partyId: partyId, amount: double.parse(amount.text), paid: double.parse(paid.text.isEmpty ? '0' : paid.text), note: note.text.trim()); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('حفظ'))])));
  amount.dispose(); paid.dispose(); note.dispose();
}
