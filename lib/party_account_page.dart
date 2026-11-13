import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'main.dart' show StoreDb;

/// كشف حساب لحركات عميل أو مورد.
/// افتح الصفحة باستخدام معرف الجهة واسمها ونوعها (عميل/مورد).
class PartyAccountPage extends StatelessWidget {
  const PartyAccountPage({
    super.key,
    required this.partyId,
    required this.partyName,
    required this.partyKind,
  });

  final int partyId;
  final String partyName;
  final String partyKind;

  String get _entryKind => partyKind == 'عميل' ? 'بيع' : 'شراء';

  String _money(num value) => NumberFormat('#,##0.##').format(value);

  Future<List<Map<String, Object?>>> _loadEntries() async {
    final database = await StoreDb.instance.db;
    return database.query(
      'entries',
      where: 'party_id = ? AND kind = ?',
      whereArgs: [partyId, _entryKind],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف حساب $partyKind'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _loadEntries(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل كشف الحساب: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!;
          num total = 0;
          num paid = 0;
          for (final entry in entries) {
            total += (entry['amount'] as num?) ?? 0;
            paid += (entry['paid'] as num?) ?? 0;
          }
          final balance = total - paid;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(partyName, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  child: Row(
                    children: [
                      _AccountTotal(label: 'إجمالي $_entryKind', value: _money(total)),
                      _AccountTotal(label: 'المدفوع', value: _money(paid)),
                      _AccountTotal(label: 'المتبقي', value: _money(balance)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('الحركات', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('لا توجد حركات مسجلة لهذا الحساب')),
                )
              else
                ...entries.map((entry) {
                  final amount = (entry['amount'] as num?) ?? 0;
                  final entryPaid = (entry['paid'] as num?) ?? 0;
                  final date = DateTime.tryParse(entry['created_at'] as String? ?? '');
                  final product = (entry['product_name'] as String?) ?? '';
                  final note = (entry['note'] as String?) ?? '';
                  final productTitle = product.isEmpty ? _entryKind : '$_entryKind — $product';

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(partyKind == 'عميل' ? Icons.point_of_sale : Icons.local_shipping_outlined),
                      ),
                      title: Text(productTitle),
                      subtitle: Text([
                        if (date != null) DateFormat('yyyy/MM/dd  HH:mm').format(date),
                        if (note.isNotEmpty) note,
                        'مدفوع: ${_money(entryPaid)}',
                      ].join(' • ')),
                      trailing: Text(
                        _money(amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _AccountTotal extends StatelessWidget {
  const _AccountTotal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
