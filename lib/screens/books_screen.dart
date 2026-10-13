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
  int _selectedIndex = 0; // 0 = Books, 1 = Settings
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
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add new book'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Enter book name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C44D4), 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isNotEmpty) {
                await DatabaseHelper.instance.insertBook(BookModel(
                  name: text,
                  updatedAt: DateTime.now(),
                ));
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                _refreshBooks(); 
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // Handle Long Press on a Book
  void _showBookOptionsBottomSheet(int bookId, String currentName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(currentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit Name'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditBookDialog(bookId, currentName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Book'),
                subtitle: const Text('This will delete all transactions inside it.'),
                onTap: () async {
                  await DatabaseHelper.instance.deleteBook(bookId);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _refreshBooks();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }

  void _showEditBookDialog(int bookId, String currentName) {
    final TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Book'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C44D4), foregroundColor: Colors.white),
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isNotEmpty && text != currentName) {
                await DatabaseHelper.instance.updateBookName(bookId, text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refreshBooks(); 
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGroup({required List<Widget> children, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsView(BuildContext context, bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.themeMode == AppThemeMode.glassmorphic;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildCardGroup(
            isDark: isDark,
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: Color(0xFF4C44D4)),
                title: Text('Modern Theme', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                subtitle: Text('Toggle visual style', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                trailing: Switch(
                  value: isGlass,
                  activeColor: const Color(0xFF4C44D4),
                  onChanged: (val) => themeProvider.toggleTheme(),
                ),
              ),
            ],
          ),
          _buildCardGroup(
            isDark: isDark,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
                title: Text('Google Drive Backup', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {},
              ),
              Divider(height: 1, indent: 50, color: isDark ? Colors.grey[800] : Colors.grey[200]),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
                title: Text('Restore from Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBooksView(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(AppConstants.appName),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 8, bottom: 8),
            child: Text('Your Books', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _booksData.length,
                    itemBuilder: (context, index) {
                      final book = _booksData[index];
                      final double totalIn = (book['totalIn'] ?? 0).toDouble();
                      final double totalOut = (book['totalOut'] ?? 0).toDouble();
                      final double netBalance = totalIn - totalOut;
                      final bool isNegative = netBalance < 0;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          // Tapping opens the ledger
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DashboardScreen(bookId: book['id'], bookName: book['name']),
                              ),
                            ).then((_) => _refreshBooks());
                          },
                          // Long Press opens edit/delete menu
                          onLongPress: () {
                            _showBookOptionsBottomSheet(book['id'], book['name']);
                          },
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4C44D4).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.book, color: Color(0xFF4C44D4)),
                          ),
                          title: Text(book['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text('Updated ${_formatDateStrict(DateTime.parse(book['updatedAt']))}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[500])),
                          trailing: Text(
                            '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${netBalance.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isNegative ? const Color(0xFFD33636) : const Color(0xFF328D4D),
                            ),
                          ),
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
        label: const Text('New Book', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: _selectedIndex == 0 
          ? _buildBooksView(isDark) 
          : _buildSettingsView(context, isDark),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        selectedItemColor: const Color(0xFF4C44D4),
        unselectedItemColor: Colors.grey,
        elevation: 8,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Books'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
