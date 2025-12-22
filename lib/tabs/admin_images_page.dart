// lib/pages/admin_images_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/user_model.dart';
import '../providers/user_provider.dart';
import '../pages/customer_sum.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(AdminUsersPage);

/// Admin page for viewing all users.
/// Features:
/// - Lists all users with search functionality
/// - Search by name, surname, or email
/// Data Flow:
/// 1. Fetches users via UserProvider.fetchUsers()
/// 2. Displays searchable list
/// 3. On tap -> CustomerSummaryPage
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  // === State Variables ===
  
  /// Future for fetching all users from Firestore
  late Future<List<UserModel>> _usersFuture;
  
  /// Complete list of all users (unfiltered)
  List<UserModel> _allUsers = [];
  
  /// Filtered list based on search query
  List<UserModel> _filteredUsers = [];
  
  /// Current search query (lowercase)
  String _searchQuery = '';
  
  /// Controller for search text field
  final TextEditingController _searchController = TextEditingController();
  
  /// Loading state indicator
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    logger.info('AdminUsersPage page initialized');
    _loadUsers();
  }

  /// Loads all users from Firestore using UserProvider.
  /// 
  /// Sets up the users list and handles errors gracefully.
  /// Updates loading state and filtered list upon completion.
  void _loadUsers() {
    logger.debug('Starting user load operation');
    
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _usersFuture = userProvider.fetchUsers();
    
    _usersFuture.then((users) {
      logger.info('Successfully loaded {} users', [users.length]);
      
      if (!mounted) {
        logger.debug('Widget unmounted, skipping state update');
        return;
      }
      
      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
      
      logger.debug('User list state updated. allUsers={} filteredUsers={}', 
        [_allUsers.length, _filteredUsers.length]);
        
    }).catchError((error, stackTrace) {
      logger.err('Error loading users: {}', [error]);
      logger.debug('Stack trace: {}', [stackTrace]);
      
      if (!mounted) {
        logger.debug('Widget unmounted, skipping error state update');
        return;
      }
      
      setState(() {
        _isLoading = false;
      });
    });
  }

  /// Filters the user list based on search query.
  /// 
  /// Searches across name, surname, and email fields (case-insensitive).
  /// Updates the filtered list and triggers UI rebuild.
  /// 
  /// @param query The search text entered by user
  void _onSearchChanged(String query) {
    logger.debug('Search query changed: "{}"', [query]);
    
    setState(() {
      _searchQuery = query.toLowerCase();
      
      if (_searchQuery.isEmpty) {
        // No filter: show all users
        _filteredUsers = _allUsers;
        logger.debug('Search cleared. Showing all {} users', [_allUsers.length]);
      } else {
        // Filter users by matching query in name, surname, or email
        _filteredUsers = _allUsers.where((user) {
          final nameMatch = user.name.toLowerCase().contains(_searchQuery);
          final emailMatch = user.email.toLowerCase().contains(_searchQuery);
          final surnameMatch = user.surname.toLowerCase().contains(_searchQuery) ?? false;

          return nameMatch || emailMatch || surnameMatch;
        }).toList();
        
        logger.debug('Search applied. Found {} matches out of {} total users', 
          [_filteredUsers.length, _allUsers.length]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    logger.debug('Building AdminUsers page. loading={} filteredCount={}',
      [_isLoading, _filteredUsers.length]);

    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Kullanıcılar',
        actions: [],
      ),
      body: Column(
        children: [
          // Search bar with clear functionality
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kullanıcı Ara (Ad, Soyad, Email)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Aramayı temizle',
                        onPressed: () {
                          logger.debug('Search cleared via button');
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue.shade300),
                ),
                filled: true,
                fillColor: Colors.blue.shade50,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 16.0,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // User list with loading, empty, and data states
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _filteredUsers.isEmpty
                    ? _buildEmptyState()
                    : _buildUserList(),
          ),
        ],
      ),
    );
  }

  /// Builds the empty state UI when no users match the search.
  Widget _buildEmptyState() {
    final bool hasSearchQuery = _searchQuery.isNotEmpty;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearchQuery ? Icons.search_off : Icons.person_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              hasSearchQuery 
                  ? 'Kullanıcı bulunamadı' 
                  : 'Henüz kullanıcı yok',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearchQuery
                  ? 'Farklı anahtar kelimeler deneyin'
                  : 'Sistem henüz kullanıcı içermiyor',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the scrollable list of users.
  /// 
  /// Each list item shows:
  /// - User avatar (first letter of name)
  /// - Full name (name + surname)
  /// - Email address
  /// - Navigation arrow
  Widget _buildUserList() {
    logger.debug('Building user list with {} items', [_filteredUsers.length]);
    
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final fullName = '${user.name} ${user.surname ?? ""}'.trim();
        final initial = user.name.isNotEmpty 
            ? user.name.substring(0, 1).toUpperCase() 
            : '?';
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
            title: Text(
              fullName,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              logger.info('User tapped. userId={} name="{}"', [user.userId, fullName]);
              
              // Navigate to user summary page
              // The CustomerSummaryPage contains tabs including ImagesTab
              // ImagesTab uses MealManager to fetch meal images
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CustomerSummaryPage(user: user),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    logger.info('AdminUsers page disposed');
    _searchController.dispose();
    super.dispose();
  }
}
