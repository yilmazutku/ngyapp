import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/diet_model.dart';
import '../models/logger.dart';
import '../providers/diet_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/meal_formatter.dart';
import '../widgets/app_bar_with_back.dart';
import '../models/meal_model.dart';

// Import the constants from meal_formatter.dart

class DietEditPage extends StatefulWidget {
  final String userId;
  final DietDocument dietDoc;
  final bool viewOnly;  // Parameter to control view/edit mode
  final bool isNewDiet; // New parameter to indicate a new diet

  const DietEditPage({
    super.key,
    required this.userId,
    required this.dietDoc,
    this.viewOnly = false,  // Default to edit mode
    this.isNewDiet = false, // Default to existing diet
  });

  @override
  createState() => _DietEditPageState();
}

class _DietEditPageState extends State<DietEditPage> {
  final Logger logger = Logger.forClass(DietEditPage);
  late Map<String, dynamic> _editableData;
  bool _isLoading = false;
  bool _hasChanges = false;
  late final ScrollController _scrollController;
  late String _dietName; // Add a field for the editable diet name

  @override
  void initState() {
    super.initState();
    // Create a deep copy of the subtitles data to edit
    _editableData = _deepCopy(widget.dietDoc.subtitles);
    // Initialize scroll controller
    _scrollController = ScrollController();
    // Initialize diet name
    _dietName = widget.dietDoc.displayName;
    
    // If it's a new diet, mark it as having changes
    if (widget.isNewDiet) {
      _hasChanges = true;
    }
  }

  @override
  void dispose() {
    // Dispose scroll controller
    _scrollController.dispose();
    super.dispose();
  }

  // Helper to create a deep copy of the data structure
  Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    Map<String, dynamic> result = {};

    source.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        Map<String, dynamic> mealData = {};

        value.forEach((mealKey, mealValue) {
          if (mealKey == 'content' && mealValue is List) {
            // Deep copy the content list
            List<Map<String, dynamic>> contentCopy = [];

            for (var item in mealValue) {
              if (item is Map) {
                contentCopy.add({...Map<String, dynamic>.from(item)});
              } else {
                contentCopy.add({'content': item.toString()});
              }
            }

            mealData[mealKey] = contentCopy;
          } else {
            mealData[mealKey] = mealValue;
          }
        });

        result[key] = mealData;
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    // Sort meals by enum order instead of time
    List<MapEntry<String, dynamic>> sortedMeals =
        _editableData.entries.toList();
    sortedMeals.sort((a, b) {
      try {
        // Try to get the enum indices for proper sorting
        final aMeal = Meals.values.indexWhere((meal) => meal.name == a.key);
        final bMeal = Meals.values.indexWhere((meal) => meal.name == b.key);
        
        // If both are valid enum values, sort by enum order
        if (aMeal >= 0 && bMeal >= 0) {
          return aMeal.compareTo(bMeal);
        }
        
        // If only one is a valid enum value, prioritize it
        if (aMeal >= 0) return -1;
        if (bMeal >= 0) return 1;
        
        // Fallback to comparing keys if neither is a valid enum
        return a.key.compareTo(b.key);
      } catch (e) {
        // Fallback to comparing keys in case of any error
        return a.key.compareTo(b.key);
      }
    });

    // Determine the appropriate title
    String pageTitle;
    if (widget.isNewDiet) {
      pageTitle = 'Yeni Diyet Ekle';
    } else if (widget.viewOnly) {
      pageTitle = _dietName;
    } else {
      pageTitle = 'Düzenle: $_dietName';
    }

    return Scaffold(
      appBar: AppBarWithBack(
        title: pageTitle,
        actions: [
          // Only show edit controls if not in view-only mode
          if (!widget.viewOnly) ...[
            // Add meal button
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddMealDialog,
              tooltip: 'Öğün Ekle',
            ),
            // Save button
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _hasChanges ? _saveDiet : null,
                    tooltip: 'Kaydet',
                  ),
          ],
          // Share button (available in both modes)
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share functionality - can be implemented later
              DialogUtils.openError(
                context,
                title: 'Bilgi',
                message: 'Paylaşım özelliği henüz aktif değil.',
              );
            },
            tooltip: 'Paylaş',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              color: Colors.grey[50],
              // Use ScrollConfiguration to handle scrolling behavior
              child: ScrollConfiguration(
                // Behavior that removes glow effect but keeps physics
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  overscroll: false,
                ),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Diet name editor card (only in edit mode)
                    if (!widget.viewOnly)
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.edit_note,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Diyet Adı',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Edit diet name button
                                  TextButton.icon(
                                    onPressed: _editDietName,
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('Düzenle'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _dietName,
                                style: const TextStyle(
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Meals list
                    ...List.generate(sortedMeals.length, (index) {
                      final mealEntry = sortedMeals[index];
                      final mealName = mealEntry.key;
                      final mealData = mealEntry.value as Map<String, dynamic>;
                      
                      return _buildMealCard(mealName, mealData);
                    }),
                  ],
                ),
              ),
            ),
      // No floating action button in view mode
      floatingActionButton: !widget.viewOnly
          ? FloatingActionButton.extended(
              onPressed: _hasChanges ? _saveDiet : null,
              icon: const Icon(Icons.save),
              label: const Text('Kaydet'),
              backgroundColor: _hasChanges ? Colors.blue : Colors.grey,
            )
          : null,
    );
  }

  Widget _buildMealCard(String mealName, Map<String, dynamic> mealData) {
    // Extract meal time and content
    final time = mealData['time'] as String? ?? '';
    final contentList = mealData['content'] as List<dynamic>? ?? [];
    
    // Get display name for the meal
    final displayName = getMealDisplayName(mealName);

    // Controllers for time editing
    final timeController = TextEditingController(text: time);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Meal header with name, time editor, and delete button
            Row(
              children: [
                // Meal name with edit option (only in edit mode)
                Expanded(
                  child: widget.viewOnly
                  ? Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            _getMealIcon(mealName),
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    )
                  : InkWell(
                    onTap: () => _editMealName(mealName),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            _getMealIcon(mealName),
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Time display/editor (editable only in edit mode)
                widget.viewOnly
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : InkWell(
                  onTap: () => _editMealTime(mealName, time),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                // Delete meal button (only in edit mode)
                if (!widget.viewOnly)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDeleteMeal(mealName),
                    tooltip: 'Öğünü Sil',
                  ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Replace the existing meal content items with formatted options
            if (contentList.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Bu öğün için içerik bulunmamaktadır',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              widget.viewOnly
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: MealFormatter.formatMealContentWithOptions(contentList),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildEditableContentItems(mealName, contentList),
                  ),

            // Add content item button (only in edit mode)
            if (!widget.viewOnly) ...[
              if (contentList.isNotEmpty) const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _addContentItem(mealName),
                          icon: const Icon(Icons.add),
                          label: const Text('İçerik Ekle'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _addVeyaContentItem(mealName),
                          icon: const Icon(Icons.sync_alt),
                          label: const Text('Veya Satırı Ekle'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => _addHaftadaContentItem(mealName),
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Haftada X Ekle'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Edit meal name
  void _editMealName(String mealName) {
    // Get current display name
    final displayName = getMealDisplayName(mealName);
    
    // Get all meal enums not already in use
    final existingMealNames = _editableData.keys.toList();
    final availableMeals = Meals.dietValues.where((meal) => 
      !existingMealNames.contains(meal.name) || meal.name == mealName).toList();
    
    // Find the current meal enum
    Meals? selectedMeal;
    try {
      selectedMeal = Meals.values.firstWhere((meal) => meal.name == mealName);
    } catch (e) {
      // If not found, provide the first available meal
      selectedMeal = availableMeals.isNotEmpty ? availableMeals.first : null;
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Öğün Adını Düzenle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Meals>(
                  value: selectedMeal,
                  decoration: const InputDecoration(
                    labelText: 'Öğün Tipi',
                    border: OutlineInputBorder(),
                  ),
                  items: availableMeals.map((meal) {
                    return DropdownMenuItem<Meals>(
                      value: meal,
                      child: Text(meal.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMeal = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedMeal != null && selectedMeal!.name != mealName) {
                    setState(() {
                      // Create a copy with the new name
                      final mealData = <String, dynamic>{..._editableData[mealName]!};
                      // Remove the old entry
                      _editableData.remove(mealName);
                      // Add with the new key (using enum name)
                      _editableData[selectedMeal!.name] = mealData;
                      _hasChanges = true;
                    });
                    Navigator.pop(context);
                  } else {
                    // No change or same name selected
                    Navigator.pop(context);
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Edit meal time
  void _editMealTime(String mealName, String currentTime) {
    final TextEditingController controller =
        TextEditingController(text: currentTime);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Öğün Saatini Düzenle'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Saat (ÖR: 08:00)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
              autofocus: true,
              onChanged: (value) {
                // Update dialog UI immediately when text changes
                setDialogState(() {});
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  final newTime = controller.text.trim();
                  Navigator.pop(context);

                  if (newTime != currentTime) {
                    setState(() {
                      _editableData[mealName]['time'] = newTime;
                      _hasChanges = true;
                    });
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        }
      ),
    );
  }

  // Edit content item
  void _editContentItem(String mealName, int index, String currentContent) {
    final TextEditingController controller =
        TextEditingController(text: currentContent);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('İçeriği Düzenle'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'İçerik',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (value) {
                // Update dialog UI immediately when text changes
                setDialogState(() {});
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: controller.text.trim().isEmpty ? null : () {
                  final newContent = controller.text.trim();
                  Navigator.pop(context);

                  if (newContent != currentContent) {
                    setState(() {
                      final contentList = _editableData[mealName]['content'] as List;
                      
                      // Check if this is a multiline edit
                      if (newContent.contains('\n')) {
                        // Remove the current item
                        contentList.removeAt(index);
                        
                        // Parse the content for multiple lines and check for "veya" separators
                        final lines = newContent.split('\n');
                        bool firstLine = true;
                        int insertIndex = index;
                        
                        for (String line in lines) {
                          final trimmedLine = line.trim();
                          if (trimmedLine.isEmpty) continue;
                          
                                                // Check for any of our special markers at the start of the line
                      bool isSpecialMarker = false;
                      
                      // Check for Veya marker
                      if (!firstLine && trimmedLine.toLowerCase().startsWith(VEYA_MARKER.toLowerCase())) {
                        // Add a standalone "Veya" marker first
                        contentList.insert(insertIndex, {'content': VEYA_MARKER});
                        insertIndex++;
                        
                        // Then add the content after "veya" if there is any
                        final contentAfterVeya = trimmedLine.substring(VEYA_MARKER.length).trim();
                        if (contentAfterVeya.isNotEmpty) {
                          contentList.insert(insertIndex, {'content': contentAfterVeya});
                          insertIndex++;
                        }
                        isSpecialMarker = true;
                      } 
                      // Check for Haftada X marker
                      else if (!firstLine && trimmedLine.toLowerCase().startsWith(HAFTADA_MARKER_PREFIX.toLowerCase())) {
                        // Try to extract the number X from "Haftada X"
                        final match = RegExp(r'^Haftada\s+(\d+)').firstMatch(trimmedLine);
                        if (match != null && match.groupCount >= 1) {
                          final number = match.group(1);
                          final markerText = '$HAFTADA_MARKER_PREFIX $number';
                          
                          // Add the "Haftada X" marker
                          contentList.insert(insertIndex, {'content': markerText});
                          insertIndex++;
                          
                          // Then add any content after "Haftada X" if there is any
                          final contentAfterMarker = trimmedLine.substring(match.end).trim();
                          if (contentAfterMarker.isNotEmpty) {
                            contentList.insert(insertIndex, {'content': contentAfterMarker});
                            insertIndex++;
                          }
                          isSpecialMarker = true;
                        }
                      }
                      
                      // If not a special marker, treat as regular content
                      if (!isSpecialMarker) {
                            // Regular content line
                            contentList.insert(insertIndex, {'content': trimmedLine});
                            insertIndex++;
                          }
                          
                          firstLine = false;
                        }
                      } else {
                        // Simple single-line edit
                        contentList[index] = {'content': newContent};
                      }
                      
                      _hasChanges = true;
                    });
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        }
      ),
    );
  }

  // Delete content item
  void _deleteContentItem(String mealName, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İçeriği Sil'),
        content:
            const Text('Bu içerik öğesini silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                final contentList = _editableData[mealName]['content'] as List;
                contentList.removeAt(index);
                _hasChanges = true;
              });
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // Add new content item
  void _addContentItem(String mealName) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('İçerik Ekle'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'İçerik',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (value) {
                // Update dialog UI immediately when text changes
                setDialogState(() {});
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: controller.text.trim().isEmpty ? null : () {
                  final content = controller.text.trim();
                  if (content.isEmpty) {
                    DialogUtils.openError(
                      context,
                      title: 'Hata',
                      message: 'İçerik boş olamaz.',
                    );
                    return;
                  }

                  Navigator.pop(context);
                  setState(() {
                    final contentList = _editableData[mealName]['content'] as List;
                    
                    // Parse the content for multiple lines and check for "veya" separators
                    final lines = content.split('\n');
                    bool firstLine = true;
                    
                    for (String line in lines) {
                      final trimmedLine = line.trim();
                      if (trimmedLine.isEmpty) continue;
                      
                      // Check for any of our special markers at the start of the line
                      bool isSpecialMarker = false;
                      
                      // Check for Veya marker
                      if (!firstLine && trimmedLine.toLowerCase().startsWith(VEYA_MARKER.toLowerCase())) {
                        // Add a standalone "Veya" marker first
                        contentList.add({'content': VEYA_MARKER});
                        
                        // Then add the content after "veya" if there is any
                        final contentAfterVeya = trimmedLine.substring(VEYA_MARKER.length).trim();
                        if (contentAfterVeya.isNotEmpty) {
                          contentList.add({'content': contentAfterVeya});
                        }
                        isSpecialMarker = true;
                      } 
                      // Check for Haftada X marker
                      else if (!firstLine && trimmedLine.toLowerCase().startsWith(HAFTADA_MARKER_PREFIX.toLowerCase())) {
                        // Try to extract the number X from "Haftada X"
                        final match = RegExp(r'^Haftada\s+(\d+)').firstMatch(trimmedLine);
                        if (match != null && match.groupCount >= 1) {
                          final number = match.group(1);
                          final markerText = '$HAFTADA_MARKER_PREFIX $number';
                          
                          // Add the "Haftada X" marker
                          contentList.add({'content': markerText});
                          
                          // Then add any content after "Haftada X" if there is any
                          final contentAfterMarker = trimmedLine.substring(match.end).trim();
                          if (contentAfterMarker.isNotEmpty) {
                            contentList.add({'content': contentAfterMarker});
                          }
                          isSpecialMarker = true;
                        }
                      }
                      
                      // If not a special marker, treat as regular content
                      if (!isSpecialMarker) {
                        // Regular content line
                        contentList.add({'content': trimmedLine});
                      }
                      
                      firstLine = false;
                    }
                    
                    _hasChanges = true;
                  });
                },
                child: const Text('Ekle'),
              ),
            ],
          );
        }
      ),
    );
  }

  // Show add meal dialog
  void _showAddMealDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController timeController = TextEditingController(text: '12:00');
    
    // Get enum names that aren't already in the diet
    final existingMealNames = _editableData.keys.toList();
    final availableMeals = Meals.dietValues.where((meal) => 
      !existingMealNames.contains(meal.name)).toList();
    
    if (availableMeals.isEmpty) {
      // All meal types are already added
      DialogUtils.openInfo(
        context,
        title: 'Bilgi',
        message: 'Tüm öğün tipleri eklenmiş. Yeni öğün eklemek için önce mevcut bir öğünü silmelisiniz.',
      );
      return;
    }
    
    // Default to the first available meal
    Meals? selectedMeal = availableMeals.isNotEmpty ? availableMeals.first : null;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Öğün Ekle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Meal selection dropdown
                DropdownButtonFormField<Meals>(
                  value: selectedMeal,
                  decoration: const InputDecoration(
                    labelText: 'Öğün Tipi',
                    border: OutlineInputBorder(),
                  ),
                  items: availableMeals.map((meal) {
                    return DropdownMenuItem<Meals>(
                      value: meal,
                      child: Text(meal.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMeal = value;
                      timeController.text = value?.defaultTime ?? '12:00';
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Time input
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: 'Saat',
                    border: OutlineInputBorder(),
                    hintText: 'HH:MM',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedMeal != null) {
                    setState(() {
                      // Create a new meal in the data structure using the enum name as the key
                      _editableData[selectedMeal!.name] = {
                        'time': timeController.text,
                        'content': [],
                      };
                      _hasChanges = true;
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Ekle'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Confirm delete meal
  void _confirmDeleteMeal(String mealName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Öğünü Sil'),
        content: Text('$mealName öğününü silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _editableData.remove(mealName);
                _hasChanges = true;
              });
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // Save diet using DietProvider instead of direct Firestore operations
  Future<void> _saveDiet() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the diet provider
      final dietProvider = Provider.of<DietProvider>(context, listen: false);
      
      bool success;
      
      // Handle differently based on whether this is a new diet or an existing one
      if (widget.isNewDiet) {
        // Create a new diet when the save button is clicked
        final docId = await dietProvider.createDiet(
          userId: widget.userId, 
          dietData: {
            'subtitles': _editableData,
            'displayName': _dietName, // Include the diet name
            'subscriptionId': widget.dietDoc.subscriptionId, // Include the subscription ID
          }
        );
        success = docId.isNotEmpty;
      } else {
        // Update an existing diet
        success = await dietProvider.updateDiet(
          userId: widget.userId,
          docId: widget.dietDoc.docId,
          subtitles: _editableData,
          displayName: _dietName, // Include the diet name
          subscriptionId: widget.dietDoc.subscriptionId, // Include the subscription ID if present
        );
      }

      // Check if widget is still mounted before updating state
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (success) {
          _hasChanges = false;
        }
      });

      if (success) {
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: widget.isNewDiet 
            ? 'Diyet listesi başarıyla oluşturuldu.'
            : 'Diyet listesi başarıyla güncellendi.',
        );
        
        // Pop back to the list screen after successful save for new diets
        if (widget.isNewDiet && mounted) {
          Navigator.of(context).pop();
        }
      } else {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: widget.isNewDiet 
            ? 'Diyet oluşturulurken bir hata oluştu.'
            : 'Diyet güncellenirken bir hata oluştu.',
        );
      }
    } catch (e) {
      // Check if widget is still mounted before updating state
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      logger.err('Error saving diet: {}', [e]);
      
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: widget.isNewDiet 
          ? 'Diyet oluşturulurken bir hata oluştu: $e'
          : 'Diyet güncellenirken bir hata oluştu: $e',
      );
    }
  }

  IconData _getMealIcon(String mealName) {
    // Try to find the enum first
    try {
      final meal = Meals.values.firstWhere((m) => m.name == mealName);
      
      // Check based on enum
      switch (meal) {
        case Meals.br:
          return Icons.wb_sunny;
        case Meals.lunch:
          return Icons.lunch_dining;
        case Meals.dinner:
          return Icons.nightlight;
        case Meals.firstmid:
        case Meals.secondmid:
        case Meals.thirdmid:
          return Icons.free_breakfast;
        default:
          return Icons.restaurant;
      }
    } catch (e) {
      // If not an enum name, fallback to text-based matching
      final lowerName = mealName.toLowerCase();
      
      if (lowerName.contains('kahvaltı') || lowerName.contains('sabah')) {
        return Icons.wb_sunny;
      } else if (lowerName.contains('öğle')) {
        return Icons.lunch_dining;
      } else if (lowerName.contains('akşam')) {
        return Icons.nightlight;
      } else if (lowerName.contains('ara')) {
        return Icons.free_breakfast;
      } else {
        return Icons.restaurant;
      }
    }
  }

  // Edit diet name dialog
  void _editDietName() {
    final TextEditingController controller = TextEditingController(text: _dietName);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Diyet Adını Düzenle'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Diyet Adı',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onChanged: (value) {
                // Update dialog UI immediately when text changes
                setDialogState(() {});
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: controller.text.trim().isEmpty ? null : () {
                  final newName = controller.text.trim();
                  if (newName.isEmpty) {
                    DialogUtils.openError(
                      context,
                      title: 'Hata',
                      message: 'Diyet adı boş olamaz.',
                    );
                    return;
                  }
                  
                  Navigator.pop(context);
                  
                  if (newName != _dietName) {
                    setState(() {
                      _dietName = newName;
                      _hasChanges = true;
                    });
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        }
      ),
    );
  }

  // Helper method to get display name for meal keys
  String getMealDisplayName(String mealKey) {
    // Try to find matching enum by name
    try {
      final mealEnum = Meals.values.firstWhere((meal) => meal.name == mealKey);
      return mealEnum.label;
    } catch (e) {
      // If not an enum name, return the key as is (for backward compatibility)
      return mealKey;
    }
  }

  List<Widget> _buildEditableContentItems(String mealName, List<dynamic> contentList) {
    List<Widget> widgets = [];
    
    // Find all "Veya" markers to identify option groups
    List<int> veyaIndices = [];
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content = (item is Map) ? (item['content'] ?? '') : item.toString();
      
      if (content.trim() == VEYA_MARKER || isVeyaOptionSeparator(content)) {
        veyaIndices.add(i);
      }
    }
    
    // Process each content item individually
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content = (item is Map) ? (item['content'] ?? '') : item.toString();
      
      // Check if this is a special marker separator line
      if (isSpecialMarkerSeparator(content)) {
        // Handle marker separator line - extract the content after marker
        final contentAfterMarker = extractContentAfterMarker(content);
        
        // Determine marker type and styling
        bool isVeya = content.trim().startsWith(VEYA_MARKER);
        bool isHaftada = content.trim().startsWith(HAFTADA_MARKER_PREFIX);
        
        // Set styling based on marker type
        Color markerColor = isVeya ? Colors.orange : Colors.blue;
        IconData markerIcon = isVeya ? Icons.sync_alt : Icons.calendar_today;
        
        // Extract the marker text to display
        String markerText = VEYA_MARKER; // Default
        if (isHaftada) {
          final match = HAFTADA_OPTION_SEPARATOR_REGEX.firstMatch(content);
          if (match != null) {
            markerText = match.group(0)!.trim();
          } else {
            markerText = HAFTADA_MARKER_PREFIX;
          }
        }
        
        // Add marker separator indicator
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Marker indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: markerColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    markerIcon,
                    color: markerColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),

                // Marker text
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: markerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      markerText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: markerColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                // Delete marker button
                IconButton(
                  icon: const Icon(Icons.remove_circle,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteContentItem(mealName, i),
                  tooltip: 'Satırı Sil',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        );
        
        // If there's content after marker, add it as a separate item
        if (contentAfterMarker.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Content text with edit option
                  Expanded(
                    child: InkWell(
                      onTap: () => _editContentItem(mealName, i, contentAfterMarker),
                      child: Text(
                        contentAfterMarker,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  // Delete item button - this deletes the entire line
                  IconButton(
                    icon: const Icon(Icons.remove_circle,
                        color: Colors.red, size: 20),
                    onPressed: () => _deleteContentItem(mealName, i),
                    tooltip: 'Öğeyi Sil',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ),
          );
        }
      } 
      // Check if this is a standalone marker
      else if (SPECIAL_MARKERS.contains(content.trim())) {
        // Determine marker type and styling
        bool isVeya = content.trim() == VEYA_MARKER;
        bool isHaftada = content.trim() == HAFTADA_MARKER_PREFIX;
        
        // Set styling based on marker type
        Color markerColor = isVeya ? Colors.orange : Colors.blue;
        IconData markerIcon = isVeya ? Icons.sync_alt : Icons.calendar_today;
        
        // Handle standalone marker line
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Marker indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: markerColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    markerIcon,
                    color: markerColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),

                // Marker text
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: markerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      content.trim(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: markerColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                // Delete marker button
                IconButton(
                  icon: const Icon(Icons.remove_circle,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteContentItem(mealName, i),
                  tooltip: 'Satırı Sil',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        );
      }
      // Normal content items (not containing Veya)
      else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Content text with edit option
                Expanded(
                  child: InkWell(
                    onTap: () => _editContentItem(mealName, i, content),
                    child: Text(
                      content,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),

                // Delete item button
                IconButton(
                  icon: const Icon(Icons.remove_circle,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteContentItem(mealName, i),
                  tooltip: 'Öğeyi Sil',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        );
      }
    }
    
    return widgets;
  }

  // Add "Veya" content item - use the constant from meal_formatter.dart
  void _addVeyaContentItem(String mealName) {
    setState(() {
      final contentList = _editableData[mealName]['content'] as List;
      // Add just a "Veya" line to indicate this is an alternative option
      contentList.add({'content': VEYA_MARKER});
      _hasChanges = true;
    });
  }
  
  // Add "Haftada X" content item
  void _addHaftadaContentItem(String mealName) {
    // Show dialog to get the number X for "Haftada X"
    final TextEditingController controller = TextEditingController(text: "1");
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Haftalık Sıklık Ekle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Haftada kaç kez?',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (value) {
                    // Update dialog UI immediately when text changes
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Örnek: "Haftada 2" şeklinde görünecektir.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  final value = controller.text.trim();
                  // Validate input is a number
                  int? number = int.tryParse(value);
                  if (number == null || number <= 0) {
                    DialogUtils.openError(
                      context,
                      title: 'Hata',
                      message: 'Lütfen geçerli bir sayı giriniz.',
                    );
                    return;
                  }
                  
                  Navigator.pop(context);
                  setState(() {
                    final contentList = _editableData[mealName]['content'] as List;
                    // Add "Haftada X" line
                    contentList.add({'content': '$HAFTADA_MARKER_PREFIX $number'});
                    _hasChanges = true;
                  });
                },
                child: const Text('Ekle'),
              ),
            ],
          );
        }
      ),
    );
  }
}
