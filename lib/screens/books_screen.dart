import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'dashboard_screen.dart';

enum BookSort { updated, created, aToZ, zToA }

class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  int _selectedIndex = 0; 
  List<Map<String, dynamic>> _booksData = [];
  bool _isLoading = true;
  BookSort _currentSort = BookSort.updated;

  @override
  void initState() {
    super.initState();
    _refreshBooks();
  }

  Future<void> _refreshBooks() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getBooksWithBalances();
    
    data.sort((a, b) {
      if (a['isPinned'] == 1 && b['isPinned'] == 0) return -1;
      if (a['isPinned'] == 0 && b['isPinned'] == 1) return 1;
      
      switch (_currentSort) {
        case BookSort.updated:
          return DateTime.parse(b['updatedAt']).compareTo(DateTime.parse(a['updatedAt']));
        case BookSort.created:
          return DateTime.parse(b['createdAt']).compareTo(DateTime.parse(a['createdAt']));
        case BookSort.aToZ:
          return a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase());
        case BookSort.zToA:
          return b['name'].toString().toLowerCase().compareTo(a['name'].toString().toLowerCase());
      }
    });

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
    HapticFeedback.lightImpact();
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Book'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'Enter book name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isNotEmpty) {
                int result = await DatabaseHelper.instance.insertBook(BookModel(name: text, createdAt: DateTime.now(), updatedAt: DateTime.now()));
                if (result == -1) {
                  HapticFeedback.heavyImpact();
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('A book with this name already exists.'), backgroundColor: Colors.red));
                  }
                } else {
                  HapticFeedback.mediumImpact();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  _refreshBooks();
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showBookOptions(int bookId, String currentName, int isPinned) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16.0), child: Text(currentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            ListTile(
              leading: Icon(isPinned == 1 ? Icons.push_pin_outlined : Icons.push_pin, color: AppConstants.primaryColor),
              title: Text(isPinned == 1 ? 'Unpin Book' : 'Pin to Top'),
              onTap: () async {
                HapticFeedback.lightImpact();
                await DatabaseHelper.instance.togglePinBook(bookId, isPinned == 0);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                _refreshBooks();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Rename Book'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditBookDialog(bookId, currentName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Book'),
              onTap: () async {
                HapticFeedback.heavyImpact();
                await DatabaseHelper.instance.deleteBook(bookId);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                _refreshBooks();
              },
            ),
          ],
        ),
      )
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
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
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

  Widget _buildBooksView(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Image.asset('logo.png', height: 28), 
        actions: [
          PopupMenuButton<BookSort>(
            icon: Icon(Icons.sort, color: isDark ? Colors.white : Colors.black),
            onSelected: (sort) {
              HapticFeedback.selectionClick();
              setState(() { _currentSort = sort; _refreshBooks(); });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: BookSort.updated, child: Text('Recently Updated')),
              const PopupMenuItem(value: BookSort.created, child: Text('Recently Created')),
              const PopupMenuItem(value: BookSort.aToZ, child: Text('A to Z')),
              const PopupMenuItem(value: BookSort.zToA, child: Text('Z to A')),
            ],
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 8),
              itemCount: _booksData.length,
              itemBuilder: (context, index) {
                final book = _booksData[index];
                final bool isPinned = book['isPinned'] == 1;
                final double netBalance = (book['totalIn'] ?? 0).toDouble() - (book['totalOut'] ?? 0).toDouble();
                final bool isNegative = netBalance < 0;

                Color cardColor = isDark 
                    ? (isPinned ? const Color(0xFF1A1A2E) : AppConstants.surfaceDark)
                    : (isPinned ? const Color(0xFFF0F4FF) : Colors.white);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Material(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    elevation: isDark ? 0 : 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(bookId: book['id'], bookName: book['name']))).then((_) => _refreshBooks());
                      },
                      onLongPress: () => _showBookOptions(book['id'], book['name'], book['isPinned']),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: AppConstants.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(isPinned ? Icons.push_pin : Icons.book, color: AppConstants.primaryColor),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(book['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                                  const SizedBox(height: 4),
                                  Text('Created: ${_formatDateStrict(DateTime.parse(book['createdAt']))}', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                                  Text('Updated: ${_formatDateStrict(DateTime.parse(book['updatedAt']))}', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[600])),
                                ],
                              ),
                            ),
                            Text(
                              '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${netBalance.abs().toStringAsFixed(0)}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isNegative ? const Color(0xFFD33636) : const Color(0xFF328D4D)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppConstants.primaryColor,
        onPressed: _showAddBookDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Book', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCardGroup({required List<Widget> children, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsView(BuildContext context, bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isModern = themeProvider.themeMode == AppThemeMode.glassmorphic;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : const Color(0xFFF2F2F7),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildCardGroup(
            isDark: isDark,
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: AppConstants.primaryColor),
                title: Text('Signature Theme', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                subtitle: Text('Toggle standard Material You', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                trailing: Switch(
                  value: isModern,
                  activeColor: AppConstants.primaryColor,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    themeProvider.toggleTheme();
                  },
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
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drive API Integration Next')));
                },
              ),
              Divider(height: 1, indent: 50, color: isDark ? Colors.grey[800] : Colors.grey[200]),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
                title: Text('Restore from Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drive API Integration Next')));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: _selectedIndex == 0 ? _buildBooksView(isDark) : _buildSettingsView(context, isDark),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: isDark ? AppConstants.surfaceDark : Colors.white,
        selectedItemColor: AppConstants.primaryColor,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Books'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
