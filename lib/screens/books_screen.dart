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

  void _showAddBookDialog(bool isSignature) {
    HapticFeedback.lightImpact();
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isSignature ? AppConstants.surfaceDark : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New Book', style: TextStyle(color: isSignature ? Colors.white : Colors.black)),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: isSignature ? Colors.white : Colors.black),
          decoration: InputDecoration(
            labelText: 'Enter book name',
            labelStyle: TextStyle(color: isSignature ? Colors.grey[400] : Colors.grey[700]),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? Colors.grey[700]! : Colors.grey[400]!)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? AppConstants.primaryColor : Colors.blue)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: isSignature ? Colors.grey[400] : Colors.blue))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isSignature ? AppConstants.primaryColor : Colors.blue, foregroundColor: isSignature ? Colors.black : Colors.white),
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

  void _showBookOptions(int bookId, String currentName, int isPinned, bool isSignature) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: isSignature ? AppConstants.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16.0), child: Text(currentName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSignature ? Colors.white : Colors.black))),
            Divider(height: 1, color: isSignature ? Colors.grey[800] : Colors.grey[300]),
            ListTile(
              leading: Icon(isPinned == 1 ? Icons.push_pin_outlined : Icons.push_pin, color: isSignature ? AppConstants.primaryColor : Colors.blue),
              title: Text(isPinned == 1 ? 'Unpin Book' : 'Pin to Top', style: TextStyle(color: isSignature ? Colors.white : Colors.black)),
              onTap: () async {
                HapticFeedback.lightImpact();
                await DatabaseHelper.instance.togglePinBook(bookId, isPinned == 0);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                _refreshBooks();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Book', style: TextStyle(color: Colors.red)),
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

  Widget _buildHeaderTypography(bool isSignature) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text('Fin', style: TextStyle(color: isSignature ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 26)),
            Text('Track', style: TextStyle(color: isSignature ? AppConstants.primaryColor : Colors.blue, fontWeight: FontWeight.bold, fontSize: 26)),
          ],
        ),
        Text(
          'YOUR PERSONAL FINANCE TRACKER', 
          style: TextStyle(
            color: isSignature ? Colors.grey[400] : Colors.grey[600], 
            fontSize: 8, 
            letterSpacing: 1.5, 
            fontWeight: FontWeight.w600
          )
        ),
      ],
    );
  }

  Widget _buildBooksView(bool isDark, bool isSignature) {
    return Scaffold(
      backgroundColor: isSignature ? AppConstants.backgroundDark : (isDark ? Colors.black : const Color(0xFFF2F2F7)),
      appBar: AppBar(
        title: _buildHeaderTypography(isSignature), 
        actions: [
          PopupMenuButton<BookSort>(
            icon: Icon(Icons.sort, color: isSignature ? Colors.white : (isDark ? Colors.white : Colors.black)),
            color: isSignature ? AppConstants.surfaceDark : null,
            onSelected: (sort) {
              HapticFeedback.selectionClick();
              setState(() { _currentSort = sort; _refreshBooks(); });
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: BookSort.updated, child: Text('Recently Updated', style: TextStyle(color: isSignature ? Colors.white : null))),
              PopupMenuItem(value: BookSort.created, child: Text('Recently Created', style: TextStyle(color: isSignature ? Colors.white : null))),
              PopupMenuItem(value: BookSort.aToZ, child: Text('A to Z', style: TextStyle(color: isSignature ? Colors.white : null))),
              PopupMenuItem(value: BookSort.zToA, child: Text('Z to A', style: TextStyle(color: isSignature ? Colors.white : null))),
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

                Color cardColor = isSignature 
                    ? (isPinned ? const Color(0xFF1E283D) : AppConstants.surfaceDark)
                    : (isDark 
                        ? (isPinned ? const Color(0xFF2C2C2C) : const Color(0xFF1E1E1E))
                        : (isPinned ? const Color(0xFFF0F4FF) : Colors.white));

                Color textColor = isSignature || isDark ? Colors.white : Colors.black;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Material(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    elevation: isSignature || isDark ? 0 : 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(bookId: book['id'], bookName: book['name']))).then((_) => _refreshBooks());
                      },
                      onLongPress: () => _showBookOptions(book['id'], book['name'], book['isPinned'], isSignature),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: (isSignature ? AppConstants.primaryColor : Colors.blue).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(isPinned ? Icons.push_pin : Icons.book, color: isSignature ? AppConstants.primaryColor : Colors.blue),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(book['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                                  const SizedBox(height: 4),
                                  Text('Created: ${_formatDateStrict(DateTime.parse(book['createdAt']))}', style: TextStyle(fontSize: 11, color: isSignature || isDark ? Colors.grey[500] : Colors.grey[600])),
                                  Text('Updated: ${_formatDateStrict(DateTime.parse(book['updatedAt']))}', style: TextStyle(fontSize: 11, color: isSignature || isDark ? Colors.grey[500] : Colors.grey[600])),
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
        backgroundColor: isSignature ? AppConstants.primaryColor : Colors.blue,
        onPressed: () => _showAddBookDialog(isSignature),
        icon: Icon(Icons.add, color: isSignature ? Colors.black : Colors.white),
        label: Text('New Book', style: TextStyle(color: isSignature ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCardGroup({required List<Widget> children, required bool isDark, required bool isSignature}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSignature ? AppConstants.surfaceDark : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsView(BuildContext context, bool isDark, bool isSignature) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: isSignature ? AppConstants.backgroundDark : (isDark ? Colors.black : const Color(0xFFF2F2F7)),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildCardGroup(
            isSignature: isSignature,
            isDark: isDark,
            children: [
              ListTile(
                leading: Icon(Icons.palette_outlined, color: isSignature ? AppConstants.primaryColor : Colors.blue),
                title: Text('Signature Theme', style: TextStyle(color: isSignature || isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                subtitle: Text('Toggle standard Material You', style: TextStyle(color: isSignature || isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                trailing: Switch(
                  value: isSignature,
                  activeColor: isSignature ? AppConstants.primaryColor : Colors.blue,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    themeProvider.toggleTheme();
                  },
                ),
              ),
            ],
          ),
          _buildCardGroup(
            isSignature: isSignature,
            isDark: isDark,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
                title: Text('Google Drive Backup', style: TextStyle(color: isSignature || isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drive API Integration Next')));
                },
              ),
              Divider(height: 1, indent: 50, color: isSignature || isDark ? Colors.grey[800] : Colors.grey[200]),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
                title: Text('Restore from Drive', style: TextStyle(color: isSignature || isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500)),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSignature = themeProvider.themeMode == AppThemeMode.glassmorphic;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: _selectedIndex == 0 ? _buildBooksView(isDark, isSignature) : _buildSettingsView(context, isDark, isSignature),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: isSignature ? AppConstants.surfaceDark : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        selectedItemColor: isSignature ? AppConstants.primaryColor : Colors.blue,
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
