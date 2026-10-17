class BookModel {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final String bookType; // 'standard' or 'lending'

  BookModel({
    this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.bookType = 'standard',
  });

  bool get isLending => bookType == 'lending';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned ? 1 : 0,
      'bookType': bookType,
    };
  }

  factory BookModel.fromMap(Map<String, dynamic> map) {
    return BookModel(
      id: map['id'],
      name: map['name']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      isPinned: map['isPinned'] == 1,
      bookType: map['bookType']?.toString() ?? 'standard',
    );
  }
}
