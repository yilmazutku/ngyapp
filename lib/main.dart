// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:untitled/pages/login_page.dart';
// import 'package:untitled/providers/appointment_manager.dart';
// import 'package:untitled/providers/diet_provider.dart';
// import 'package:untitled/providers/image_manager.dart';
// import 'package:untitled/providers/login_manager.dart';
// import 'package:untitled/providers/meal_state_and_upload_manager.dart';
// import 'package:untitled/providers/user_provider.dart';
// import 'package:untitled/providers/payment_provider.dart';
// import 'package:untitled/providers/test_provider.dart';
// import 'package:untitled/providers/meas_provider.dart';
// import 'firebase_options.dart';
// import 'models/logger.dart';
//
// final logger = Logger('MyApp');

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/pages/admin_chat_page.dart';
import 'package:ngy_app/pages/chat_page_new.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';

import 'firebase_options.dart';
import 'models/logger.dart';
import 'pages/admin_appointments_page.dart';
import 'platform/platform_config.dart';
import 'platform/platform_config_factory.dart';
import 'pages/admin_create_user_page.dart';
import 'pages/admin_payments_page.dart';
import 'pages/admin_timeslots_page.dart';
import 'pages/appointments_page.dart';
import 'pages/kvkk_consent_page.dart';
import 'pages/login_page.dart';
import 'pages/meal_upload_page.dart';
import 'pages/meas_page.dart';
import 'pages/profile_page.dart';
import 'pages/user_payments_page.dart';
import 'providers/appointment_manager.dart';
import 'providers/daily_data_provider.dart';
import 'providers/diet_provider.dart';
import 'providers/login_manager.dart';
import 'providers/meal_state_and_upload_manager.dart';
import 'providers/meas_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/sub_provider.dart';
import 'providers/test_provider.dart';
import 'providers/user_provider.dart';
import 'services/fcm_service.dart';
import 'services/meal_reminder_service.dart';
import 'services/notification_service.dart';
import 'tabs/admin_images_page.dart';
import 'news/news_provider.dart';
import 'news/news_list_page.dart';
import 'news/admin_news_page.dart';
import 'pages/notification_test_page.dart';

/// Global platform configuration instance
late final PlatformConfig platformConfig;

/// Global theme provider instance for early initialization
//late final ThemeProvider themeProvider;

// === LOGGING FLAGS ===
// DEBUG: Set to true to enable debug-level messages (log.debug calls)
// Set to false to suppress debug-level messages in console and file
const bool DEBUG = false;

// LOGTOFILE: Set to true to save all log messages to file (desktop only)
// Set to false to disable file logging entirely
const bool LOGTOFILE = false;

// AUTO_LOGIN: Set to true to auto-login with signInAutomatically() credentials
// Set to false to use the login form with user-provided email/password
const bool AUTO_LOGIN = false;

final logger = Logger('MyApp');

/// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the logging system
  await Logger.initialize(debugEnabled: DEBUG, logToFileEnabled: LOGTOFILE);
  logger.info('Logging system initialized');
  logger.info('Application started');
  // Initialize date formatting for Turkish locale
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR';
  logger.info('Turkish date formatting initialized');

  // Auto-login for development/testing when AUTO_LOGIN is true
  if (AUTO_LOGIN) {
    await signInAutomatically();
  }

  // Initialize theme provider and load saved color preference
  // themeProvider = ThemeProvider();
  // await themeProvider.initialize();
  // logger.info('Theme provider initialized with color: ${themeProvider.primaryColorHex}');

  // Initialize platform-specific configuration (notifications, etc.)
  // This uses the Strategy Pattern to handle platform differences
  platformConfig = await PlatformConfigFactory.initializePlatform(
    navigatorKey: navKey,
  );
  logger.info('Platform initialized: ${platformConfig.platformName}');

  runApp(const MyApp());

  // Try opening pending notification after first frame (only on supported platforms)
  if (FcmService.isSupported) {
    FcmService().tryOpenPendingMessageAfterFrame();
  }

  // Schedule meal reminders if user is logged in
  _scheduleMealRemindersForCurrentUser();
}

/// Schedule meal reminders for the current user if logged in
Future<void> _scheduleMealRemindersForCurrentUser() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && MealReminderService().isSupported) {
      await MealReminderService().initialize();
      await MealReminderService().scheduleMealReminders(user.uid);
      logger.info('Meal reminders scheduled for user ${user.uid}');
    }
  } catch (e) {
    logger.err('Error scheduling meal reminders at startup: $e');
  }
}

// Keep this for testing purposes; remove or modify for production
Future<void> signInAutomatically() async {
  const email = 'utkuyy97@gmail.com';//'denemehesap@gmail.com';
  const password = '612009';
  try {
    UserCredential userCredential =
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    logger.info('Signed in with email: ${userCredential.user?.email}');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      logger.warn('No user found for that email.');
    } else if (e.code == 'wrong-password') {
      logger.warn('Wrong password provided for that user.');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatManager(
            db: FirebaseFirestore.instance,
            auth: FirebaseAuth.instance,
            storage: FirebaseStorage.instance,
          ),
        ),
        ChangeNotifierProvider(create: (_) => DailyDataProvider()),
        ChangeNotifierProvider(create: (_) => MealManager()),
        ChangeNotifierProvider(create: (_) => SubProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AppointmentManager(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => TimeslotManager()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (ctx) => PaymentProvider(subProvider: ctx.read<SubProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => MeasProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => DietProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: AppLifecycleManager(
        child: MaterialApp(
          navigatorKey: navKey, // <-- IMPORTANT for notification tap navigation
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.purple,
            primaryColor: const Color(0xFFA16AEC),
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFA16AEC),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 2,
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black87),
            ),
            cardColor: Colors.white,
            iconTheme: const IconThemeData(color: Color(0xFFA16AEC)),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA16AEC),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          supportedLocales: const [
            Locale('tr', 'TR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

/// Wrapper widget that handles authentication state and navigates accordingly.
/// - Shows a loading screen while checking auth state
/// - If user is logged in, navigates to HomePage (after KVKK check)
/// - If user is not logged in, shows LoginPage
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  /// Future for checking KVKK consent status
  Future<bool>? _kvkkCheckFuture;
  
  /// Track the current user ID to reset KVKK check when user changes
  String? _currentUserId;
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        // User is not logged in - show login page
        if (!snapshot.hasData || snapshot.data == null) {
          // Reset cached values when user logs out
          _kvkkCheckFuture = null;
          _currentUserId = null;
          return const LoginPage();
        }
        
        // User is logged in - check KVKK consent before showing HomePage
        final userId = snapshot.data!.uid;
        
        // Reset KVKK check if user changed (e.g., logged out and logged in with different account)
        if (_currentUserId != userId) {
          _currentUserId = userId;
          _kvkkCheckFuture = _checkKvkkConsent(userId);
        }
        
        // Initialize KVKK check future if not already done
        _kvkkCheckFuture ??= _checkKvkkConsent(userId);
        
        return FutureBuilder<bool>(
          future: _kvkkCheckFuture,
          builder: (context, kvkkSnapshot) {
            // Show loading while checking KVKK consent
            if (kvkkSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Oturum kontrol ediliyor...'),
                    ],
                  ),
                ),
              );
            }
            
            // Check if KVKK consent exists
            final hasConsent = kvkkSnapshot.data ?? false;
            
            if (hasConsent) {
              return const HomePage();
            } else {
              // User needs to accept KVKK consent
              return const KvkkConsentPage();
            }
          },
        );
      },
    );
  }
  
  /// Check if user has valid KVKK consent
  Future<bool> _checkKvkkConsent(String userId) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      return await userProvider.hasValidKvkkConsent(userId: userId);
    } catch (e) {
      logger.err('Error checking KVKK consent: $e');
      return false;
    }
  }
}

/// A widget that handles app lifecycle events for proper resource management
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App resumed to foreground - clear the app badge
      // This handles the case when user clears notifications from notification center
      logger.info('Application resumed, clearing notification badge');
      FcmService().clearBadge();
    } else if (state == AppLifecycleState.detached) {
      // App is about to be terminated, clean up resources
      logger.info('Application is detaching, cleaning up resources');
      Logger.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Cached stream for unread chat count (only for admins)
  /// This prevents the stream from being recreated on every rebuild
  Stream<int>? _unreadChatsStream;
  
  /// Whether the stream has been initialized
  bool _streamInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initUnreadStream();
  }
  
  /// Initialize the chat unread stream for the current user
  /// Called in didChangeDependencies to ensure context is available
  /// - For admins: shows count of chats with unread messages
  /// - For regular users: shows count of unread messages in their chat
  void _initUnreadStream() {
    // Only initialize once
    if (_streamInitialized) return;
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      logger.debug('_initUnreadStream: no user logged in, skipping');
      return;
    }
    
    final isAdmin = FcmService.isAdmin(userId);
    logger.info('_initUnreadStream: userId={} isAdmin={}', [userId, isAdmin]);
    
    final chatManager = context.read<ChatManager>();
    
    if (isAdmin) {
      // Admin: count of chats with unread messages
      _unreadChatsStream = chatManager.totalUnreadChatsStream();
      logger.info('_initUnreadStream: admin unread chats stream initialized');
    } else {
      // Regular user: count of unread messages in their chat
      _unreadChatsStream = chatManager.userUnreadCountStream();
      logger.info('_initUnreadStream: user unread count stream initialized');
    }
    
    _streamInitialized = true;
  }

  // Fetch user role (optional, for admin features)
  Future<String> _getUserRole(String userId) async {
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data()?['role'] ?? 'user';
  }

  // Navigation method for "Planım" (example)
  Future<void> _navigateToMeal(BuildContext context, String userId) async {
    // Replace with your actual logic, e.g., fetching subscription ID
    const subscriptionId = 'example-subscription-id'; // Placeholder //TODO
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealUploadPage(
          userId: userId,
          subscriptionId: subscriptionId,
          onImageUploaded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  Future<void> _navigateToChat(BuildContext context, String userId, bool isAdmin) async {
    if (!context.mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminChatListPage()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
    }
  }

  // Navigation method for "Ödemelerim" (example)
  void _navigateToPayments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPaymentsPage(userId: userId),
      ),
    );
  }

  // Navigation method for "Profilim"
  void _navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: userId),
      ),
    );
  }

  void _navigateToMeas(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementPage(userId: userId),
      ),
    );
  }

  void _navigateToAppointments(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsPage(
          userId: userId,
          subscriptionId: 'default',
          onAppointmentAdded: () {
            // Refresh the UI if needed
          },
        ),
      ),
    );
  }

  // Admin navigation methods
  void _navigateToAdminAppointments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAppointmentsPage(),
      ),
    );
  }

  void _navigateToAdminPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminPaymentsPage(),
      ),
    );
  }

  void _navigateToAdminUsers(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateUserPage(),
      ),
    );
  }

  void _navigateToAdminImages(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminUsersPage(),
      ),
    );
  }

  void _navigateToAdminTimeslots(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminTimeSlotsPage(),
      ),
    );
  }

  void _navigateToNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewsListPage(),
      ),
    );
  }

  void _navigateToAdminNews(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminNewsPage(),
      ),
    );
  }

  void _navigateToNotificationTest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationTestPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Kullanıcı bulunamadı'));
    }

    return FutureBuilder<String>(
      future: _getUserRole(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final role = snapshot.data ?? 'user';
        final isAdmin = FcmService.isAdmin(userId) && userId!='9CwKr0S4mDdZB4Wlc8BK4W8qsT42';

        // Build grid items based on user role
        final List<Map<String, dynamic>> gridItems = [];

        // Common items for all users
        gridItems.addAll([
          {
            'icon': Icons.chat,
            'label': 'Chat',
            'onTap': () => _navigateToChat(context, userId, isAdmin),
            // Only admins get the badge stream (using cached stream)
            'badgeStream': _unreadChatsStream,
          },
          {
            'icon': Icons.food_bank,
            'label': 'Planım',
            'onTap': () => _navigateToMeal(context, userId),
          },
          {
            'icon': Icons.payments,
            'label': 'Ödemelerim',
            'onTap': () => _navigateToPayments(context, userId),
          },
          {
            'icon': Icons.calendar_today,
            'label': 'Randevularım',
            'onTap': () => _navigateToAppointments(context, userId),
          },
          {
            'icon': Icons.person,
            'label': 'Profilim',
            'onTap': () => _navigateToProfile(context, userId),
          },
          {
            'icon': Icons.fitness_center,
            'label': 'Ölçümlerim',
            'onTap': () => _navigateToMeas(context, userId),
          },
          {
            'icon': Icons.newspaper,
            'label': 'Duyurular',
            'onTap': () => _navigateToNews(context),
          },
        ]);

        // Add admin management items if user is admin
        if (isAdmin) {
          gridItems.addAll([
            {
              'icon': Icons.admin_panel_settings,
              'label': 'Kullanıcı Ekle',
              'onTap': () => _navigateToAdminUsers(context),
            },
            {
              'icon': Icons.payments,
              'label': 'Ödeme Yönetimi',
              'onTap': () => _navigateToAdminPayments(context),
            },
            {
              'icon': Icons.calendar_today,
              'label': 'Randevu Yönetimi',
              'onTap': () => _navigateToAdminAppointments(context),
            },
            {
              'icon': Icons.image,
              'label': 'Kullanıcı Yönetimi',
              'onTap': () => _navigateToAdminImages(context),
            },
            {
              'icon': Icons.access_time,
              'label': 'Zaman Dilimi Yönetimi',
              'onTap': () => _navigateToAdminTimeslots(context),
            },
            {
              'icon': Icons.campaign,
              'label': 'Duyuru Yönetimi',
              'onTap': () => _navigateToAdminNews(context),
            },
            {
              'icon': Icons.notifications_active,
              'label': 'Bildirim Testi',
              'onTap': () => _navigateToNotificationTest(context),
            },
          ]);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ana Sayfa'),
            centerTitle: true,
            elevation: 4.0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Çıkış Yap',
                onPressed: () async {
                  // Show confirmation dialog before logging out
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış'),
                      content: const Text('Oturumu kapatmak istediğinize emin misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Evet'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout == true) {
                    // Cancel all local notifications before signing out
                    await NotificationService().cancelAllNotifications();
                    await MealReminderService().cancelAllMealReminders();
                    // Remove FCM token before signing out to stop push notifications
                    await FcmService().removeFcmToken();
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive grid layout based on screen width
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, index) {
                  final item = gridItems[index];
                  final badgeStream = item['badgeStream'] as Stream<int>?;
                  
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item['onTap'],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon with optional badge
                          if (badgeStream != null)
                            StreamBuilder<int>(
                              stream: badgeStream,
                              builder: (context, snapshot) {
                                // Handle stream errors gracefully
                                if (snapshot.hasError) {
                                  logger.warn('Badge stream error: ${snapshot.error}');
                                }
                                
                                final count = snapshot.data ?? 0;
                                return Badge(
                                  isLabelVisible: count > 0,
                                  label: Text(
                                    count > 99 ? '99+' : count.toString(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                  child: Icon(
                                    item['icon'],
                                    size: 48,
                                    color: const Color(0xFFA16AEC),
                                  ),
                                );
                              },
                            )
                          else
                            Icon(
                              item['icon'],
                              size: 48,
                              color: const Color(0xFFA16AEC),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
