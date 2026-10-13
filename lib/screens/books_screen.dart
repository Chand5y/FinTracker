import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'dashboard_screen.dart';

class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  int _selectedIndex = 1; // 1 = Cashbooks (Default)
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

  // Enforces MM/DD/YYYY
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

  // --- 1. THE SETTINGS UI ---
  Widget _buildSettingsView(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.themeMode == AppThemeMode.glassmorphic;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('App Preferences', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.palette_outlined, color: Color(0xFF4C44D4)),
            title: const Text('Apple Glassmorphic Theme'),
            subtitle: const Text('Toggle between Glass and Cashbook styles'),
            trailing: Switch(
              value: isGlass,
              activeColor: const Color(0xFF4C44D4),
              onChanged: (val) => themeProvider.toggleTheme(),
            ),
          ),
          const Divider(),
          const SizedBox(height: 16),
          const Text('Backup & Restore', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
            title: const Text('Google Drive Backup'),
            subtitle: const Text('Requires API setup'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Google Drive API configuration is required next.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
            title: const Text('Restore from Drive'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Connect Google Drive to restore database.')),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- 2. THE CASHBOOKS UI ---
  Widget _buildBooksView() {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined, color: Color(0xFF4C44D4)), 
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts integration coming soon'))),
          ),
          const SizedBox(width: 8),
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
                  children: [
                    IconButton(icon: const Icon(Icons.filter_list, color: Color(0xFF4C44D4)), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.search, color: Color(0xFF4C44D4)), onPressed: () {}),
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
                      
                      // CRITICAL FIX: Explicitly cast to double to prevent the integer rendering crash
                      final double totalIn = (book['totalIn'] ?? 0).toDouble();
                      final double totalOut = (book['totalOut'] ?? 0).toDouble();
                      final double netBalance = totalIn - totalOut;
                      final bool isNegative = netBalance < 0;

                      return ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DashboardScreen(bookId: book['id'], bookName: book['name']),
                            ),
                          ).then((_) => _refreshBooks());
                        },
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE8E8FA),
                          child: Icon(Icons.book, color: Color(0xFF4C44D4)),
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

  // --- 3. MAIN NAVIGATION SHELL ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 1 
          ? _buildBooksView() 
          : _selectedIndex == 3 
              ? _buildSettingsView(context)
              : const Center(child: Text('Under Construction')),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF4C44D4),
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Payments'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Cashbooks'),
          BottomNavigationBarItem(icon: Icon(Icons.credit_card), label: 'Passbook'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
