import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../core/constants.dart';
import 'dashboard_screen.dart'; // We will update this in the next step

class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  List<Map<String, dynamic>> _booksData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshBooks();
  }

  Future<void> _refreshBooks() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getBooksWithBalances();
    setState(() {
      _booksData = data;
      _isLoading = false;
    });
  }

  String _formatDateStrict(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$month/$day/${date.year}";
  }

  void _showAddBookDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add new book'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Enter book name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C44D4), foregroundColor: Colors.white),
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await DatabaseHelper.instance.insertBook(BookModel(
                  name: nameController.text.trim(),
                  updatedAt: DateTime.now(),
                ));
                if (mounted) Navigator.pop(context);
                _refreshBooks();
              }
            },
            child: const Text('Create book'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fintracker Business', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Tap to switch business', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        actions: const [
          Icon(Icons.person_add_alt_1_outlined, color: Color(0xFF4C44D4)),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Your Books', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Row(
                  children: const [
                    Icon(Icons.filter_list, color: Color(0xFF4C44D4)),
                    SizedBox(width: 16),
                    Icon(Icons.search, color: Color(0xFF4C44D4)),
                  ],
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _booksData.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final book = _booksData[index];
                      final double netBalance = book['totalIn'] - book['totalOut'];
                      final isNegative = netBalance < 0;

                      return ListTile(
                        onTap: () {
                          // Navigate to the Book Details screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DashboardScreen(bookId: book['id'], bookName: book['name']),
                            ),
                          ).then((_) => _refreshBooks());
                        },
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE8E8FA),
                          child: const Icon(Icons.book, color: Color(0xFF4C44D4)),
                        ),
                        title: Text(book['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Updated on ${_formatDateStrict(DateTime.parse(book['updatedAt']))}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${netBalance.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isNegative ? const Color(0xFFD33636) : const Color(0xFF328D4D),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.more_vert, color: Colors.grey),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4C44D4),
        onPressed: _showAddBookDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add new book', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
