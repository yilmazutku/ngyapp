// lib/pages/admin_images_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/chat_manager_new.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../pages/customer_sum.dart';
import '../utils/dialog_utils.dart';
import '../utils/search_text.dart';
import '../widgets/app_bar_with_back.dart';

/// Admin page for viewing all users.
/// Features:
/// - Lists all users with search functionality
/// - Search by name, surname, or email
/// - Alfabetik sıralı liste (Danışanlar Özet sayfasındaki sıralamayla aynı)
/// - Yürürlükteki paketi olmayan danışanlar soluk gösterilir ve
///   e-postalarının yanında "PAKETİ YOK" rozeti taşır
/// Data Flow:
/// 1. Fetches users via UserProvider.fetchUsers()
/// 2. Displays searchable list
/// 3. Paket bilgisi liste çizildikten sonra ayrıca yüklenir
///    ([SubProvider.fetchUsersWithLivePackage])
/// 4. On tap -> CustomerSummaryPage
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  /// Paket durumu yalnızca danışanlar için anlamlıdır; yöneticilere rozet
  /// konmaz.
  static const String _customerRole = 'customer';

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

  /// Yürürlükteki (aktif ya da dondurulmuş) paketi olan danışanların
  /// kimlikleri. Liste çizildikten sonra doldurulur.
  Set<String> _usersWithPackage = const {};

  /// Paket bilgisi hâlâ yükleniyor mu. Yüklenirken hiçbir satıra "PAKETİ YOK"
  /// yazılmaz: bilgi gelmeden danışan paketsiz sanılmasın.
  bool _packagesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  /// Loads all users from Firestore using UserProvider.
  /// 
  /// Sets up the users list and handles errors gracefully.
  /// Updates loading state and filtered list upon completion.
  ///
  /// Liste alfabetik sıralı gelir (bkz. [_sortByDisplayName]); paket bilgisi
  /// liste çizildikten sonra ayrıca yüklenir ([_loadPackageOwners]) ki sayfa
  /// paket sorguları bitene kadar boş beklemesin.
  void _loadUsers() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _usersFuture = userProvider.fetchUsers();
    
    _usersFuture.then((users) {
      if (!mounted) {
        return;
      }
      
      // Hide users with incomplete profile data (empty name, surname, or email).
      // These are typically corrupt or partially-created records that should not
      // appear in the admin user management list. Admin accounts are always
      // kept so an admin can find (and manage) their own record here.
      final validUsers = users.where((u) {
        if (ChatManager.isAdminUid(u.userId)) return true;
        return u.name.trim().isNotEmpty &&
            u.surname.trim().isNotEmpty &&
            u.email.trim().isNotEmpty;
      }).toList()
        ..sort(_sortByDisplayName);

      setState(() {
        _allUsers = validUsers;
        _filteredUsers = validUsers;
        _isLoading = false;
      });

      _loadPackageOwners(validUsers);
    }).catchError((error, stackTrace) {
      if (!mounted) {
        return;
      }
      
      setState(() {
        _isLoading = false;
        _packagesLoading = false;
      });
    });
  }

  /// Listede gösterilen ad: ad-soyad boşsa (profili doldurulmamış yönetici
  /// kayıtları) e-posta kullanılır. Sıralama da bu ada göre yapılır.
  String _displayNameOf(UserModel user) =>
      user.fullName.isEmpty ? user.email : user.fullName;

  /// Alfabetik sıralama; Danışanlar Özet sayfasıyla aynı karşılaştırıcıyı
  /// kullanır ki iki sayfada da Türkçe harfler doğru yere otursun.
  int _sortByDisplayName(UserModel a, UserModel b) =>
      compareSearchText(_displayNameOf(a), _displayNameOf(b));

  /// Hangi danışanın yürürlükteki paketi olduğunu yükler; kalanlar listede
  /// soluk gösterilip "PAKETİ YOK" rozeti alır.
  ///
  /// Paket bilgisi sayfanın asıl işi değil: okunamazsa liste yine çalışır,
  /// yalnızca rozet gösterilmez.
  Future<void> _loadPackageOwners(List<UserModel> users) async {
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final List<String> customerIds = users
        .where(_isCustomer)
        .map((user) => user.userId)
        .toList();

    if (customerIds.isEmpty) {
      setState(() => _packagesLoading = false);
      return;
    }

    try {
      final Set<String> owners =
          await subProvider.fetchUsersWithLivePackage(customerIds);
      if (!mounted) return;
      setState(() {
        _usersWithPackage = owners;
        _packagesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _packagesLoading = false);
    }
  }

  /// Paket durumu aranan kayıt mı: yönetici olmayan, rolü `customer` olan
  /// kullanıcılar.
  bool _isCustomer(UserModel user) =>
      user.role == _customerRole && !ChatManager.isAdminUid(user.userId);

  /// [user] paketsiz mi: paket bilgisi gelmiş bir danışan, yürürlükteki paketi
  /// olanlar arasında değilse. Bilgi yüklenirken hiç kimse paketsiz sayılmaz.
  bool _hasNoPackage(UserModel user) =>
      !_packagesLoading &&
      _isCustomer(user) &&
      !_usersWithPackage.contains(user.userId);

  /// Filters the user list based on search query.
  /// 
  /// Searches across name, surname, and email fields (case-insensitive).
  /// Updates the filtered list and triggers UI rebuild.
  /// 
  /// @param query The search text entered by user
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      
      if (_searchQuery.isEmpty) {
        // No filter: show all users
        _filteredUsers = _allUsers;
      } else {
        // Filter users by matching query in name, surname, or email
        _filteredUsers = _allUsers.where((user) {
          final nameMatch = user.name.toLowerCase().contains(_searchQuery);
          final emailMatch = user.email.toLowerCase().contains(_searchQuery);
          final surnameMatch = user.surname.toLowerCase().contains(_searchQuery);

          return nameMatch || emailMatch || surnameMatch;
        }).toList();
      }
    });
  }

  /// Confirms and permanently deletes [user] together with everything that
  /// belongs to them (all Firestore data, every Storage file and their Firebase
  /// Authentication account) via [UserProvider.deleteUserAccount].
  ///
  /// Shows a strong, itemized confirmation first, a blocking loading dialog
  /// while the server-side deletion runs, and finally an info/error dialog. On
  /// success the user is removed from the in-memory lists so the UI updates
  /// without a full reload.
  Future<void> _confirmAndDeleteUser(UserModel user) async {
    final fullName = '${user.name} ${user.surname}'.trim();

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Kullanıcıyı Sil',
      message: '"$fullName" kullanıcısı ve bu kullanıcıya ait TÜM veriler '
          'kalıcı olarak silinecek:\n\n'
          '• Randevular\n'
          '• Ödemeler ve dekontlar\n'
          '• Paketler\n'
          '• Ölçümler ve Tanita PDF\'leri\n'
          '• Dokümanlar\n'
          '• Diyet listeleri\n'
          '• Öğün fotoğrafları ve günlük veriler\n'
          '• Sohbet ve yüklenen tüm fotoğraflar\n'
          '• Giriş (hesap) bilgileri\n\n'
          'Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
      confirmText: 'Evet, sil',
      cancelText: 'Vazgeç',
    );

    if (!confirmed) return;
    if (!mounted) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(context, message: 'Kullanıcı siliniyor...');
        loadingOpen = true;
      }

      await userProvider.deleteUserAccount(userId: user.userId);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      setState(() {
        _allUsers.removeWhere((u) => u.userId == user.userId);
        _filteredUsers.removeWhere((u) => u.userId == user.userId);
      });

      await DialogUtils.openInfo(
        context,
        title: 'Silindi',
        message: '"$fullName" kullanıcısı ve tüm verileri kalıcı olarak silindi.',
      );
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Kullanıcı silinirken bir hata oluştu.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
  ///
  /// Yürürlükteki paketi olmayan danışanın kartı soluk çizilir (soluk zemin,
  /// gri avatar ve gri yazı); e-postasının yanındaki kırmızı "PAKETİ YOK"
  /// rozeti kartın tek canlı renkli ögesi olduğu için hemen göze çarpar.
  Widget _buildUserList() {
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final fullName = '${user.name} ${user.surname}'.trim();
        final initial = user.name.isNotEmpty 
            ? user.name.substring(0, 1).toUpperCase() 
            : '?';
        // Admin accounts cannot be deleted (mirrors the server-side guard), so
        // the delete action is only offered for regular users.
        final isAdmin = ChatManager.isAdminUid(user.userId);
        final hasNoPackage = _hasNoPackage(user);
        final Color? fadedTextColor =
            hasNoPackage ? Colors.grey.shade600 : null;
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          elevation: hasNoPackage ? 1 : 2,
          color: hasNoPackage ? Colors.grey.shade200 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  hasNoPackage ? Colors.grey.shade300 : Colors.blue.shade100,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      hasNoPackage ? Colors.grey.shade600 : Colors.blue.shade700,
                ),
              ),
            ),
            title: Text(
              fullName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: fadedTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                // Rozet dar ekranda da tam görünsün diye kısalan taraf
                // e-postadır.
                Flexible(
                  child: Text(
                    user.email,
                    style: TextStyle(color: fadedTextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasNoPackage) ...[
                  const SizedBox(width: 8),
                  const _NoPackageBadge(),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isAdmin)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Kullanıcı işlemleri',
                    onSelected: (value) {
                      if (value == 'delete') {
                        _confirmAndDeleteUser(user);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline,
                              color: Colors.red),
                          title: Text(
                            'Kullanıcıyı Sil',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              // Navigate to user summary page.
              // The CustomerSummaryPage contains tabs including the Detay tab,
              // which can delete the user and pops back with the deleted userId
              // so we can drop the row here without a full reload.
              final deletedUserId = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(
                  builder: (context) => CustomerSummaryPage(user: user),
                ),
              );

              if (!mounted) return;
              if (deletedUserId is String && deletedUserId.isNotEmpty) {
                setState(() {
                  _allUsers.removeWhere((u) => u.userId == deletedUserId);
                  _filteredUsers.removeWhere((u) => u.userId == deletedUserId);
                });
              }
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

/// Paketi olmayan danışanı belli eden rozet: e-postanın yanında, kırmızı
/// zeminde büyük ve kalın harflerle.
class _NoPackageBadge extends StatelessWidget {
  static const String _label = 'PAKETİ YOK';

  const _NoPackageBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: const Text(
        _label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14.0,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
