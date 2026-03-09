import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';

/// Notification types for testing
enum NotificationType {
  chat('Sohbet', Icons.chat),
  meal('Öğün', Icons.restaurant),
  news('Haber/Duyuru', Icons.newspaper);

  const NotificationType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Admin page for testing all notification types.
///
/// Fixes applied:
/// - Explicit Android channel creation (heads-up depends on channel settings)
/// - Separate channels per type (chat/meal/news)
/// - Unique notification IDs per send (prevents "update" behavior that may skip heads-up)
/// - Timezone local location setup for tz.local
/// - Runtime permission request (Android 13+)
class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({super.key});

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  final Logger _logger = Logger.forClass(NotificationTestPage);
  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  // Common state
  NotificationType _selectedType = NotificationType.chat;
  int _delaySeconds = 5;
  bool _isScheduling = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // Keep last scheduled notification id so "Cancel" works even with unique IDs
  int? _lastScheduledNotificationId;

  // Chat notification state
  final TextEditingController _chatMessageController = TextEditingController();

  // Meal notification state
  Meals _selectedMeal = Meals.br;

  // News notification state
  final TextEditingController _newsTitleController = TextEditingController();
  final TextEditingController _newsBodyController = TextEditingController();
  final TextEditingController _newsImageController = TextEditingController();

  // Separate channels per type (IMPORTANT for heads-up/banner behavior)
  static const String _chatChannelId = 'test_chat';
  static const String _mealChannelId = 'test_meal';
  static const String _newsChannelId = 'test_news';

  @override
  void initState() {
    super.initState();
    _chatMessageController.text = 'Merhaba, bu bir test mesajıdır!';
    _initializeNotifications();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _chatMessageController.dispose();
    _newsTitleController.dispose();
    _newsBodyController.dispose();
    _newsImageController.dispose();
    super.dispose();
  }

  String get _currentNotificationTitle {
    switch (_selectedType) {
      case NotificationType.chat:
        return PushNotificationReference.chatAdminToUserTitle;
      case NotificationType.meal:
        return NotificationConstants.mealReminderTitle;
      case NotificationType.news:
        return _newsTitleController.text.isEmpty
            ? PushNotificationReference.newsDefaultTitle
            : '${PushNotificationReference.newsTitlePrefix}${_newsTitleController.text}';
    }
  }

  String get _currentNotificationBody {
    switch (_selectedType) {
      case NotificationType.chat:
        return _chatMessageController.text.isEmpty
            ? PushNotificationReference.chatDefaultBody
            : _chatMessageController.text;
      case NotificationType.meal:
        return NotificationConstants.getMealReminderBody(_selectedMeal.label);
      case NotificationType.news:
        return _newsBodyController.text.isEmpty
            ? 'Yeni duyuru içeriği'
            : _newsBodyController.text;
    }
  }

  String get _currentChannelId {
    switch (_selectedType) {
      case NotificationType.chat:
        return _chatChannelId;
      case NotificationType.meal:
        return _mealChannelId;
      case NotificationType.news:
        return _newsChannelId;
    }
  }

  /// Make a fresh ID each time so Android treats it as a new notification (more likely heads-up)
  int _newNotificationId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    // Keep within signed 32-bit range
    return ms.remainder(2147483647);
  }

  Future<void> _configureLocalTimeZone() async {
    // tz.local must be set for tz.TZDateTime.from(..., tz.local)
    tz_data.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      _logger.info('Timezone configured: $timeZoneName');
    } catch (e) {
      // Fallback: still set something predictable if device TZ fetch fails
      tz.setLocalLocation(tz.getLocation('UTC'));
      _logger.warn('Timezone fetch failed, fallback to UTC: $e');
    }
  }

  Future<void> _createAndroidChannels() async {
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl == null) return;

    // Android 13+ runtime permission
    try {
      await androidImpl.requestNotificationsPermission();
    } catch (_) {}

    const channels = <AndroidNotificationChannel>[
      AndroidNotificationChannel(
        _chatChannelId,
        'Test - Sohbet',
        description: 'Sohbet test bildirimleri',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        _mealChannelId,
        'Test - Öğün',
        description: 'Öğün test bildirimleri',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        _newsChannelId,
        'Test - Haber/Duyuru',
        description: 'Haber/Duyuru test bildirimleri',
        importance: Importance.high,
      ),
    ];

    for (final c in channels) {
      await androidImpl.createNotificationChannel(c);
    }

    _logger.info('Android notification channels created');
  }

  Future<void> _initializeNotifications() async {
    await _configureLocalTimeZone();

    const androidSettings =
    AndroidInitializationSettings(NotificationConstants.androidNotificationIcon);

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // iOS permission request (safe even if already granted)
    final iosImpl = _notifications
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    // Create channels explicitly on Android
    await _createAndroidChannels();

    _logger.info('Test notification service initialized');
  }

  Future<void> _scheduleTestNotification() async {
    if (_isScheduling) return;

    setState(() {
      _isScheduling = true;
      _remainingSeconds = _delaySeconds;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remainingSeconds--);

      if (_remainingSeconds <= 0) {
        timer.cancel();
        if (mounted) setState(() => _isScheduling = false);
      }
    });

    try {
      final id = _newNotificationId();
      _lastScheduledNotificationId = id;

      final androidDetails = AndroidNotificationDetails(
        _currentChannelId,
        _selectedType == NotificationType.chat
            ? 'Test - Sohbet'
            : _selectedType == NotificationType.meal
            ? 'Test - Öğün'
            : 'Test - Haber/Duyuru',
        channelDescription: 'Test bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        icon: NotificationConstants.androidNotificationIcon,
        // Don’t force full screen; heads-up should be handled by channel+priority.
        fullScreenIntent: false,
        category: _selectedType == NotificationType.chat
            ? AndroidNotificationCategory.message
            : AndroidNotificationCategory.reminder,
        // Simple “big picture” example using local resource (URL needs download -> not implemented here)
        largeIcon: _selectedType == NotificationType.news &&
            _newsImageController.text.isNotEmpty
            ? const DrawableResourceAndroidBitmap('@mipmap/ngy')
            : null,
        styleInformation: _selectedType == NotificationType.news &&
            _newsImageController.text.isNotEmpty
            ? BigPictureStyleInformation(
          const DrawableResourceAndroidBitmap('@mipmap/ngy'),
          contentTitle: _currentNotificationTitle,
          summaryText: _currentNotificationBody,
        )
            : null,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final scheduledTime = DateTime.now().add(Duration(seconds: _delaySeconds));

      await _notifications.zonedSchedule(
        id,
        _currentNotificationTitle,
        _currentNotificationBody,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        // For testing, use exact so you don’t get “late” behavior
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );

      _logger.info(
        'Test ${_selectedType.label} notification scheduled in $_delaySeconds seconds (id=$id)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedType.label} bildirimi $_delaySeconds saniye sonra gönderilecek',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.err('Error scheduling test notification: $e');

      _countdownTimer?.cancel();
      if (mounted) {
        setState(() {
          _isScheduling = false;
          _remainingSeconds = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bildirim zamanlanamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelTestNotification() async {
    _countdownTimer?.cancel();

    final id = _lastScheduledNotificationId;
    if (id != null) {
      await _notifications.cancel(id);
      _logger.info('Cancelled notification id=$id');
    }

    if (mounted) {
      setState(() {
        _isScheduling = false;
        _remainingSeconds = 0;
        _lastScheduledNotificationId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bildirim iptal edildi'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildChatNotificationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Başlık',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            PushNotificationReference.chatAdminToUserTitle,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Mesaj İçeriği',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chatMessageController,
          enabled: !_isScheduling,
          maxLines: 3,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.all(16),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.message),
            ),
            hintText: 'Test mesajınızı yazın...',
          ),
        ),
      ],
    );
  }

  Widget _buildMealNotificationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Öğün Türü',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Meals>(
          value: _selectedMeal,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: const Icon(Icons.restaurant),
          ),
          items: Meals.dietValues.map((meal) {
            return DropdownMenuItem<Meals>(
              value: meal,
              child: Text('${meal.label} (${meal.defaultTime})'),
            );
          }).toList(),
          onChanged: _isScheduling
              ? null
              : (Meals? value) {
            if (value != null) setState(() => _selectedMeal = value);
          },
        ),
      ],
    );
  }

  Widget _buildNewsNotificationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duyuru Başlığı',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _newsTitleController,
          enabled: !_isScheduling,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: const Icon(Icons.title),
            hintText: 'Duyuru başlığı...',
            helperText:
            'Boş bırakılırsa "${PushNotificationReference.newsDefaultTitle}" kullanılır',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text(
          'Duyuru İçeriği',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _newsBodyController,
          enabled: !_isScheduling,
          maxLines: 3,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.all(16),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(Icons.article),
            ),
            hintText: 'Duyuru içeriği...',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text(
          'Görsel URL (opsiyonel)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _newsImageController,
          enabled: !_isScheduling,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: const Icon(Icons.image),
            hintText: 'https://example.com/image.png',
            helperText:
            'Not: URL’den görsel göstermek için önce indirip bitmap yapmanız gerekir. (Bu testte local icon kullanılıyor)',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Testi'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      size: 64,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bildirim Testi',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Farklı bildirim türlerini test edin: Sohbet, Öğün hatırlatma ve Haber/Duyuru.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bildirim Türü',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<NotificationType>(
                      segments: NotificationType.values.map((type) {
                        return ButtonSegment<NotificationType>(
                          value: type,
                          label: Text(type.label),
                          icon: Icon(type.icon),
                        );
                      }).toList(),
                      selected: {_selectedType},
                      onSelectionChanged: _isScheduling
                          ? null
                          : (Set<NotificationType> selected) {
                        setState(() => _selectedType = selected.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_selectedType.icon,
                            color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedType.label} Bildirimi Ayarları',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (_selectedType == NotificationType.chat)
                      _buildChatNotificationFields(),
                    if (_selectedType == NotificationType.meal)
                      _buildMealNotificationFields(),
                    if (_selectedType == NotificationType.news)
                      _buildNewsNotificationFields(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gecikme (saniye)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _delaySeconds.toString(),
                      enabled: !_isScheduling,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefixIcon: const Icon(Icons.timer),
                        suffixText: 'saniye',
                        hintText: 'Örn: 5',
                      ),
                      onChanged: (value) {
                        final seconds = int.tryParse(value);
                        if (seconds != null && seconds > 0) {
                          setState(() => _delaySeconds = seconds);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_isScheduling) ...[
              Card(
                elevation: 2,
                color: Colors.blue[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        '${_selectedType.label} bildirimi gönderilecek:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_remainingSeconds saniye',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (_isScheduling) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelTestNotification,
                      icon: const Icon(Icons.cancel),
                      label: const Text('İptal Et'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _scheduleTestNotification,
                      icon: const Icon(Icons.send),
                      label: Text('${_selectedType.label} Bildirimi Gönder'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 1,
              color: Colors.amber[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[700]),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Android’da banner/heads-up görünmesi channel ayarına bağlıdır.\n'
                            'Eğer yine görünmüyorsa: Telefon Ayarları → Uygulamalar → (App) → Bildirimler → '
                            '"Test - Haber/Duyuru" kanalında "Pop on screen / Heads-up" açık mı kontrol edin.\n'
                            'Gerekirse uygulamayı kaldırıp tekrar kurun (channel reset).',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
