class TransactionModel {
  final int? id;
  final int bookId;
  final String type;
  final double amount;
  final String name;
  final String category;
  final String notes;
  final String smsBody;
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
    this.smsBody = '',
    this.imagePath = '',
    required this.date,
    required this.currency,
    required this.paymentMode,
  });

  /// Returns the permanent SMS text without mixing it with user notes
  String get effectiveSmsText => smsBody;

  /// Returns true if the user has written a personal note on this entry
  bool get hasUserNote => notes.trim().isNotEmpty;

  TransactionModel copyWith({
    int? id,
    bool clearId = false,
    int? bookId,
    String? type,
    double? amount,
    String? name,
    String? category,
    String? notes,
    String? smsBody,
    String? imagePath,
    DateTime? date,
    String? currency,
    String? paymentMode,
  }) {
    return TransactionModel(
      id: clearId ? null : (id ?? this.id),
      bookId: bookId ?? this.bookId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      name: name ?? this.name,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      smsBody: smsBody ?? this.smsBody,
      imagePath: imagePath ?? this.imagePath,
      date: date ?? this.date,
      currency: currency ?? this.currency,
      paymentMode: paymentMode ?? this.paymentMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'type': type,
      'amount': amount,
      'name': name,
      'category': category,
      'notes': notes,
      'smsBody': smsBody,
      'imagePath': imagePath,
      'date': date.toIso8601String(),
      'currency': currency,
      'paymentMode': paymentMode,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    final String rawNotes = map['notes']?.toString() ?? '';
    final String rawSms = map['smsBody']?.toString() ?? '';
    // If an older entry had identical text in notes and smsBody from an SMS import, clear notes so it's not duplicated
    final String cleanNotes = (rawSms.isNotEmpty && rawNotes == rawSms) ? '' : rawNotes;

    return TransactionModel(
      id: (map['id'] as num?)?.toInt(),
      bookId: (map['bookId'] as num).toInt(),
      type: map['type']?.toString() ?? 'Expense',
      amount: (map['amount'] as num).toDouble(),
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      notes: cleanNotes,
      smsBody: rawSms,
      imagePath: map['imagePath']?.toString() ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      currency: map['currency']?.toString() ?? '₹',
      paymentMode: map['paymentMode']?.toString() ?? 'Cash',
    );
  }
}
