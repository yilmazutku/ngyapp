import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
  bool _isSavingWater = false;
  bool _isSavingSteps = false;
  final NotificationService _notificationService = NotificationService();
  final MealReminderService _mealReminderService = MealReminderService();

  @override
  void initState() {
    super.initState();
    _mealContentsFuture = _fetchMealStatesAndContents();
    _notificationService.initialize();
    _mealReminderService.initialize();
    
    // Schedule meal reminders when page loads (if user has notifications enabled)
    _scheduleMealRemindersIfEnabled();
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

  Future<void> _uploadMealImage(Meals mealCategory) async {
    final ImagePicker picker = ImagePicker();

    // 1) Pick image from gallery
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
    );

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

  Future<void> _saveWaterIntake() async {
    setState(() {
      _isSavingWater = true;
    });

    try {
      final dailyDataProvider =
          Provider.of<DailyDataProvider>(context, listen: false);
      await dailyDataProvider.saveWaterIntake(
          widget.userId, now, _waterIntakeLiters);

      if (!mounted) return;

      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Su tüketimi başarıyla kaydedildi.',
      );
    } catch (e) {
      logger.err('Error saving water intake: {}', [e.toString()]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Su tüketimi kaydedilirken bir hata oluştu.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingWater = false;
        });
      }
    }
  }

  Future<void> _saveSteps() async {
    try {
      int? steps = int.tryParse(_stepsController.text);
      if (steps == null) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message:
              'Girilen sayı geçerli değildir. Lütfen sayıyı kontrol edip tekrar giriniz.',
        );
        return;
      }

      setState(() {
        _isSavingSteps = true;
      });

      final dailyDataProvider =
          Provider.of<DailyDataProvider>(context, listen: false);
      await dailyDataProvider.saveSteps(widget.userId, now, steps);

      if (!mounted) return;

      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Adım sayısı başarıyla kaydedildi.',
      );
    } catch (e) {
      logger.err('Error saving steps: {}', [e.toString()]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Adım sayısı kaydedilirken bir hata oluştu.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSteps = false;
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
        title: 'Yemek Listesi Yükleme', 
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
                        // Water Intake and Steps Sections in a Row
                        // Water Intake and Steps Sections (overflow-proof)
                        // Water Intake and Steps Sections (overflow-proof + no Expanded in Column)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final bool isNarrow = constraints.maxWidth < 720; // tweak if you want

                            // Build cards WITHOUT Expanded
                            Widget waterCard = Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    // Title uses Wrap so it can break if tight
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      children: const [
                                        Icon(Icons.local_drink, color: Colors.blue, size: 30),
                                        Text(
                                          'Su Tüketimi',
                                          style: TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Bugün: ${_waterIntakeLiters.toStringAsFixed(2)} Litre',
                                      style: const TextStyle(fontSize: 20),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Slider(
                                      value: _waterIntakeLiters,
                                      min: 0, max: 5, divisions: 20,
                                      label: '${_waterIntakeLiters.toStringAsFixed(2)} L',
                                      onChanged: (value) => setState(() => _waterIntakeLiters = value),
                                      activeColor: Colors.blue,
                                      inactiveColor: Colors.blue[100],
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingWater ? null : _saveWaterIntake,
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.white, backgroundColor: Colors.blue,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: _isSavingWater
                                          ? const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      )
                                          : const Text('Kaydet'),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            Widget stepsCard = Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      children: const [
                                        Icon(Icons.directions_walk, color: Colors.green, size: 30),
                                        Text(
                                          'Adım Sayısı',
                                          style: TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Bugün: ${_stepsController.text.isNotEmpty ? _stepsController.text : '0'}',
                                      style: const TextStyle(fontSize: 20),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _stepsController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Adım sayısını giriniz',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingSteps ? null : _saveSteps,
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.white, backgroundColor: Colors.green,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: _isSavingSteps
                                          ? const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      )
                                          : const Text('Kaydet'),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (isNarrow) {
                              // IMPORTANT: no Expanded inside Column (it’s inside a SingleChildScrollView)
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  waterCard,
                                  const SizedBox(height: 16),
                                  stepsCard,
                                ],
                              );
                            } else {
                              // Wide layout: side-by-side with Expanded is fine
                              return Row(
                                children: [
                                  Expanded(child: waterCard),
                                  const SizedBox(width: 16),
                                  Expanded(child: stepsCard),
                                ],
                              );
                            }
                          },
                        ),


                        const SizedBox(height: 16),
                        // // Meals Section
                        // if (kDebugMode) ...[
                        //   _buildDebugDateSelector(context),
                        //   const SizedBox(height: 16),
                        // ],
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: Meals.values.length,
                          itemBuilder: (context, index) {
                            final mealCategory = Meals.values[index];
                            final contents = mealContents[mealCategory] ?? [];

                            // Skip meals with no content
                            if (contents.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  title: Text(
                                    mealCategory.displayLabel,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: MealFormatter.formatMealContentWithOptions(
                                        contents.map((content) => {'content': content}).toList()
                                      ),
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        MealUploadPage.formatTimeOfDay24(
                                            mealTimes[mealCategory] ??
                                                defaultMealTime),
                                        textAlign: TextAlign.left,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.camera_alt),
                                        color: Colors.blue,
                                        onPressed: () async {
                                          await _uploadMealImage(mealCategory);
                                        },
                                      ),
                                      Checkbox(
                                        value: checkedStates[mealCategory],
                                        onChanged: (bool? newValue) async {
                                          setState(() {
                                            checkedStates[mealCategory] =
                                                newValue ?? false;
                                          });

                                          // Update the meal state in Firestore
                                          await  Provider.of<MealManager>(context, listen: false).updateMealState(widget.userId, now, mealCategory,newValue ?? false);
                                          
                                          // Cancel reminder if meal is checked off
                                          if (newValue == true) {
                                            await _mealReminderService.cancelMealReminder(mealCategory);
                                          }
                                        },
                                        activeColor: Colors.deepOrange,
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(),
                              ],
                            );
                          },
                        ),
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
