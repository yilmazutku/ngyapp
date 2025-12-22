import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'file_handlers//file_handler.dart';
import 'models/meal_model.dart';
import 'models/logger.dart';

final Logger log = Logger('DocxParserTest');

// A simple standalone test to diagnose docx parsing issues
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Path to the problematic document
    const String docxPath = 'lib/kkl_edited.docx';
    log.info('Testing parser with document: {}', [docxPath]);
    
    // Check if file exists
    final File file = File(docxPath);
    if (!await file.exists()) {
      log.err('Test file not found: {}', [docxPath]);
      return;
    }
    
    final Uint8List fileBytes = await file.readAsBytes();
    log.info('File size: {} bytes', [fileBytes.length]);
    
    // Initialize subtitles structure similar to FileHandlerPage
    List<Map<String, dynamic>> subtitles = [];
    for (var meal in Meals.values) {
      subtitles.add({
        'name': meal.label,
        'time': meal.defaultTime,
        'content': [],
      });
    }
    
    // Process the file
    await handleFile(
      fileBytes,
      'kkl_edited.docx',
      (text, filePath) {
        log.info('File processed successfully, extracted text length: {}', [text.length]);
        _extractSubtitles(text, subtitles);
      },
      (error) {
        log.err('Error processing file: {}', [error]);
      }
    );
  } catch (e, stackTrace) {
    log.err('Exception: {}', [e.toString()]);
    log.err('Stack trace: {}', [stackTrace.toString()]);
  }
}

void _extractSubtitles(String text, List<Map<String, dynamic>> subtitles) {
  log.info('============ PARSING DEBUG START ============');
  log.info('Text length: {}', [text.length]);
  
  // For very large texts, just show first 500 chars
  if (text.length > 500) {
    log.info('Text preview: {}...', [text.substring(0, 500)]);
  } else {
    log.info('Text: {}', [text]);
  }
  
  // Split the text into lines and clean it
  final lines = text
      .split(RegExp(r'\r\n|\r|\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  
  log.info('Extracted {} lines from document', [lines.length]);
  
  // Log up to first 30 lines
  int maxLinesToShow = lines.length < 30 ? lines.length : 30;
  for (int i = 0; i < maxLinesToShow; i++) {
    log.info('Line {}: {}', [i, lines[i]]);
  }
  
  // Log all meal types we're looking for
  log.info('Searching for these meal types:');
  for (var meal in Meals.values) {
    log.info('- {} ({})', [meal.name, meal.label]);
  }
  
  Map<String, dynamic>? currentSubtitle;
  
  for (var line in lines) {
    // Check if this line starts a new meal section
    bool foundMealSection = false;
    
    // For non-Ara meals (direct matching)
    for (var meal in Meals.values) {
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
            final timeMatch = RegExp(r'(\d{1,2}:\d{2})').firstMatch(line);
            currentSubtitle['time'] = timeMatch?.group(0) ?? '';
            
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
        
        // Find the first unused "Ara" meal in our subtitles
        var araSubtitle = subtitles.firstWhere(
          (subtitle) => subtitle['name'] == "Ara" && subtitle['content'].isEmpty,
          orElse: () => {},
        );
        
        if (araSubtitle.isNotEmpty) {
          currentSubtitle = araSubtitle;
          
          // Extract time
          final timeMatch = RegExp(r'(\d{1,2}:\d{2})').firstMatch(line);
          currentSubtitle['time'] = timeMatch?.group(0) ?? '';
          
          log.info('Assigned to Ara meal with time: {}, extracted time: {}',
              [araSubtitle['time'], currentSubtitle['time']]);
          
          foundMealSection = true;
        } else {
          log.warn('All "Ara" meals already assigned content');
        }
      }
    }
    
    // If we didn't find a new meal section, treat as content for current subtitle
    if (!foundMealSection && currentSubtitle != null) {
      log.info('Adding content to subtitle {}: {}',
          [currentSubtitle['name'], line]);

      // Add content to the current subtitle's content list
      currentSubtitle['content'].add({
        'content': line,
      });
    } else if (!foundMealSection) {
      log.warn('No subtitle found and no active subtitle for line: {}', [line]);
    }
  }

  log.info('Final parsed subtitles:');
  for (var subtitle in subtitles) {
    log.info('- {} ({}): {} items', [
      subtitle['name'], 
      subtitle['time'], 
      subtitle['content'].length
    ]);
    
    // Only show first few items to avoid log flooding
    int itemsToShow = subtitle['content'].length > 5 ? 5 : subtitle['content'].length;
    for (int i = 0; i < itemsToShow; i++) {
      log.info('  * {}', [subtitle['content'][i]['content']]);
    }
    if (subtitle['content'].length > 5) {
      log.info('  * ... and {} more items', [subtitle['content'].length - 5]);
    }
  }
  log.info('============ PARSING DEBUG END ============');
} 