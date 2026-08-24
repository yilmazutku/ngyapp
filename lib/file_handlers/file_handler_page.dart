import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/user_model.dart';
import '../models/subs_model.dart';
import '../providers/diet_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/meal_formatter.dart';
import 'delete_file_mobile.dart';
import 'file_handler.dart'; // New conditional import
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/labeled_action_button.dart';

final Logger log = Logger.forClass(FileHandlerPage);

/*
Suggested Improvements:
- Added more robust error handling in _parseFileContent and _extractSubtitles.
- Added user feedback using Snackbar when the user forgets to select a user or when file selection is canceled.
*/

class FileHandlerPage extends StatefulWidget {
  const FileHandlerPage({super.key});

  @override
  createState() => _FileHandlerPageState();
}

class _FileHandlerPageState extends State<FileHandlerPage> {
  String? _localFilePath;
  List<Map<String, dynamic>> subtitles = [];

  Map<String, String> _userMap =
      {}; // Store userId as key and userName as value
  String? _selectedUser;
  SubscriptionModel? _selectedSubscription;
  List<SubscriptionModel> _subscriptions = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    for (var meal in Meals.dietValues) {
      subtitles.add({
        'name': meal.label,
        'enumName': meal.name,
        'time': meal.defaultTime,
        'content': [],
      });
    }
    _fetchUserList();
  }

  @override
  Widget build(BuildContext context) {
    log.info('Building file handler page..');
    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Diyet Listeleri Yöneticisi',
        actions: [
          LabeledActionButton(
            icon: Icons.upload_file,
            label: 'JSON Yükle',
            tooltip: 'JSON Dosya Yükle',
            onPressed: () => _showExportDialog(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _userDropdown(), // Dropdown to select user
            if (_selectedUser != null) 
              _subscriptionDropdown(), // Show subscription dropdown if user is selected
            ElevatedButton(
              onPressed: _isUploading ? null : _pickAndSaveFile,
              child: _isUploading 
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('Yükleniyor...'),
                    ],
                  )
                : const Text('Dosya Seç ve İşle'),
            ),
            const SizedBox(height: 20),
            _localFilePath != null
                ? Text('Dosya kaydedildi: $_localFilePath')
                : const Text('Dosya seçilmedi.'),
            const SizedBox(height: 20),
            _buildParsedContent(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _deleteFile,
              child: const Text('Dosyayı Sil'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('JSON Dosya Yükleme'),
        content: const Text(
            'Bu özellik henüz tamamlanmadı. Gelecek güncellemede kullanıma sunulacaktır.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _userDropdown() {
    return DropdownButton<String>(
      value: _selectedUser,
      hint: const Text('Kullanıcı Seçin'),
      onChanged: (String? newValue) {
        setState(() {
          _selectedUser = newValue; // newValue will be the user ID
          _selectedSubscription = null; // Reset subscription when user changes
        });
        
        if (newValue != null) {
          _fetchSubscriptions(newValue);
        }
      },
      items: _userMap.entries.map<DropdownMenuItem<String>>((entry) {
        return DropdownMenuItem<String>(
          value: entry.key, // Use user ID as value
          child: Text(entry.value), // Display user name
        );
      }).toList(),
    );
  }

  Widget _subscriptionDropdown() {
    if (_subscriptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('Kullanıcının aktif paketi bulunmamaktadır'),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButton<SubscriptionModel>(
        value: _selectedSubscription,
        hint: const Text('Paket Seçin'),
        onChanged: (SubscriptionModel? newValue) {
          setState(() {
            _selectedSubscription = newValue;
          });
        },
        items: _subscriptions.map<DropdownMenuItem<SubscriptionModel>>((sub) {
          return DropdownMenuItem<SubscriptionModel>(
            value: sub,
            child: Text(sub.packageName),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildParsedContent() {
    if (_localFilePath == null) return Container();

    return Expanded(
      child: ListView.builder(
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
    );
  }

  /// Fetch user list from Cloud Firestore
  Future<void> _fetchUserList() async {
    try {
      final QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('users').get();
      final List<QueryDocumentSnapshot> documents = querySnapshot.docs;

      setState(() {
        _userMap = {
          for (var doc in documents) doc.id: UserModel.fromDocument(doc).name
        };
      });

      log.info('Fetched user list: {}', [_userMap]);
    } catch (e) {
      log.err('Error fetching user list: {}', [e.toString()]);
      _showSnackbar('Kullanıcı listesi yüklenirken hata oluştu.');
    }
  }

  /// Fetch subscriptions for the selected user
  Future<void> _fetchSubscriptions(String userId) async {
    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final List<SubscriptionModel> activeSubscriptions = 
        await subProvider.fetchSubscriptions(
          userId: userId,
          showAllSubscriptions: false, // Only active subscriptions
        );
      
      if (mounted) {
        setState(() {
          _subscriptions = activeSubscriptions;
          // Auto-select the first subscription if available
          _selectedSubscription = 
            activeSubscriptions.isNotEmpty ? activeSubscriptions.first : null;
        });
      }
      
      log.info('Fetched {} subscriptions for user {}', 
        [activeSubscriptions.length, userId]);
        
      if (activeSubscriptions.isEmpty && mounted) {
        await DialogUtils.openInfo(
          context,
          title: 'Bilgi',
          message: 'Bu kullanıcının aktif paketi bulunmamaktadır. Diyet yüklemek için önce bir paket ekleyin.',
        );
      }
    } catch (e) {
      log.err('Error fetching subscriptions: {}', [e.toString()]);
      if (mounted) {
        _showSnackbar('Paketler yüklenirken hata oluştu.');
      }
    }
  }

  /// Step 2: Pick a file, save it to a temporary local directory, and parse it
  Future<void> _pickAndSaveFile() async {
    if (_selectedUser == null) {
      log.warn('Please select a user first.');
      _showSnackbar('Lütfen önce bir kullanıcı seçin.');
      return;
    }
    
    if (_selectedSubscription == null) {
      log.warn('Please select a subscription first.');
      _showSnackbar('Lütfen önce bir paket seçin.');
      return;
    }
    
    for (var subtitle in subtitles) {
      subtitle['content'].clear(); // Clear the content list
      subtitle['time'] = '-'; // Reset the time field
    }

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
      }  catch (e) {
        _onFileProcessingError(e.toString());
      }
    } else {
      log.info('File selection canceled.');
      _showSnackbar('Dosya seçimi iptal edildi.');
    }
  }

  void _onFileProcessed(String text, String filePath) {
    setState(() {
      _localFilePath = filePath;
    });
    _extractSubtitles(text);
    _uploadContentToFirestore();
  }

  void _onFileProcessingError(String error) {
    log.err('Error processing file: {}', [error]);
    _showSnackbar('Dosya işlenirken hata oluştu: $error');
  }

  void _extractSubtitles(String text) {
    log.info('============ PARSING DEBUG START ============');
    log.info('Text length: {}', [text.length]);
    // Log the first 1000 characters to see the document structure
    log.info('Text preview: {}', [text.length > 1000 ? '${text.substring(0, 1000)}...' : text]);
    
    // Split the text into lines and clean it
    final lines = text
        .split(RegExp(r'\r\n|\r|\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    
    log.info('Extracted {} lines from document', [lines.length]);
    // Log all lines for detailed analysis
    for (int i = 0; i < lines.length; i++) {
      log.info('Line {}: {}', [i, lines[i]]);
    }
    
    // Log all meal types we're looking for
    log.info('Searching for these meal types:');
    for (var meal in Meals.dietValues) {
      log.info('- {} ({})', [meal.name, meal.label]);
    }
    
    Map<String, dynamic>? currentSubtitle;
    
    for (var line in lines) {
      log.info('Processing line: {}', [line]);

      // Check if this line starts a new meal section
      bool foundMealSection = false;
      
      // For non-Ara meals (direct matching)
      for (var meal in Meals.dietValues) {
        if (meal != Meals.firstmid && meal != Meals.secondmid && meal != Meals.thirdmid) {
          // Case insensitive check
          if (line.toLowerCase().contains(meal.label.toLowerCase())) {
            log.info('MATCH FOUND: "{}" contains "{}"', [line, meal.label]);
            
            // Find the corresponding subtitle in our list
            var foundSubtitle = subtitles.firstWhere(
              (subtitle) => subtitle['name'] == meal.label,
              orElse: () => {},
            );
            
            if (foundSubtitle.isNotEmpty) {
              currentSubtitle = foundSubtitle;
              
              // Extract time
              final timeMatch = RegExp(r'(\d{1,2}[:.](\d{2}))').firstMatch(line);
              if (timeMatch != null) {
                String timeStr = timeMatch.group(0)!;
                // Ensure consistent format with colon
                timeStr = timeStr.replaceAll('.', ':');
                currentSubtitle['time'] = timeStr;
              }
              
              log.info('Extracted time for subtitle {}: {}',
                  [currentSubtitle['name'], currentSubtitle['time']]);
              
              foundMealSection = true;
              break;
            }
          }
        }
      }
      
      // If we didn't find a non-Ara meal, check for "Ara"
      if (!foundMealSection) {
        // Case insensitive check for "Ara"
        if (line.toLowerCase().contains("ara")) {
          log.info('MATCH FOUND: "Ara" in line: {}', [line]);
          
          // Get time if present to determine which Ara meal
          final timeMatch = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(line);
          int hour = 0;
          if (timeMatch != null) {
            hour = int.parse(timeMatch.group(1)!);
          }
          
          // Choose appropriate Ara meal based on time or sequence
          var araSubtitle = {};
          if (hour > 0 && hour <= 12) {
            // Morning
            araSubtitle = subtitles.firstWhere(
              (subtitle) => subtitle['name'] == 'Ara Öğün 1',
              orElse: () => {},
            );
          } else if (hour > 12 && hour <= 18) {
            // Afternoon
            araSubtitle = subtitles.firstWhere(
              (subtitle) => subtitle['name'] == 'Ara Öğün 2',
              orElse: () => {},
            );
          } else if (hour > 18) {
            // Evening
            araSubtitle = subtitles.firstWhere(
              (subtitle) => subtitle['name'] == 'Ara Öğün 3',
              orElse: () => {},
            );
          } else {
            // If no time found, find first unused Ara meal
            araSubtitle = subtitles.firstWhere(
              (subtitle) => subtitle['name'].toLowerCase().contains("ara") && subtitle['content'].isEmpty,
              orElse: () => {},
            );
          }
          
          if (araSubtitle.isNotEmpty) {
            currentSubtitle = araSubtitle.cast<String, dynamic>();
            
            // Extract time from line if present
            final timeMatch = RegExp(r'(\d{1,2}[:.](\d{2}))').firstMatch(line);
            if (timeMatch != null) {
              String timeStr = timeMatch.group(0)!;
              // Ensure consistent format with colon
              timeStr = timeStr.replaceAll('.', ':');
              currentSubtitle['time'] = timeStr;
            }
            
            log.info('Selected Ara subtitle: {} with time {}', 
              [currentSubtitle['name'], currentSubtitle['time']]);
            
            foundMealSection = true;
          }
        }
      }
      
      // If we have a current subtitle, add content to it
      if (currentSubtitle != null && !foundMealSection) {
        log.info('Adding content to subtitle {}: {}', 
          [currentSubtitle['name'], line]);
        
        // Check if this line starts with "Veya" followed by whitespace (tab)
        // Use the same RegExp pattern from meal_formatter.dart
        if (line.trim().startsWith(VEYA_MARKER) || VEYA_OPTION_SEPARATOR_REGEX.hasMatch(line)) {
          // Add the exact line to preserve the "Veya" marker and spacing
          currentSubtitle['content'].add({'content': line});
          log.info('Added VEYA separator: {}', [line]);
        } else {
          // Regular content line
          currentSubtitle['content'].add({'content': line});
        }
      }
    }
    
    log.info('============ PARSING DEBUG END ============');
    
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
    } else {
      log.info('Successfully parsed document with content');
    }
  }

  /// Updated Step 4: Upload the parsed content using DietProvider
  Future<void> _uploadContentToFirestore() async {
    if (_selectedUser == null) {
      log.warn('No user selected for upload.');
      _showSnackbar('Lütfen önce bir kullanıcı seçin.');
      return;
    }
    
    if (_selectedSubscription == null) {
      log.warn('No subscription selected for upload.');
      _showSnackbar('Lütfen önce bir paket seçin.');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      Map<String, dynamic> subtitleData = {};

      // Format the data correctly for the Diet structure expected by the app
      for (var subtitle in subtitles) {
        // Use enum name as the key instead of label
        final enumName = subtitle['enumName'] as String;
        
        // Ensure content list is properly formatted
        List<Map<String, dynamic>> formattedContent = [];
        for (var item in subtitle['content']) {
          if (item is Map) {
            formattedContent.add({...Map<String, dynamic>.from(item)});
          } else {
            formattedContent.add({'content': item.toString()});
          }
        }
        
        subtitleData[enumName] = {
          'time': subtitle['time'],
          'content': formattedContent,
        };
      }

      // Use the DietProvider for Firebase operations
      final dietProvider = Provider.of<DietProvider>(context, listen: false);
      final String? docId = await dietProvider.uploadDiet(
        userId: _selectedUser!,
        subtitles: subtitleData,
        subscriptionId: _selectedSubscription!.subscriptionId,
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }

      if (docId != null) {
        log.info('Diet list uploaded with ID: {}', [docId]);
        if (mounted) {
          await DialogUtils.openInfo(
            context,
            title: 'Başarılı',
            message: 'Diyet listesi başarıyla yüklendi.',
          );
          
          // Refresh UI by clearing the form after successful upload
          setState(() {
            for (var subtitle in subtitles) {
              subtitle['content'].clear();
              subtitle['time'] = subtitle['name'] == 'Sabah' ? '08:00' : 
                               subtitle['name'] == 'Öğle' ? '13:00' : 
                               subtitle['name'] == 'Akşam' ? '19:00' : '';
            }
            _localFilePath = null;
          });
        }
      } else {
        log.err('Failed to upload diet list, docId is null');
        if (mounted) {
          _showSnackbar('Diyet listesi yüklenirken bir hata oluştu.');
        }
      }
    } catch (e) {
      log.err('Error uploading diet list: {}', [e.toString()]);
      
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        _showSnackbar('Diyet listesi yüklenirken bir hata oluştu: $e');
      }
    }
  }

  /// Step 5: Delete the file from the temporary directory
  Future<void> _deleteFile() async {
    if (_localFilePath != null) {
      try {
        await deleteFile(_localFilePath!);
        log.info('File deleted.');

        setState(() {
          _localFilePath = null;
          // Clear subtitles
          for (var subtitle in subtitles) {
            subtitle['content'].clear();
            subtitle['time'] = ''; // Reset time
          }
        });

        _showSnackbar('Dosya başarıyla silindi.');
      } catch (e) {
        log.err('Error deleting file: {}', [e.toString()]);
        _showSnackbar('Dosya silinirken bir hata oluştu: ${e.toString()}');
      }
    } else {
      _showSnackbar('Silinecek dosya yok.');
    }
  }

  /// Helper method to show Snackbars for user feedback
  Future<void> _showSnackbar(String message) async {
    await DialogUtils.openInfo(
      context,
      title: 'Bilgi',
      message: message,
    );
  }
}

