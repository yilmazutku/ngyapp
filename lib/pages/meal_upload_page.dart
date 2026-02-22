import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../providers/daily_data_provider.dart';
import '../providers/diet_provider.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../utils/dialog_utils.dart';
import '../utils/meal_formatter.dart';
import '../services/notification_service.dart';
import '../services/meal_reminder_service.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/loading_overlay.dart';
import 'dart:async';

final Logger logger = Logger.forClass(MealUploadPage);

/// Set to false to hide font size adjustment controls
const bool IS_TESTING = false;

/// SharedPreferences key for storing expanded meal states
const String _expandedMealsKey = 'meal_upload_expanded_meals';

class MealUploadPage extends StatefulWidget {
  final String userId;
  final String subscriptionId;
  final VoidCallback onImageUploaded;

  const MealUploadPage({
    super.key,
    required this.userId,
    required this.subscriptionId,
    required this.onImageUploaded,
  });

  static String formatTimeOfDay24(TimeOfDay time) {
    final now = DateTime.now();
    final dateTime =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('HH:mm').format(dateTime);
  }

  @override
  State<MealUploadPage> createState() => _MealUploadPageState();
}

class _MealUploadPageState extends State<MealUploadPage> {
  Map<Meals, bool> checkedStates = {
    for (var meal in Meals.values) meal: false,
  };

  Map<Meals, List<String>> mealContents = {};
  Map<Meals, TimeOfDay> mealTimes = {
    for (var meal in Meals.values) meal: const TimeOfDay(hour: 0, minute: 0),
  };
  bool _isUploading = false;
  Timer? _uploadTimeoutTimer;

  late Future<void> _mealContentsFuture;
  DateTime now = DateTime.now();
  DateTime? _debugSelectedDate;
  double _waterIntakeLiters = 0.0; // Water intake in liters
  final TextEditingController _stepsController = TextEditingController();
  bool _isSavingDailyData = false;
  final NotificationService _notificationService = NotificationService();
  final MealReminderService _mealReminderService = MealReminderService();
  
  // Track which meals are expanded (all collapsed by default)
  final Map<Meals, bool> _expandedMeals = {
    for (var meal in Meals.values) meal: false,
  };
  
  // Font size adjustments for testing
  double _titleFontSize = 14.0;
  double _contentFontSize = 13.0;
  bool _showFontSizeControls = false;

  @override
  void initState() {
    super.initState();
    _mealContentsFuture = _fetchMealStatesAndContents();
    _notificationService.initialize();
    _mealReminderService.initialize();
    
    // Load persisted expanded meal states
    _loadExpandedMeals();
    
    // Schedule meal reminders when page loads (if user has notifications enabled)
    _scheduleMealRemindersIfEnabled();
  }

  /// Load persisted expanded meal states from SharedPreferences
  Future<void> _loadExpandedMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expandedList = prefs.getStringList(_expandedMealsKey) ?? [];
      
      if (mounted) {
        setState(() {
          for (final mealName in expandedList) {
            final meal = Meals.fromName(mealName);
            if (meal != null) {
              _expandedMeals[meal] = true;
            }
          }
        });
      }
      logger.debug('Loaded expanded meals: {}', [expandedList]);
    } catch (e) {
      logger.err('Error loading expanded meals: {}', [e.toString()]);
    }
  }

  /// Save expanded meal states to SharedPreferences
  Future<void> _saveExpandedMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expandedList = _expandedMeals.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key.name)
          .toList();
      await prefs.setStringList(_expandedMealsKey, expandedList);
      logger.debug('Saved expanded meals: {}', [expandedList]);
    } catch (e) {
      logger.err('Error saving expanded meals: {}', [e.toString()]);
    }
  }

  /// Schedule meal reminders if the user has notifications enabled
  Future<void> _scheduleMealRemindersIfEnabled() async {
    try {
      await _mealReminderService.scheduleMealReminders(widget.userId);
    } catch (e) {
      logger.err('Error scheduling meal reminders: {}', [e.toString()]);
    }
  }

  Future<void> _fetchMealStatesAndContents() async {
    try {
      // Fetch meal contents (subtitles) using DietProvider
      final dietProvider = Provider.of<DietProvider>(context, listen: false);
      final subtitles = await dietProvider.fetchLatestDietSubtitles(widget.userId);

      Map<Meals, List<String>> mealContentsTemp = {};
      Map<Meals, TimeOfDay> mealTimesTemp = {};

      if (subtitles != null) {
        //logger.info('user diet document has non-null subtitles.');
        
        // Debug: Print raw subtitles data
        //logger.info('Raw subtitles data: $subtitles');

        for (var entry in subtitles.entries) {
          final mealName = entry.key;
          final mealData = entry.value as Map<String, dynamic>;
          final meal = Meals.fromName(mealName);

          // logger.info('Processing meal: $mealName');
          // logger.info('Meal data: $mealData');

          if (meal != null) {
            // Get content list
            final contentList = List<String>.from(
              (mealData['content'] as List<dynamic>)
                  .map((item) => item['content'].toString()),
            );
            mealContentsTemp[meal] = contentList;

            // Get time
            String? timeString = mealData['time'] as String?;
            logger.info('Time string for $mealName: $timeString');

            TimeOfDay timeOfDay = const TimeOfDay(hour: 0, minute: 0);
            if (timeString != null && timeString.isNotEmpty) {
              try {
                // Handle different time formats
                if (timeString.contains(':')) {
                  final parts = timeString.split(':');
                  if (parts.length == 2) {
                    final hour = int.tryParse(parts[0]);
                    final minute = int.tryParse(parts[1]);
                    if (hour != null && minute != null) {
                      timeOfDay = TimeOfDay(hour: hour, minute: minute);
                      logger.info(
                          'Parsed time for $mealName: ${timeOfDay.hour}:${timeOfDay.minute}');
                    }
                  }
                } else {
                  final parsedTime = DateFormat('HH:mm').parse(timeString);
                  timeOfDay = TimeOfDay.fromDateTime(parsedTime);
                  logger.info(
                      'Parsed time for $mealName: ${timeOfDay.hour}:${timeOfDay.minute}');
                }
              } catch (e) {
                logger.err('Error when parsing the time of dietlist:{}',
                    [e.toString()]);
              }
            }
            mealTimesTemp[meal] = timeOfDay;
          } else {
            logger.warn('Skipping unmatched meal: {}', [mealName]);
          }
        }
      } else {
        logger.warn('No diet lists found for the user.');
      }
      setState(() {
        mealContents = mealContentsTemp;
        mealTimes = mealTimesTemp;
      });

      // Fetch meal states using provider
      final mealManager = Provider.of<MealManager>(context, listen: false);
      final fetchedStates =
          await mealManager.fetchMealStates(widget.userId, date: now);

      setState(() {
        checkedStates = fetchedStates;
      });

      // Fetch daily data using provider
      final dailyDataProvider =
          Provider.of<DailyDataProvider>(context, listen: false);
      final dailyData =
          await dailyDataProvider.fetchDailyDataForDate(widget.userId, date:now);

      setState(() {
        _stepsController.text = dailyData.steps.toString();
              _waterIntakeLiters = (dailyData.waterIntake as num).toDouble();
            });
        } catch (e) {
      logger.err('Error fetching meal states or contents: {}', [e.toString()]);
    }
  }

  /// Check and request photo library permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkPhotoPermission() async {
    // On iOS 14+, use photos permission; on Android, use storage or photos
    Permission permission;
    if (Platform.isIOS) {
      permission = Permission.photos;
    } else {
      // Android 13+ uses photos, older versions use storage
      permission = Permission.photos;
    }

    var status = await permission.status;
    logger.info('Photo permission initial status: {}', [status.toString()]);

    // Already granted or limited access - proceed
    if (status.isGranted || status.isLimited) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      logger.info('Requesting photo permission...');
      status = await permission.request();
      logger.info('Photo permission after request: {}', [status.toString()]);
      
      if (status.isGranted || status.isLimited) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Fotoğraf İzni Gerekli',
      message: 'Öğün fotoğrafı yükleyebilmek için fotoğraf galerisine erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek fotoğraf erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Check and request camera permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    logger.info('Camera permission initial status: {}', [status.toString()]);

    // Already granted - proceed
    if (status.isGranted) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied or restricted
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      logger.info('Requesting camera permission...');
      status = await Permission.camera.request();
      logger.info('Camera permission after request: {}', [status.toString()]);
      
      if (status.isGranted) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Kamera İzni Gerekli',
      message: 'Fotoğraf çekebilmek için kamera erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek kamera erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Show dialog to choose image source (gallery or camera)
  Future<ImageSource?> _chooseSource() async {
    logger.debug('Opening image source selection dialog');
    
    return showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kaynak'),
        content: const Text('Görsel kaynağını seçin.'),
        actions: [
          TextButton(
            onPressed: () {
              logger.debug('Image source selected: gallery');
              Navigator.pop(context, ImageSource.gallery);
            },
            child: const Text('Galeri'),
          ),
          TextButton(
            onPressed: () {
              logger.debug('Image source selected: camera');
              Navigator.pop(context, ImageSource.camera);
            },
            child: const Text('Kamera'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadMealImage(Meals mealCategory) async {
    // 1) Choose image source (gallery or camera)
    final ImageSource? source = await _chooseSource();
    if (source == null) {
      logger.debug('Meal upload cancelled: No source selected');
      return;
    }
    logger.debug('Image source selected: {}', [source.name]);

    // 2) Check permission based on selected source
    final hasPermission = source == ImageSource.camera
        ? await _checkCameraPermission()
        : await _checkPhotoPermission();
    if (!hasPermission) {
      logger.info('Permission denied for {}, aborting upload', [source.name]);
      return;
    }

    final ImagePicker picker = ImagePicker();

    // 3) Pick/capture image
    final XFile? image = await picker.pickImage(source: source);

    if (image == null) {
      // User cancelled image picking
      return;
    }

    // Start upload with timeout
    _uploadTimeoutTimer?.cancel();
    setState(() {
      _isUploading = true;
    });
    _uploadTimeoutTimer = Timer(kLoadingTimeout, () {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    });

    try {
      // 2) Get MealManager from Provider
      //
      // MealManager.uploadMealImg will:
      //   - find today's meal doc:
      //       users/{userId}/meals/{yyyy-MM-dd}/mealEntries/{meal.name}
      //   - load previous meal doc (if exists)
      //   - delete ONLY the old image from Storage
      //   - upload the new image to Storage
      //   - write/merge MealModel in Firestore
      //   - update the "meals" map on the day doc (mark this meal as checked)
      final mealManager = Provider.of<MealManager>(context, listen: false);

      final downloadUrl = await mealManager.uploadMealImg(
        userId: widget.userId,
        meal: mealCategory,
        image: image,
        subscriptionId: widget.subscriptionId,
        overrideDate: kDebugMode ? _debugSelectedDate : null,
        alsoPostToChat: false, // set true if you want it in chat too
        // chatManager: someChatManager, // if you wire ChatManager here
      );

      if (!mounted) return;

      _uploadTimeoutTimer?.cancel();
      setState(() {
        _isUploading = false;
      });

      // 3) Check result from uploadMealImg
      if (downloadUrl != null) {
        // Locally mark this meal as checked in the UI.
        // Firestore state is already updated inside MealManager.
        setState(() {
          checkedStates[mealCategory] = true;
        });

        // Cancel the reminder notification for this meal since it's been uploaded
        await _mealReminderService.cancelMealReminder(mealCategory);

        // Inform parent screen
        widget.onImageUploaded();

        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Öğün görseli başarıyla yüklendi.',
        );
      } else {
        // uploadMealImg returned null → upload failed
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Görsel yüklenirken bir hata oluştu.',
        );
      }
    } catch (e) {
      logger.err('Error in _uploadMealImage: {}', [e.toString()]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Görsel yüklenirken bir hata oluştu.',
      );
    } finally {
      _uploadTimeoutTimer?.cancel();
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _saveDailyData() async {
    // Validate steps input first
    int? steps = int.tryParse(_stepsController.text);
    if (steps == null && _stepsController.text.isNotEmpty) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Girilen adım sayısı geçerli değildir. Lütfen kontrol ediniz.',
        );
        return;
      }

      setState(() {
      _isSavingDailyData = true;
      });

    try {
      final dailyDataProvider =
          Provider.of<DailyDataProvider>(context, listen: false);
      
      // Save both water intake and steps
      await Future.wait([
        dailyDataProvider.saveWaterIntake(widget.userId, now, _waterIntakeLiters),
        dailyDataProvider.saveSteps(widget.userId, now, steps ?? 0),
      ]);

      if (!mounted) return;

      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Günlük verileriniz başarıyla kaydedildi.',
      );
    } catch (e) {
      logger.err('Error saving daily data: {}', [e.toString()]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Veriler kaydedilirken bir hata oluştu.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDailyData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.info('Building MealUploadPage');
    const defaultMealTime = TimeOfDay(hour: 0, minute: 0);

    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Planım',
        actions: [
          // Keep any existing actions here
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _mealContentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                logger.err('Error in FutureBuilder: {}',
                    [snapshot.error ?? 'snapshot error']);
                return Center(child: Text('Error: ${snapshot.error}'));
              } else {
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Font size adjustment controls (for testing)
                        if (IS_TESTING) _buildFontSizeControls(),
                        
                        // Combined Daily Tracking Card (Water + Steps)
                        _buildDailyTrackingCard(),
                        
                        const SizedBox(height: 12),
                        
                        // Meals Section with collapsible tiles
                        _buildCollapsibleMealsList(defaultMealTime),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
          if (_isUploading)
            const LoadingOverlay(message: 'Görsel yükleniyor...'),
        ],
      ),
    );
  }

  /// Font size adjustment controls for testing on phone
  Widget _buildFontSizeControls() {
    return Column(
      children: [
        // Toggle button to show/hide controls
        InkWell(
          onTap: () => setState(() => _showFontSizeControls = !_showFontSizeControls),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _showFontSizeControls ? Colors.purple.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _showFontSizeControls ? Colors.purple.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.text_fields,
                  size: 16,
                  color: _showFontSizeControls ? Colors.purple.shade600 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  'Font Ayarları',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _showFontSizeControls ? Colors.purple.shade700 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showFontSizeControls ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: _showFontSizeControls ? Colors.purple.shade600 : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
        
        // Controls panel
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showFontSizeControls 
              ? CrossFadeState.showFirst 
              : CrossFadeState.showSecond,
          firstChild: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              children: [
                // Title font size
                Row(
                  children: [
                    const SizedBox(width: 80, child: Text('Başlık:', style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _titleFontSize,
                        min: 10,
                        max: 22,
                        divisions: 12,
                        onChanged: (v) => setState(() => _titleFontSize = v),
                        activeColor: Colors.purple,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${_titleFontSize.toInt()}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Content font size
                Row(
                  children: [
                    const SizedBox(width: 80, child: Text('İçerik:', style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: _contentFontSize,
                        min: 10,
                        max: 20,
                        divisions: 10,
                        onChanged: (v) => setState(() => _contentFontSize = v),
                        activeColor: Colors.purple,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${_contentFontSize.toInt()}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Reset button
                TextButton.icon(
                  onPressed: () => setState(() {
                    _titleFontSize = 14.0;
                    _contentFontSize = 13.0;
                  }),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Sıfırla', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.purple.shade700,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          secondChild: const SizedBox(height: 8),
        ),
      ],
    );
  }

  /// Compact combined card for water intake and steps
  Widget _buildDailyTrackingCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with title and history button
            Row(
              children: [
                Text(
                  'Günlük Takip',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                // History button
                TextButton.icon(
                  onPressed: () => _showDailyDataHistory(),
                  icon: Icon(Icons.history, size: 16, color: Colors.indigo.shade600),
                  label: Text(
                    'Geçmiş',
                    style: TextStyle(fontSize: 12, color: Colors.indigo.shade600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const Divider(height: 8, thickness: 0.5),
            // Water row
            Row(
              children: [
                Icon(Icons.water_drop, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Su',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.blue.shade400,
                      inactiveTrackColor: Colors.blue.shade100,
                      thumbColor: Colors.blue.shade600,
                    ),
                    child: Slider(
                      value: _waterIntakeLiters,
                      min: 0,
                      max: 5,
                      divisions: 20,
                      onChanged: (value) => setState(() => _waterIntakeLiters = value),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${_waterIntakeLiters.toStringAsFixed(1)}L',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            
            const Divider(height: 12, thickness: 0.5),
            
            // Steps row
            Row(
              children: [
                Icon(Icons.directions_walk, color: Colors.green.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Adım',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _stepsController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.green.shade400, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Save button
                SizedBox(
                  height: 32,
                  child: FilledButton.icon(
                    onPressed: _isSavingDailyData ? null : _saveDailyData,
                    icon: _isSavingDailyData
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Kaydet', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Show history of daily data (water intake & steps) in a bottom sheet
  Future<void> _showDailyDataHistory() async {
    // Show bottom sheet with history
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return _DailyDataHistorySheet(
              userId: widget.userId,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  /// Build collapsible meals list
  Widget _buildCollapsibleMealsList(TimeOfDay defaultMealTime) {
    // Filter meals with content
    final mealsWithContent = Meals.values.where((meal) {
      final contents = mealContents[meal] ?? [];
      return contents.isNotEmpty;
    }).toList();

    if (mealsWithContent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.restaurant_menu, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Henüz öğün planı oluşturulmamış',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: mealsWithContent.map((mealCategory) {
        final contents = mealContents[mealCategory] ?? [];
        final isExpanded = _expandedMeals[mealCategory] ?? false;
        final isChecked = checkedStates[mealCategory] ?? false;
        final mealTime = mealTimes[mealCategory] ?? defaultMealTime;

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey(mealCategory.name),
              initiallyExpanded: isExpanded,
              onExpansionChanged: (expanded) {
                setState(() {
                  _expandedMeals[mealCategory] = expanded;
                });
                _saveExpandedMeals();
              },
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isChecked ? Colors.green.shade50 : Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isChecked ? Icons.check_circle : Icons.restaurant,
                  size: 18,
                  color: isChecked ? Colors.green.shade600 : Colors.deepOrange.shade600,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      mealCategory.displayLabel,
                      style: TextStyle(
                        fontSize: _titleFontSize,
                        fontWeight: FontWeight.w600,
                        color: isChecked ? Colors.green.shade700 : Colors.deepOrange.shade700,
                      ),
                    ),
                  ),
                  // Time badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      MealUploadPage.formatTimeOfDay24(mealTime),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Camera button
                  InkWell(
                    onTap: () => _uploadMealImage(mealCategory),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 18,
                        color: Colors.blue.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Checkbox
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: isChecked,
                      onChanged: (bool? newValue) async {
                        setState(() {
                          checkedStates[mealCategory] = newValue ?? false;
                        });
                        await Provider.of<MealManager>(context, listen: false)
                            .updateMealState(widget.userId, now, mealCategory, newValue ?? false);
                        if (newValue == true) {
                          await _mealReminderService.cancelMealReminder(mealCategory);
                        }
                      },
                      activeColor: Colors.green.shade600,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: MealFormatter.formatMealContentWithOptions(
                    contents.map((content) => {'content': content}).toList(),
                    fontSize: _contentFontSize,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDebugDateSelector(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final label = _debugSelectedDate != null
        ? DateFormat('yyyy-MM-dd').format(_debugSelectedDate!)
        : 'Bugün (varsayılan)';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.bug_report, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  'Test Yükleme Tarihi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _debugSelectedDate == null
                      ? null
                      : () {
                          setState(() => _debugSelectedDate = null);
                        },
                  child: const Text('Bugüne Dön'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _pickDebugDate(context),
                  icon: const Icon(Icons.date_range),
                  label: const Text('Tarih Seç'),
                ),
                const Spacer(),
                const Text(
                  'Sadece debug modunda aktiftir',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDebugDate(BuildContext context) async {
    if (!kDebugMode) return;
    final initialDate = _debugSelectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() => _debugSelectedDate = picked);
    }
  }

  @override
  void dispose() {
    _uploadTimeoutTimer?.cancel();
    _stepsController.dispose();
    super.dispose();
  }
}

/// Stateful widget for daily data history bottom sheet
class _DailyDataHistorySheet extends StatefulWidget {
  final String userId;
  final ScrollController scrollController;

  const _DailyDataHistorySheet({
    required this.userId,
    required this.scrollController,
  });

  @override
  State<_DailyDataHistorySheet> createState() => _DailyDataHistorySheetState();
}

class _DailyDataHistorySheetState extends State<_DailyDataHistorySheet> {
  static const int _defaultDays = 7;
  static const int _extendedDays = 30;
  
  late Future<Map<DateTime, DailyData>> _historyFuture;
  int _selectedDays = _defaultDays;
  final DateFormat _dateFormat = DateFormat('dd MMM', 'tr_TR');
  final DateFormat _dayNameFormat = DateFormat('EEEE', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _selectedDays - 1));
    final endDate = DateTime(now.year, now.month, now.day);
    
    final dailyDataProvider = Provider.of<DailyDataProvider>(context, listen: false);
    _historyFuture = dailyDataProvider.fetchDailyDataForDateRange(
      widget.userId,
      DateTimeRange(start: startDate, end: endDate),
    );
  }

  void _changeDateRange(int days) {
    setState(() {
      _selectedDays = days;
      _loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.indigo.shade600),
              const SizedBox(width: 8),
              const Text(
                'Geçmiş Kayıtlar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Date range selector
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: _defaultDays, label: Text('7 Gün')),
                  ButtonSegment(value: _extendedDays, label: Text('30 Gün')),
                ],
                selected: {_selectedDays},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    _changeDateRange(selection.first);
                  }
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: FutureBuilder<Map<DateTime, DailyData>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'Veriler yüklenirken bir hata oluştu',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _loadHistory()),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Tekrar Dene'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              
              final data = snapshot.data ?? {};
              if (data.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Henüz kayıt bulunmuyor',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }
              
              // Sort dates in descending order (most recent first)
              final sortedDates = data.keys.toList()
                ..sort((a, b) => b.compareTo(a));
              
              // Calculate averages
              final validEntries = data.values.where(
                (d) => d.waterIntake > 0 || d.steps > 0,
              ).toList();
              final avgWater = validEntries.isEmpty
                  ? 0.0
                  : validEntries.map((d) => d.waterIntake).reduce((a, b) => a + b) / validEntries.length;
              final avgSteps = validEntries.isEmpty
                  ? 0
                  : (validEntries.map((d) => d.steps).reduce((a, b) => a + b) / validEntries.length).round();
              
              return Column(
                children: [
                  // Summary card
                  if (validEntries.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo.shade50, Colors.purple.shade50],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSummaryItem(
                              icon: Icons.water_drop,
                              iconColor: Colors.blue.shade600,
                              label: 'Ort. Su',
                              value: '${avgWater.toStringAsFixed(1)}L',
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.indigo.shade200,
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              icon: Icons.directions_walk,
                              iconColor: Colors.green.shade600,
                              label: 'Ort. Adım',
                              value: _formatSteps(avgSteps),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // History list
                  Expanded(
                    child: Scrollbar(
                      controller: widget.scrollController,
                      child: ListView.separated(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: sortedDates.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final date = sortedDates[index];
                          final dailyData = data[date]!;
                          final isToday = _isToday(date);
                          
                          return _buildHistoryItem(date, dailyData, isToday);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(DateTime date, DailyData data, bool isToday) {
    final hasData = data.waterIntake > 0 || data.steps > 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isToday ? Colors.amber.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday ? Colors.amber.shade300 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Date column
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Bugün' : _dateFormat.format(date),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isToday ? Colors.amber.shade800 : Colors.grey.shade800,
                  ),
                ),
                if (!isToday)
                  Text(
                    _dayNameFormat.format(date),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Water
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.water_drop,
                  size: 16,
                  color: hasData && data.waterIntake > 0 
                      ? Colors.blue.shade500 
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  data.waterIntake > 0 
                      ? '${data.waterIntake.toStringAsFixed(1)}L' 
                      : '-',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: data.waterIntake > 0 ? FontWeight.w600 : FontWeight.normal,
                    color: data.waterIntake > 0 
                        ? Colors.blue.shade700 
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          // Steps
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.directions_walk,
                  size: 16,
                  color: hasData && data.steps > 0 
                      ? Colors.green.shade500 
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  data.steps > 0 
                      ? _formatSteps(data.steps) 
                      : '-',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: data.steps > 0 ? FontWeight.w600 : FontWeight.normal,
                    color: data.steps > 0 
                        ? Colors.green.shade700 
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      final k = steps / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return steps.toString();
  }
}
