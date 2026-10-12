class TransactionModel {
  final int? id;
  final String type; // 'Expense', 'Income', 'Given', 'Received'
  final double amount;
  final String? partyName;
  final String category;
  final String? notes;
  final String? imagePath; // Path to the local screenshot/receipt
  final DateTime date;
  final String currency; // Allows different currencies per transaction

  TransactionModel({
    this.id,
    required this.type,
    required this.amount,
    this.partyName,
    required this.category,
    this.notes,
    this.imagePath,
    required this.date,
    required this.currency,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'partyName': partyName,
      'category': category,
      'notes': notes,
      'imagePath': imagePath,
      'date': date.toIso8601String(),
      'currency': currency,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      type: map['type'],
      amount: map['amount'],
      partyName: map['partyName'],
      category: map['category'],
      notes: map['notes'],
      imagePath: map['imagePath'],
      date: DateTime.parse(map['date']),
      currency: map['currency'],
    );
  }
}
