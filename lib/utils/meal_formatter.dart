import 'package:flutter/material.dart';

// Constants for special markers handling
const String VEYA_MARKER = "Veya";
const String HAFTADA_MARKER_PREFIX = "Haftada"; // New marker for weekly frequency
const List<String> SPECIAL_MARKERS = [VEYA_MARKER, HAFTADA_MARKER_PREFIX];

// Regular expressions for marker separators
final RegExp VEYA_OPTION_SEPARATOR_REGEX = RegExp(r'^Veya\s+'); // Matches "Veya" followed by whitespace
final RegExp HAFTADA_OPTION_SEPARATOR_REGEX = RegExp(r'^Haftada\s+\d+\s*'); // Matches "Haftada X" where X is a number

// Helper to check if a content string is any special marker separator
bool isSpecialMarkerSeparator(String content) {
  return VEYA_OPTION_SEPARATOR_REGEX.hasMatch(content) || 
         HAFTADA_OPTION_SEPARATOR_REGEX.hasMatch(content);
}

// Helper to check if a content string is a standalone marker
bool isStandaloneMarker(String content) {
  final trimmedContent = content.trim();
  return SPECIAL_MARKERS.contains(trimmedContent) || 
         SPECIAL_MARKERS.any((marker) => trimmedContent.startsWith('$marker '));
}

// Helper to check if a content string is a Veya option separator (kept for backward compatibility)
bool isVeyaOptionSeparator(String content) {
  return VEYA_OPTION_SEPARATOR_REGEX.hasMatch(content);
}

// Helper to extract content after a marker in a separator
String extractContentAfterMarker(String content) {
  if (VEYA_OPTION_SEPARATOR_REGEX.hasMatch(content)) {
    return content.replaceFirst(VEYA_OPTION_SEPARATOR_REGEX, '');
  } else if (HAFTADA_OPTION_SEPARATOR_REGEX.hasMatch(content)) {
    return content.replaceFirst(HAFTADA_OPTION_SEPARATOR_REGEX, '');
  }
  return content;
}

// Helper to extract content after Veya in a separator (kept for backward compatibility)
String extractContentAfterVeya(String content) {
  return extractContentAfterMarker(content);
}

/// Utility class for formatting meal content for display
class MealFormatter {
  /// Formats a list of meal content items to display options with "Veya" separators
  /// 
  /// Each option starts with content item that has "Veya" prefix
  /// Returns a list of widgets with Text widgets for content and Dividers with "Veya" text
  static List<Widget> formatMealContentWithOptions(List<dynamic> contentList) {
    List<Widget> formattedContent = [];
    List<int> optionStartIndices = [];
    
    // First, identify all option boundaries
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content = (item is Map) ? (item['content'] ?? '') : item.toString();
      
      // The first item is always the start of the first option
      if (i == 0) {
        optionStartIndices.add(i);
      }
      // Any standalone marker or marker followed by content is the start of a new option
      else if (isStandaloneMarker(content.toString()) || isSpecialMarkerSeparator(content.toString())) {
        optionStartIndices.add(i);
      }
    }
    
    // Now create UI for each option with separators
    for (int optionIndex = 0; optionIndex < optionStartIndices.length; optionIndex++) {
      // Add divider before all options except the first
      if (optionIndex > 0) {
        // Get the marker text for the divider
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent = (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        String dividerText = VEYA_MARKER; // Default
        
        // Determine which marker to display in the divider
        if (markerContent.trim().startsWith(HAFTADA_MARKER_PREFIX)) {
          // For Haftada X, show the full "Haftada X" text
          final match = HAFTADA_OPTION_SEPARATOR_REGEX.firstMatch(markerContent);
          if (match != null) {
            dividerText = match.group(0)!.trim();
          } else {
            dividerText = HAFTADA_MARKER_PREFIX;
          }
        }
        
        formattedContent.add(const SizedBox(height: 8));
        formattedContent.add(
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  dividerText,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        );
        formattedContent.add(const SizedBox(height: 8));
      }
      
      // Determine the range of indices for this option
      int startIdx = optionStartIndices[optionIndex];
      int endIdx = (optionIndex < optionStartIndices.length - 1) 
                 ? optionStartIndices[optionIndex + 1] 
                 : contentList.length;
      
      // Add all items in this option
      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent = (item is Map) ? (item['content'] ?? '') : item.toString();
        
        // Skip standalone marker items
        if (SPECIAL_MARKERS.contains(displayContent.trim())) {
          continue; // Skip standalone marker lines
        } else if (isSpecialMarkerSeparator(displayContent)) {
          // Extract content after any marker
          displayContent = extractContentAfterMarker(displayContent);
        }
        
        formattedContent.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              displayContent,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        );
      }
    }
    
    return formattedContent;
  }

  /// Returns a RichText widget that formats meal content with options
  /// Used when we need to display the content as a single widget
  static Widget formatMealContentAsRichText(List<dynamic> contentList) {
    List<TextSpan> spans = [];
    List<int> optionStartIndices = [];
    
    // First, identify all option boundaries
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content = (item is Map) ? (item['content'] ?? '') : item.toString();
      
      // The first item is always the start of the first option
      if (i == 0) {
        optionStartIndices.add(i);
      }
      // Any standalone marker or marker followed by content is the start of a new option
      else if (isStandaloneMarker(content.toString()) || isSpecialMarkerSeparator(content.toString())) {
        optionStartIndices.add(i);
      }
    }
    
    // Now create spans for each option with separators
    for (int optionIndex = 0; optionIndex < optionStartIndices.length; optionIndex++) {
      // Add divider before all options except the first
      if (optionIndex > 0) {
        // Get the marker text for the divider
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent = (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        String dividerText = VEYA_MARKER; // Default
        
        // Determine which marker to display in the divider
        if (markerContent.trim().startsWith(HAFTADA_MARKER_PREFIX)) {
          // For Haftada X, show the full "Haftada X" text
          final match = HAFTADA_OPTION_SEPARATOR_REGEX.firstMatch(markerContent);
          if (match != null) {
            dividerText = match.group(0)!.trim();
          } else {
            dividerText = HAFTADA_MARKER_PREFIX;
          }
        }
        
        spans.add(const TextSpan(text: '\n'));
        spans.add(TextSpan(
          text: '$dividerText\n',
          style: TextStyle(
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(const TextSpan(text: '\n'));
      }
      
      // Determine the range of indices for this option
      int startIdx = optionStartIndices[optionIndex];
      int endIdx = (optionIndex < optionStartIndices.length - 1) 
                 ? optionStartIndices[optionIndex + 1] 
                 : contentList.length;
      
      // Add all items in this option
      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent = (item is Map) ? (item['content'] ?? '') : item.toString();
        
        // Skip standalone marker items
        if (SPECIAL_MARKERS.contains(displayContent.trim())) {
          continue; // Skip standalone marker lines
        } else if (isSpecialMarkerSeparator(displayContent)) {
          // Extract content after any marker
          displayContent = extractContentAfterMarker(displayContent);
        }
        
        spans.add(TextSpan(
          text: '$displayContent\n',
          style: const TextStyle(height: 1.5),
        ));
      }
    }
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black, fontSize: 16),
        children: spans,
      ),
    );
  }

  /// Convert meal content to a formatted string for plain text display
  static String formatMealContentAsString(List<dynamic> contentList) {
    StringBuffer buffer = StringBuffer();
    List<int> optionStartIndices = [];
    
    // First, identify all option boundaries
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content = (item is Map) ? (item['content'] ?? '') : item.toString();
      
      // The first item is always the start of the first option
      if (i == 0) {
        optionStartIndices.add(i);
      }
      // Any standalone marker or marker followed by content is the start of a new option
      else if (isStandaloneMarker(content.toString()) || isSpecialMarkerSeparator(content.toString())) {
        optionStartIndices.add(i);
      }
    }
    
    // Now create text for each option with separators
    for (int optionIndex = 0; optionIndex < optionStartIndices.length; optionIndex++) {
      // Add divider before all options except the first
      if (optionIndex > 0) {
        // Get the marker text for the divider
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent = (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        String dividerText = VEYA_MARKER; // Default
        
        // Determine which marker to display in the divider
        if (markerContent.trim().startsWith(HAFTADA_MARKER_PREFIX)) {
          // For Haftada X, show the full "Haftada X" text
          final match = HAFTADA_OPTION_SEPARATOR_REGEX.firstMatch(markerContent);
          if (match != null) {
            dividerText = match.group(0)!.trim();
          } else {
            dividerText = HAFTADA_MARKER_PREFIX;
          }
        }
        
        buffer.writeln();
        buffer.writeln(dividerText);
        buffer.writeln();
      }
      
      // Determine the range of indices for this option
      int startIdx = optionStartIndices[optionIndex];
      int endIdx = (optionIndex < optionStartIndices.length - 1) 
                 ? optionStartIndices[optionIndex + 1] 
                 : contentList.length;
      
      // Add all items in this option
      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent = (item is Map) ? (item['content'] ?? '') : item.toString();
        
        // Skip standalone marker items
        if (SPECIAL_MARKERS.contains(displayContent.trim())) {
          continue; // Skip standalone marker lines
        } else if (isSpecialMarkerSeparator(displayContent)) {
          // Extract content after any marker
          displayContent = extractContentAfterMarker(displayContent);
        }
        
        buffer.writeln(displayContent);
      }
    }
    
    return buffer.toString();
  }
} 