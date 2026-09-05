import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diet_goals.dart';
import '../models/diet_section.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';
import '../providers/daily_data_provider.dart';
import '../providers/diet_provider.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/special_lines_provider.dart';
import '../utils/diet_menu_parser.dart';
import '../utils/dialog_utils.dart';
import '../utils/pdf_launcher.dart';
import '../services/notification_service.dart';
import '../services/meal_reminder_service.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/chat_image_preview.dart';
import '../widgets/diet_plan_view.dart';
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

  @override
  State<MealUploadPage> createState() => _MealUploadPageState();
}

class _MealUploadPageState extends State<MealUploadPage> {
  Map<Meals, bool> checkedStates = {
    for (var meal in Meals.dietValues) meal: false,
  };

  // Weekday (Hafta İçi) menu.
  DietMenu _weekdayMenu = const DietMenu.empty();

  // Weekend (Hafta Sonu) menu. Only populated when the active diet defines one.
  DietMenu _weekendMenu = const DietMenu.empty();

  /// Download URL of the active diet's attached recipe PDF, if any. Drives the
  /// tappable "*tarifi ektedir" link inside the meal content.
  String? _recipePdfUrl;

  /// Goal lines of the active diet, shown above the first meal.
  DietGoals _goals = const DietGoals.empty();

  /// Today's uploaded images per meal type.
  Map<Meals, List<String>> _mealImages = {};

  bool _isUploading = false;
  Timer? _uploadTimeoutTimer;

  late Future<void> _mealContentsFuture;
  DateTime now = DateTime.now();
  DateTime? _debugSelectedDate;
  double _waterIntakeLiters = 0.0; // Water intake in liters
  final TextEditingController _stepsController = TextEditingController();
  final FocusNode _stepsFocusNode = FocusNode();
  bool _isSavingDailyData = false;
  final NotificationService _notificationService = NotificationService();
  final MealReminderService _mealReminderService = MealReminderService();
  
  // Track which meal tiles are expanded (all collapsed by default). Keyed by a
  // string so weekday and weekend tiles for the same meal don't share state
  // (see [_expansionKey]).
  final Map<String, bool> _expandedMeals = {};
  
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

    // Clear the leading "0" when the steps field is focused so the user can
    // type directly (e.g. "100" instead of "0100"), and restore "0" on blur
    // when left empty to preserve the initial display.
    _stepsFocusNode.addListener(_handleStepsFocusChange);
    
    // Load persisted expanded meal states
    _loadExpandedMeals();
    
    // Schedule meal reminders when page loads (if user has notifications enabled)
    _scheduleMealRemindersIfEnabled();
  }

  /// Prevents a leading zero from being prepended to the steps input.
  ///
  /// On focus gained: if the field only shows the placeholder "0", clear it so
  /// typing starts fresh. On focus lost: if the field is empty, restore "0" to
  /// keep the display consistent with the initial/loaded state.
  void _handleStepsFocusChange() {
    if (_stepsFocusNode.hasFocus) {
      if (_stepsController.text == '0') {
        _stepsController.clear();
      }
    } else if (_stepsController.text.isEmpty) {
      _stepsController.text = '0';
    }
  }

  /// Load persisted expanded meal states from SharedPreferences
  Future<void> _loadExpandedMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expandedList = prefs.getStringList(_expandedMealsKey) ?? [];
      
      if (mounted) {
        setState(() {
          for (final key in expandedList) {
            _expandedMeals[key] = true;
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
          .map((entry) => entry.key)
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
      // Pull the admin-configured special lines first so the meal formatter
      // recognizes every marker (built-in + admin) when rendering the plan.
      try {
        await Provider.of<SpecialLinesProvider>(context, listen: false)
            .fetchSpecialLines();
      } catch (e) {
        logger.warn(
            'Could not load admin special lines, falling back to built-ins only: {}',
            [e.toString()]);
      }

      // Fetch the latest diet document (weekday + optional weekend menus).
      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
      final dietProvider = Provider.of<DietProvider>(context, listen: false);
      final diet = await dietProvider.fetchLatestDietDocument(widget.userId);

      if (diet == null) {
        logger.warn('No diet lists found for the user.');
      }

      setState(() {
        _weekdayMenu = DietMenu.fromSubtitles(diet?.subtitles);
        _weekendMenu = DietMenu.fromSubtitles(diet?.weekendSubtitles);
        _recipePdfUrl = diet?.recipePdfUrl;
        _goals = diet?.goals ?? const DietGoals.empty();
      });

      // Fetch meal states using provider
      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
      final mealManager = Provider.of<MealManager>(context, listen: false);
      final fetchedStates =
          await mealManager.fetchMealStates(widget.userId, date: now);

      setState(() {
        checkedStates = fetchedStates;
      });

      // Fetch today's uploaded images
      await _refreshMealImages();

      // Fetch daily data using provider
      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
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

  /// Fetches today's meal images from MealManager and updates [_mealImages].
  Future<void> _refreshMealImages() async {
    try {
      final mealManager = Provider.of<MealManager>(context, listen: false);
      final effectiveDate = kDebugMode ? _debugSelectedDate ?? now : now;
      final dateKey = DateFormat('yyyy-MM-dd').format(effectiveDate);
      final meals = await mealManager.fetchMeals(
        null,
        userId: widget.userId,
        showAllImages: true,
        date: dateKey,
      );

      final map = <Meals, List<String>>{};
      for (final m in meals) {
        if (m.imageUrls.isNotEmpty) {
          map[m.mealType] = m.imageUrls;
        }
      }

      if (!mounted) return;
      setState(() {
        _mealImages = map;
      });
    } catch (e) {
      logger.err('Error refreshing meal images: {}', [e]);
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
      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
      final mealManager = Provider.of<MealManager>(context, listen: false);

      // Pre-check: see if the meal already has max images
      final existingMeals = await mealManager.fetchMeals(
        null,
        userId: widget.userId,
        showAllImages: true,
        date: DateFormat('yyyy-MM-dd')
            .format(kDebugMode ? _debugSelectedDate ?? now : now),
      );
      final existingMeal = existingMeals
          .where((m) => m.mealType == mealCategory)
          .toList();
      if (existingMeal.isNotEmpty && !existingMeal.first.canAddMoreImages) {
        if (!mounted) return;
        _uploadTimeoutTimer?.cancel();
        setState(() => _isUploading = false);
        await DialogUtils.openError(
          context,
          title: 'Limit',
          message:
              'Bu öğün için en fazla ${MealModel.maxImages} görsel yükleyebilirsiniz.',
        );
        return;
      }

      final downloadUrl = await mealManager.uploadMealImg(
        userId: widget.userId,
        meal: mealCategory,
        image: image,
        subscriptionId: widget.subscriptionId,
        overrideDate: kDebugMode ? _debugSelectedDate : null,
        alsoPostToChat: false,
      );

      if (!mounted) return;

      _uploadTimeoutTimer?.cancel();
      setState(() {
        _isUploading = false;
      });

      if (downloadUrl != null) {
        setState(() {
          checkedStates[mealCategory] = true;
        });

        await _mealReminderService.cancelMealReminder(mealCategory);
        await _refreshMealImages();
        widget.onImageUploaded();

        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Öğün görseli başarıyla yüklendi.',
        );
      } else {
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
    // The keyboard has no business staying up over the result of the save.
    FocusManager.instance.primaryFocus?.unfocus();

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

                        // Debug-only date picker: lets us preview weekday vs
                        // weekend menus and uploads on a chosen date.
                        _buildDebugDateSelector(context),

                        // Combined Daily Tracking Card (Water + Steps)
                        _buildDailyTrackingCard(),
                        
                        const SizedBox(height: 8),

                        _buildViewUploadsButton(),

                        const SizedBox(height: 8),

                        // Diet-wide goal lines, above the first meal.
                        if (_goals.hasAny) DietGoalsCard(goals: _goals),

                        // Meals Section with collapsible tiles (split into
                        // weekday/weekend sections when the diet has both).
                        _buildMealsArea(defaultMealTime),
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
                      focusNode: _stepsFocusNode,
                      keyboardType: TextInputType.number,
                      // A number keyboard has no return key on iOS, so the
                      // field also has to offer a way out of itself.
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _stepsFocusNode.unfocus(),
                      onTapOutside: (_) => _stepsFocusNode.unfocus(),
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

  /// Composite key so weekday and weekend tiles for the same meal keep
  /// independent expanded/collapsed state.
  String _expansionKey(Meals meal, {DietSection? section}) =>
      section == null ? meal.name : '${section.key}_${meal.name}';

  /// Builds the meals area: a single interactive list for weekday-only diets,
  /// or two labelled sections (Hafta İçi + Hafta Sonu) when the diet defines a
  /// weekend menu. Only the section matching today is interactive (check-off +
  /// photo upload); the other is shown read-only for reference.
  Widget _buildMealsArea(TimeOfDay defaultMealTime) {
    if (!_weekendMenu.hasContent) {
      return _buildMealsSection(
        menu: _weekdayMenu,
        interactive: true,
        defaultMealTime: defaultMealTime,
      );
    }

    final effectiveDate = kDebugMode ? _debugSelectedDate ?? now : now;
    final weekendToday = isWeekendDate(effectiveDate);

    return Column(
      children: [
        _buildMealsSection(
          section: DietSection.weekday,
          sectionIcon: Icons.calendar_view_week,
          menu: _weekdayMenu,
          interactive: !weekendToday,
          isToday: !weekendToday,
          defaultMealTime: defaultMealTime,
        ),
        const SizedBox(height: 12),
        _buildMealsSection(
          section: DietSection.weekend,
          sectionIcon: Icons.weekend,
          menu: _weekendMenu,
          interactive: weekendToday,
          isToday: weekendToday,
          defaultMealTime: defaultMealTime,
        ),
      ],
    );
  }

  /// Builds one menu's meal tiles (optionally under a section header).
  Widget _buildMealsSection({
    required DietMenu menu,
    required bool interactive,
    required TimeOfDay defaultMealTime,
    DietSection? section,
    IconData? sectionIcon,
    bool isToday = false,
  }) {
    final mealsWithContent = menu.mealsWithContent;

    // Weekday-only diets keep the original full-page empty state.
    if (mealsWithContent.isEmpty && section == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.restaurant_menu, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Henüz öğün planı oluşturulmamış',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section != null)
          DietSectionHeader(
            section: section,
            icon: sectionIcon,
            isToday: isToday,
          ),
        if (mealsWithContent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'Bu bölüm için öğün planı bulunmuyor.',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...mealsWithContent.map((meal) => _buildMealTile(
                mealCategory: meal,
                contents: menu.linesOf(meal),
                mealTime: menu.timeOf(meal, defaultMealTime),
                interactive: interactive,
                expansionKey: _expansionKey(meal, section: section),
              )),
      ],
    );
  }

  /// A single collapsible meal tile. When [interactive] is true it shows the
  /// check-off and camera controls (today's menu); otherwise it is a read-only
  /// reference tile (the other day-type's menu).
  Widget _buildMealTile({
    required Meals mealCategory,
    required List<String> contents,
    required TimeOfDay mealTime,
    required bool interactive,
    required String expansionKey,
  }) {
    final isChecked = interactive && (checkedStates[mealCategory] ?? false);
    // Whether a photo has actually been uploaded for this meal today. Drives
    // the "Yüklendi / Yüklü Değil" status, independently of the checkbox.
    final hasPhoto =
        interactive && (_mealImages[mealCategory]?.isNotEmpty ?? false);

    return DietMealTile(
      mealCategory: mealCategory,
      contents: contents,
      mealTime: mealTime,
      expansionKey: expansionKey,
      expanded: _expandedMeals[expansionKey] ?? false,
      onExpansionChanged: (expanded) {
        setState(() {
          _expandedMeals[expansionKey] = expanded;
        });
        _saveExpandedMeals();
      },
      tone: !interactive
          ? DietMealTone.reference
          : (isChecked ? DietMealTone.completed : DietMealTone.active),
      titleFontSize: _titleFontSize,
      contentFontSize: _contentFontSize,
      onRecipeTap: (_recipePdfUrl == null || _recipePdfUrl!.isEmpty)
          ? null
          : () => openPdfUrl(context, _recipePdfUrl),
      // Tracking controls only for the active (today's) menu.
      trailing: interactive
          ? [
              const SizedBox(width: 6),
              // Upload button: "Yükle" label to the LEFT of the camera icon.
              InkWell(
                onTap: () => _uploadMealImage(mealCategory),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Yükle',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 18,
                        color: Colors.blue.shade600,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
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
                        .updateMealState(
                            widget.userId, now, mealCategory, newValue ?? false);
                    if (newValue == true) {
                      await _mealReminderService
                          .cancelMealReminder(mealCategory);
                    }
                  },
                  activeColor: Colors.green.shade600,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ]
          : const <Widget>[],
      // Upload status for today's menu: green "Yüklendi" + tick when a photo
      // exists, otherwise red "Yüklü Değil" + cross.
      subtitle: interactive
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasPhoto ? 'Yüklendi' : 'Yüklü Değil',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        hasPhoto ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  hasPhoto ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: hasPhoto ? Colors.green.shade600 : Colors.red.shade600,
                ),
              ],
            )
          : null,
    );
  }

  /// Full-width button that opens the day's uploaded photos, grouped by meal,
  /// in a bottom sheet. Hidden while nothing has been uploaded today.
  Widget _buildViewUploadsButton() {
    final totalImages =
        _mealImages.values.fold<int>(0, (sum, list) => sum + list.length);
    if (totalImages == 0) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showUploadsSheet,
        icon: const Icon(Icons.photo_library_outlined, size: 18),
        label: Text('Yüklediklerimi Gör / Sil'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          side: BorderSide(color: Colors.blue.shade300),
          foregroundColor: Colors.blue.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Future<void> _showUploadsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final mealsWithImages = Meals.dietValues
                .where((m) => (_mealImages[m] ?? []).isNotEmpty)
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library,
                              color: Colors.blue.shade600),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Yüklediklerim',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (mealsWithImages.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('Henüz yüklenmiş görsel yok.'),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: mealsWithImages.length,
                          itemBuilder: (_, index) {
                            final meal = mealsWithImages[index];
                            final images = _mealImages[meal]!;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${meal.label}  (${images.length}/${MealModel.maxImages})',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 90,
                                      child: ListView.separated(
                                        key: PageStorageKey(
                                            'sheet_imgs_${meal.name}'),
                                        scrollDirection: Axis.horizontal,
                                        itemCount: images.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (_, imgIdx) {
                                          final url = images[imgIdx];
                                          return Stack(
                                            children: [
                                              GestureDetector(
                                                onTap: () =>
                                                    _showFullImage(url),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                  child: ChatImagePreview(
                                                    imageUrl: url,
                                                    width: 90,
                                                    height: 90,
                                                    borderRadius: 8,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 3,
                                                right: 3,
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    final confirmed =
                                                        await DialogUtils
                                                            .openConfirm(
                                                      ctx,
                                                      title: 'Görseli Sil',
                                                      message:
                                                          'Bu görseli silmek istediğinize emin misiniz?',
                                                      confirmText: 'Sil',
                                                      cancelText: 'İptal',
                                                    );
                                                    if (!confirmed) return;
                                                    if (!mounted) return;

                                                    try {
                                                      final mealManager =
                                                          Provider.of<MealManager>(
                                                              context,
                                                              listen:
                                                                  false);
                                                      await mealManager
                                                          .deleteMealImage(
                                                        userId:
                                                            widget.userId,
                                                        meal: meal,
                                                        imageUrlToDelete:
                                                            url,
                                                        overrideDate: kDebugMode
                                                            ? _debugSelectedDate
                                                            : null,
                                                      );
                                                      await _refreshMealImages();
                                                      if (!mounted) return;

                                                      final imgs =
                                                          _mealImages[
                                                                  meal] ??
                                                              [];
                                                      if (imgs.isEmpty) {
                                                        setState(() {
                                                          checkedStates[
                                                              meal] = false;
                                                        });
                                                      }
                                                      setSheetState(() {});
                                                    } catch (e) {
                                                      logger.err(
                                                          'Error deleting meal image: {}',
                                                          [e]);
                                                      // Guarded on ctx, the
                                                      // sheet's own context.
                                                      if (ctx.mounted) {
                                                        await DialogUtils
                                                            .openError(
                                                          ctx,
                                                          title: 'Hata',
                                                          message:
                                                              'Görsel silinirken bir hata oluştu.',
                                                        );
                                                      }
                                                    }
                                                  },
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Colors.black54,
                                                      shape:
                                                          BoxShape.circle,
                                                    ),
                                                    padding:
                                                        const EdgeInsets
                                                            .all(4),
                                                    child: const Icon(
                                                        Icons.delete,
                                                        size: 15,
                                                        color:
                                                            Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Shows a full-screen preview of a meal image.
  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
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
    _stepsFocusNode.removeListener(_handleStepsFocusChange);
    _stepsFocusNode.dispose();
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
