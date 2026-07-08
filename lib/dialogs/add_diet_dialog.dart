import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Replace with your actual imports
import '../models/logger.dart';
import '../models/meal_model.dart'; // For Meals enum
import '../models/special_line_model.dart'; // SpecialLinesRegistry / detect
import '../models/subs_model.dart'; // Add subscription model import
import '../file_handlers//file_handler.dart'; // For handleFile
// For deleteFile
import '../providers/sub_provider.dart';
// Add user provider import
import '../providers/diet_provider.dart'; // Add diet provider import
import '../providers/special_lines_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/meal_formatter.dart';

/// We'll create a logger for this dialog
final Logger log = Logger.forClass(AddDietDialog);

class AddDietDialog extends StatefulWidget {
  final String userId; // Which user to upload diets for
  final SubscriptionModel? selectedSubscription; // Pre-selected subscription

  const AddDietDialog({
    super.key, 
    required this.userId,
    this.selectedSubscription,
  });

  @override
  State<AddDietDialog> createState() => _AddDietDialogState();
}

class _AddDietDialogState extends State<AddDietDialog> {
  // Subtitles structure, same as FileHandlerPage
  List<Map<String, dynamic>> subtitles = [];

  // Local file path where docx is saved
  String? _localFilePath;
  // Track whether we've parsed and have a preview
  bool _hasParsedPreview = false;
  
  // Subscription related variables
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = false;
  
  // Track upload state
  bool _isUploading = false;

  // Add ScrollController to manage scrolling
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Initialize subtitles with Meals enum
    for (var meal in Meals.dietValues) {
      subtitles.add({
        'name': meal.label,
        'time': meal.defaultTime,
        'content': [],
      });
    }
    
    // Initialize scroll controller
    _scrollController = ScrollController();
    
    // Use pre-selected subscription if provided
    if (widget.selectedSubscription != null) {
      _selectedSubscription = widget.selectedSubscription;
      _subscriptions = [widget.selectedSubscription!];
    } else {
      // Fetch subscriptions for this user
      _fetchSubscriptions();
    }
  }

  @override
  void dispose() {
    // Dispose scroll controller
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchSubscriptions() async {
    setState(() {
      _isLoadingSubscriptions = true;
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final List<SubscriptionModel> activeSubscriptions =
      await subProvider.fetchSubscriptions(
        userId: widget.userId,
        showAllSubscriptions: false, // Only active subscriptions
      );

      // Check if widget is still mounted before updating state
      if (!mounted) return;

      setState(() {
        _subscriptions = activeSubscriptions;
        _isLoadingSubscriptions = false;
        
        // Select the first subscription if available
        if (_subscriptions.isNotEmpty) {
          _selectedSubscription = _subscriptions.first;
        } else {
          _selectedSubscription = null;
        }
      });
      
      // Show error if no active subscriptions found
      if (activeSubscriptions.isEmpty) {
        log.err('No active subscriptions found for user: {}', [widget.userId]);
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Uyarı',
            message:
                'Bu kullanıcının aktif paketi bulunmamaktadır. Diyet listesi eklemek için önce bir paket eklemelisiniz.',
          );
        }
      }
    } catch (e) {
      log.err('Error fetching subscriptions: {}', [e]);
      if (!mounted) return;
      
      setState(() {
        _isLoadingSubscriptions = false;
      });
      
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Paketler yüklenirken bir hata oluştu: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Diyet Yükle'),
      content: SizedBox(
        width: 400,
        height: 400,
        child:
            _hasParsedPreview ? _buildParsedContent() : _buildInitialContent(),
      ),
      actions: _hasParsedPreview
          ? _buildParsedButtons()
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'))
            ],
    );
  }
  
  /// Initial content with subscription dropdown and pick file button
  Widget _buildInitialContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Subscription display/selection
        if (_isLoadingSubscriptions)
          const Center(child: CircularProgressIndicator())
        else if (widget.selectedSubscription != null)
          // Display pre-selected subscription as non-editable
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seçili Paket:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedSubscription?.packageName ?? '',
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          // Show dropdown only if no pre-selected subscription
          DropdownButtonFormField<SubscriptionModel>(
            value: _selectedSubscription,
            decoration: const InputDecoration(
              labelText: 'Paket *',
              border: OutlineInputBorder(),
              hintText: 'Paket seçin',
            ),
            items: _subscriptions.map((sub) {
              return DropdownMenuItem<SubscriptionModel>(
                value: sub,
                child: Text(
                  sub.packageName,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedSubscription = value;
              });
            },
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _pickAndSaveFile,
          child: const Text('Dosya Seç ve İşle'),
        ),
      ],
    );
  }

  /// 2) Show a preview of parsed subtitles if we have them
  Widget _buildParsedContent() {
    if (_localFilePath == null) {
      return const Center(child: Text('Dosya seçilmedi.'));
    }

    // A scrollable ListView of subtitles
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Dosya kaydedildi: $_localFilePath'),
        ),
        // Show selected subscription
        if (_selectedSubscription != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Seçili paket: ${_selectedSubscription!.packageName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          // Use ScrollConfiguration to handle overflow properly
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              overscroll: false,
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: subtitles.length,
              itemBuilder: (context, index) {
                final subtitle = subtitles[index];
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${subtitle['name']} \t ${subtitle['time']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8.0),
                      if (subtitle['content'].isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            'İçerik bulunmamaktadır',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: MealFormatter.formatMealContentWithOptions(subtitle['content']),
                          ),
                        ),
                      const SizedBox(height: 16.0),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 3) Actions once we have preview: "Vazgeç" or "Onayla"
  List<Widget> _buildParsedButtons() {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context), // just close
        child: const Text('Vazgeç'),
      ),
      _isUploading
          ? const CircularProgressIndicator()
          : ElevatedButton(
              onPressed: _selectedSubscription == null 
                  ? null // Disable if no subscription selected
                  : _uploadContentToFirestore,
              child: const Text('Onayla'),
            ),
    ];
  }

  /// Replicates _pickAndSaveFile from FileHandlerPage, minus the user dropdown
  Future<void> _pickAndSaveFile() async {
    // No need to validate subscription as it's already pre-selected and shown to the user

    // Pull the latest admin-configured special lines so the docx parser knows
    // about every marker (built-in + admin) before it starts splitting lines.
    try {
      await Provider.of<SpecialLinesProvider>(context, listen: false)
          .fetchSpecialLines();
    } catch (e) {
      log.warn(
          'Could not load admin special lines, falling back to built-ins only: {}',
          [e]);
    }

    // Clear any old parse data
    for (var subtitle in subtitles) {
      subtitle['content'].clear();
      subtitle['time'] = '';
    }
    _localFilePath = null;
    _hasParsedPreview = false;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );

    if (result != null) {
      try {
        Uint8List? fileBytes = result.files.single.bytes;
        String fileName = result.files.single.name;
        // handleFile is from your file_handler.dart
        if (fileBytes != null) {
          await handleFile(
              fileBytes, fileName, _onFileProcessed, _onFileProcessingError);
        } else {
          log.warn(
              'fileBytes is null. cannot continue with handleFile method.');
          if(mounted) {
            DialogUtils.openError(context,
              title: 'Hata',
              message:
                  'Seçilen dosya ile ilgili bir problem oluştu. Lütfen destek talep ediniz.');
          }
        }
      } catch (e) {
        _onFileProcessingError(e.toString());
      }
    } else {
      log.info('File selection canceled.');
      if (mounted) {
        await _showSnackbar('Dosya seçimi iptal edildi.');
      }
    }
  }

  /// Called once file_handler.dart finishes reading the docx into plain text
  void _onFileProcessed(String text, String filePath) {
    setState(() {
      _localFilePath = filePath;
    });
    // Now parse the text into subtitles
    _extractSubtitles(text);
    // Show the preview
    setState(() {
      _hasParsedPreview = true;
    });
  }

  void _onFileProcessingError(String error) {
    log.err('Error processing file: {}', [error]);
    if (!mounted) return;
    DialogUtils.openError(
      context,
      title: 'Hata',
      message: 'Dosya işlenirken bir hata oluştu: $error',
    );
  }

  /// Whether [keyword] appears in [lowerLine] as a standalone word (Turkish
  /// letters are treated as word characters so the boundary check is accurate
  /// for Turkish text).
  ///
  /// With [atStart] true the keyword must be the FIRST word of the line. A meal
  /// header always leads with the meal name (e.g. "ARA (13.00) :"), so meal
  /// detection requires this stricter form. It is not enough for the keyword to
  /// merely appear somewhere as a word: the Turkish word "ara" can legitimately
  /// occur mid-sentence in food content (e.g. "2 saat ara verin"), and "ara" is
  /// also a substring of unrelated words like "şarap" (ş-ara-p). Anchoring to
  /// the start of the line ensures the whole leading word really is the meal
  /// name rather than an incidental match.
  ///
  /// With [atStart] false (the default) the keyword may appear anywhere as a
  /// whole word; used for the "öğün" exclusion that distinguishes a bare "Ara"
  /// header from "Ara Öğün N".
  bool _containsMealWord(String lowerLine, String keyword,
      {bool atStart = false}) {
    final escaped = RegExp.escape(keyword);
    final pattern = atStart
        ? '^$escaped(?![a-zçğıiöşü])'
        : '(?<![a-zçğıiöşü])$escaped(?![a-zçğıiöşü])';
    return RegExp(pattern, caseSensitive: false).hasMatch(lowerLine);
  }

  /// EXACT logic from your FileHandlerPage's _extractSubtitles
  void _extractSubtitles(String text) {
    log.info('text={}', [text]);

    final lines = text
        .split(RegExp(r'\r\n|\r|\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    // ----------------------------------------------------------------------
    // TEMP DIAGNOSTIC (remove after debugging). For every parsed line dumps:
    //   * exact characters with whitespace made visible,
    //   * raw codeUnits,
    //   * whether it is detected as a meal header (and which meal), and
    //   * what SpecialLinesRegistry.detect() returns (marker + content).
    //   » = TAB(0x09)  · = SPACE(0x20)  ⍽ = NBSP(0xA0)  ∅ = ZWSP(0x200B)
    //   \xNN = any other control char (shown by hex code)
    String visualize(String s) {
      final sb = StringBuffer();
      for (final r in s.runes) {
        switch (r) {
          case 0x09:
            sb.write('»');
            break;
          case 0x20:
            sb.write('·');
            break;
          case 0xA0:
            sb.write('⍽');
            break;
          case 0x200B:
            sb.write('∅');
            break;
          default:
            if (r < 0x20) {
              sb.write('\\x${r.toRadixString(16).padLeft(2, '0')}');
            } else {
              sb.writeCharCode(r);
            }
        }
      }
      return sb.toString();
    }

    String mealHit(String dl) {
      final low = dl.toLowerCase();
      if (_containsMealWord(low, 'sabah', atStart: true) ||
          _containsMealWord(low, 'kahvaltı', atStart: true)) return 'SABAH';
      if (_containsMealWord(low, 'öğle', atStart: true)) return 'ÖĞLE';
      if (_containsMealWord(low, 'akşam', atStart: true)) return 'AKŞAM';
      if (_containsMealWord(low, 'ara öğün 1', atStart: true)) {
        return 'ARA ÖĞÜN 1';
      }
      if (_containsMealWord(low, 'ara öğün 2', atStart: true)) {
        return 'ARA ÖĞÜN 2';
      }
      if (_containsMealWord(low, 'ara öğün 3', atStart: true)) {
        return 'ARA ÖĞÜN 3';
      }
      if (_containsMealWord(low, 'ara', atStart: true) &&
          !_containsMealWord(low, 'öğün')) return 'ARA(bare)';
      return '-';
    }

    log.info('[DIET-DIAG] Special markers loaded: {}',
        [SpecialLinesRegistry.all.map((c) => c.toTemplate()).join(' | ')]);
    for (int d = 0; d < lines.length; d++) {
      final dl = lines[d];
      final match = SpecialLinesRegistry.detect(dl);
      log.info(
          '[DIET-DIAG] LINE[{}] meal={} text="{}" | detect={} | codeUnits={}', [
        d,
        mealHit(dl),
        visualize(dl),
        match == null
            ? 'NONE'
            : 'marker="${match.markerLabel}" after="${visualize(match.contentAfter)}"',
        dl.codeUnits,
      ]);
    }
    // -------------------------- END TEMP DIAGNOSTIC --------------------------

    Map<String, dynamic>? currentSubtitle;
    
    // Create a map of meal types for better matching
    final mealMatchers = {
      'sabah': subtitles.firstWhere((s) => s['name'] == 'Sabah', orElse: () => {}),
      'ara öğün 1': subtitles.firstWhere((s) => s['name'] == 'Ara Öğün 1', orElse: () => {}),
      'öğle': subtitles.firstWhere((s) => s['name'] == 'Öğle', orElse: () => {}),
      'ara öğün 2': subtitles.firstWhere((s) => s['name'] == 'Ara Öğün 2', orElse: () => {}),
      'akşam': subtitles.firstWhere((s) => s['name'] == 'Akşam', orElse: () => {}),
      'ara öğün 3': subtitles.firstWhere((s) => s['name'] == 'Ara Öğün 3', orElse: () => {}),
    };

    // Track which meal we're on in sequence to help determine which "ARA" it is
    int mealSequence = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lowerLine = line.toLowerCase();
      
      Map<String, dynamic> foundSubtitle = {};
      
      // Check if this line matches a meal type. The meal name must be the FIRST
      // word of the line (see [_containsMealWord] with atStart) so that a
      // keyword buried inside another word (e.g. "ara" inside "şarap") or used
      // mid-sentence in content (e.g. "2 saat ara verin") never creates a
      // phantom meal. The "öğün" exclusion stays an anywhere check.
      if (_containsMealWord(lowerLine, 'sabah', atStart: true) ||
          _containsMealWord(lowerLine, 'kahvaltı', atStart: true)) {
        foundSubtitle = mealMatchers['sabah'] ?? {};
        mealSequence = 1;
      } else if (_containsMealWord(lowerLine, 'öğle', atStart: true)) {
        foundSubtitle = mealMatchers['öğle'] ?? {};
        mealSequence = 3;
      } else if (_containsMealWord(lowerLine, 'akşam', atStart: true)) {
        foundSubtitle = mealMatchers['akşam'] ?? {};
        mealSequence = 5;
      } else if (_containsMealWord(lowerLine, 'ara', atStart: true) &&
          !_containsMealWord(lowerLine, 'öğün')) {
        // Just "Ara" without a number - determine which one based on sequence
        switch (mealSequence) {
          case 1: // After Sabah
            foundSubtitle = mealMatchers['ara öğün 1'] ?? {};
            mealSequence = 2;
            break;
          case 3: // After Öğle
            foundSubtitle = mealMatchers['ara öğün 2'] ?? {};
            mealSequence = 4;
            break;
          case 5: // After Akşam
            foundSubtitle = mealMatchers['ara öğün 3'] ?? {};
            mealSequence = 6;
            break;
          default:
            // If sequence doesn't help, try finding first unused Ara
            if ((mealMatchers['ara öğün 1'] ?? {})['content']?.isEmpty ?? true) {
              foundSubtitle = mealMatchers['ara öğün 1'] ?? {};
              mealSequence = 2;
            } else if ((mealMatchers['ara öğün 2'] ?? {})['content']?.isEmpty ?? true) {
              foundSubtitle = mealMatchers['ara öğün 2'] ?? {};
              mealSequence = 4;
            } else {
              foundSubtitle = mealMatchers['ara öğün 3'] ?? {};
              mealSequence = 6;
            }
        }
      } else if (_containsMealWord(lowerLine, 'ara öğün 1', atStart: true)) {
        foundSubtitle = mealMatchers['ara öğün 1'] ?? {};
        mealSequence = 2;
      } else if (_containsMealWord(lowerLine, 'ara öğün 2', atStart: true)) {
        foundSubtitle = mealMatchers['ara öğün 2'] ?? {};
        mealSequence = 4;
      } else if (_containsMealWord(lowerLine, 'ara öğün 3', atStart: true)) {
        foundSubtitle = mealMatchers['ara öğün 3'] ?? {};
        mealSequence = 6;
      }

      if (foundSubtitle.isNotEmpty) {
        log.info('Found subtitle: {}', [foundSubtitle['name']]);
        currentSubtitle = foundSubtitle;

        // A meal-header line is expected to contain ONLY the meal name and its
        // time (e.g. "ÖĞLE (11.30) :"). By design we read just the time from
        // this line and do NOT treat any leftover text on it as food content.
        // So if a header arrives glued to a food item (e.g.
        // "ÖĞLE (11.30) :2 adet yumurta" — `docx_to_text` dropping the Word
        // <w:tab/> after the time), that trailing text is intentionally
        // ignored: the document is malformed and the item belongs on its own
        // line. This is not a bug; food items must start on the line after the
        // header.
        final timeMatch = RegExp(r'(\d{1,2}[:.](\d{2}))').firstMatch(line);
        if (timeMatch != null) {
          String timeStr = timeMatch.group(0)!;
          // Ensure consistent format with colon
          timeStr = timeStr.replaceAll('.', ':');
          currentSubtitle['time'] = timeStr;
          log.info('Extracted time for subtitle {}: {}',
              [currentSubtitle['name'], currentSubtitle['time']]);
        } else {
          // If no time found, try to extract just numbers that might represent time
          final numberMatch = RegExp(r'(\d{1,2})').firstMatch(line);
          if (numberMatch != null) {
            final hour = int.tryParse(numberMatch.group(0)!);
            if (hour != null && hour >= 0 && hour <= 23) {
              currentSubtitle['time'] = '$hour:00';
              log.info('Extracted hour for subtitle {}: {}',
                  [currentSubtitle['name'], currentSubtitle['time']]);
            }
          }
        }
      } else if (currentSubtitle != null) {
        // If we have an active subtitle, treat this line as content
        log.info('Adding content to subtitle {}: {}',
            [currentSubtitle['name'], line]);

        // Detect any configured special-line marker (Veya, Haftada X, plus
        // every admin-defined entry). Marker is stored as its own row so the
        // formatter can render it as a section divider; trailing content (if
        // any) is stored as the next regular row.
        final match = SpecialLinesRegistry.detect(line);
        if (match != null) {
          currentSubtitle['content'].add({'content': match.markerLabel});
          if (match.contentAfter.isNotEmpty) {
            currentSubtitle['content'].add({'content': match.contentAfter});
          }
        } else {
          currentSubtitle['content'].add({'content': line});
        }
      }
    }

    // Check if we found any content
    bool foundAnyContent = false;
    for (var subtitle in subtitles) {
      if ((subtitle['content'] as List).isNotEmpty) {
        foundAnyContent = true;
        break;
      }
    }

    if (!foundAnyContent) {
      log.warn('No content found in parsed document');
    }
  }

  /// Modified to use DietProvider instead of direct Firestore operations
  Future<void> _uploadContentToFirestore() async {
    if (_selectedSubscription == null) {
      await DialogUtils.openError(
        context,
        title: 'Uyarı',
        message: 'Lütfen bir paket seçiniz.',
      );
      return;
    }
    
    setState(() {
      _isUploading = true;
    });
    
    try {
      // Convert subtitles list to map format expected by the provider
      final Map<String, dynamic> subtitlesMap = {};
      
      // Loop through each subtitle and build the correct structure
      for (var subtitle in subtitles) {
        final mealName = subtitle['name']; // Display name
        
        // Find the corresponding Meals enum for this name
        String enumKey = '';
        try {
          // Try to find the enum by matching label
          for (var meal in Meals.dietValues) {
            if (meal.label == mealName) {
              enumKey = meal.name;
              break;
            }
          }
          
          // If not found by label, use a fallback matching approach
          if (enumKey.isEmpty) {
            final lowerName = mealName.toLowerCase();
            if (lowerName.contains('sabah')) {
              enumKey = Meals.br.name;
            } else if (lowerName.contains('öğle')) {
              enumKey = Meals.lunch.name;
            } else if (lowerName.contains('akşam')) {
              enumKey = Meals.dinner.name;
            } else if (lowerName.contains('ara') && lowerName.contains('1')) {
              enumKey = Meals.firstmid.name;
            } else if (lowerName.contains('ara') && lowerName.contains('2')) {
              enumKey = Meals.secondmid.name;
            } else if (lowerName.contains('ara') && lowerName.contains('3')) {
              enumKey = Meals.thirdmid.name;
            }
          }
        } catch (e) {
          log.warn('Error finding enum for meal: {} - {}', [mealName, e]);
        }
        
        // If we still don't have an enum key, skip this entry
        if (enumKey.isEmpty) {
          log.warn('Could not find enum key for meal: {}', [mealName]);
          continue;
        }
        
        // Format content items correctly
        List<Map<String, dynamic>> formattedContent = [];
        for (var item in subtitle['content']) {
          if (item is Map) {
            formattedContent.add(Map<String, dynamic>.from(item));
          } else {
            formattedContent.add({'content': item.toString()});
          }
        }
        
        // Add the properly structured entry
        subtitlesMap[enumKey] = {
          'time': subtitle['time'],
          'content': formattedContent,
        };
      }

      // Use DietProvider to upload the diet
      final dietProvider = Provider.of<DietProvider>(context, listen: false);
      final String? docId = await dietProvider.uploadDiet(
        userId: widget.userId,
        subtitles: subtitlesMap,
        subscriptionId: _selectedSubscription!.subscriptionId,
      );

      // Check if widget is still mounted before updating state
      if (!mounted) return;
      
      setState(() {
        _isUploading = false;
      });

      if (docId != null) {
        log.info('Diet list uploaded with ID: {}', [docId]);
        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Diyet listesi başarıyla yüklendi.',
        );
        if (mounted) {
          Navigator.pop(context); // Close dialog
        }
      } else {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Diyet listesi yüklenemedi.',
        );
      }
    } catch (e) {
      // Check if widget is still mounted before updating state
      if (!mounted) return;
      
      setState(() {
        _isUploading = false;
      });
      
      log.err('Error uploading diet list: {}', [e.toString()]);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Diyet listesi yüklenirken bir hata oluştu: $e',
      );
    }
  }

  /// Helper for user feedback
  Future<void> _showSnackbar(String message) async {
    if (!mounted) return;
    await DialogUtils.openInfo(
      context,
      title: 'Bilgi',
      message: message,
    );
  }
}
