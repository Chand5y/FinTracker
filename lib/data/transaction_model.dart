class TransactionModel {
  final int? id;
  final int bookId;
  final String type;
  final double amount;
  final String name;
  final String category;
  final String notes;
  final String imagePath;
  final DateTime date;
  final String currency;
  final String paymentMode;

  TransactionModel({
    this.id,
    required this.bookId,
    required this.type,
    required this.amount,
    required this.name,
    required this.category,
    this.notes = '',
    this.imagePath = '',
    required this.date,
    required this.currency,
    required this.paymentMode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'type': type,
      'amount': amount,
      'name': name,
      'category': category,
      'notes': notes,
      'imagePath': imagePath,
      'date': date.toIso8601String(),
      'currency': currency,
      'paymentMode': paymentMode,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      bookId: map['bookId'],
      type: map['type'],
      amount: map['amount'],
      name: map['name'],
      category: map['category'] ?? '',
      notes: map['notes'] ?? '',
      imagePath: map['imagePath'] ?? '',
      date: DateTime.parse(map['date']),
      currency: map['currency'] ?? '₹',
      paymentMode: map['paymentMode'] ?? 'Cash',
    );
  }
}
