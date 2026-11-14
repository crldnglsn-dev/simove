class Expense {
  const Expense({
    this.id,
    required this.category,
    required this.amountCents,
    this.description,
    required this.createdAt,
  });

  final int? id;
  final String category;
  final int amountCents;
  final String? description;
  final DateTime createdAt;

  Expense copyWith({
    int? id,
    String? category,
    int? amountCents,
    String? description,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      category: category ?? this.category,
      amountCents: amountCents ?? this.amountCents,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'category': category,
        'amount_cents': amountCents,
        'description': description,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static Expense fromDbMap(Map<String, Object?> map) => Expense(
        id: map['id'] as int?,
        category: map['category'] as String? ?? 'Other',
        amountCents: (map['amount_cents'] as int?) ?? 0,
        description: map['description'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
      );
}

class ExpenseCategory {
  ExpenseCategory._();

  static const gasoline = 'Gasoline';
  static const maintenance = 'Maintenance';
  static const parking = 'Parking';
  static const food = 'Food';
  static const other = 'Other';

  static const all = [gasoline, maintenance, parking, food, other];
}
