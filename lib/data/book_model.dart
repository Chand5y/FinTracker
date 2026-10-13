class BookModel {
  final int? id;
  final String name;
  final DateTime updatedAt;

  BookModel({this.id, required this.name, required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BookModel.fromMap(Map<String, dynamic> map) {
    return BookModel(
      id: map['id'],
      name: map['name'],
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}
