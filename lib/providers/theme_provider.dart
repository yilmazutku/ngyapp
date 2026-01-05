import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/logger.dart';

final Logger logger = Logger.forClass(ThemeProvider);

/// Manages app theme color with persistence
/// Allows changing the primary color of the app and persists the preference
class ThemeProvider extends ChangeNotifier {
  static const String _colorKey = 'app_primary_color';
  
  // Default blue color (the original app color)
  static const Color defaultColor = Color(0xFF2196F3); // Blue 500 (Colors.blue)
  
  Color _primaryColor = defaultColor;
  bool _isInitialized = false;

  /// The current primary color of the app
  Color get primaryColor => _primaryColor;
  
  /// Whether the provider has been initialized
  bool get isInitialized => _isInitialized;
  
  /// Get the hex string representation of the current color (e.g., "#7B1FA2")
  String get primaryColorHex {
    return '#${_primaryColor.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Initialize the provider and load saved color preference
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedColorValue = prefs.getInt(_colorKey);
      
      if (savedColorValue != null) {
        _primaryColor = Color(savedColorValue);
        logger.info('Loaded saved color: $primaryColorHex');
      } else {
        _primaryColor = defaultColor;
        logger.info('Using default color: $primaryColorHex');
      }
    } catch (e) {
      logger.err('Error loading color preference: $e');
      _primaryColor = defaultColor;
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  /// Change the primary color and persist it
  Future<void> setColor(Color color) async {
    if (_primaryColor == color) return;
    
    _primaryColor = color;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_colorKey, color.value);
      logger.info('Saved color preference: $primaryColorHex');
    } catch (e) {
      logger.err('Error saving color preference: $e');
    }
  }

  /// Reset to the default purple color
  Future<void> resetToDefault() async {
    await setColor(defaultColor);
    logger.info('Reset to default color: $primaryColorHex');
  }

  /// Check if the current color is the default color
  bool get isDefaultColor => _primaryColor == defaultColor;

  /// Create a MaterialColor from the primary color for use as primarySwatch
  MaterialColor get primarySwatch {
    return _createMaterialColor(_primaryColor);
  }

  /// Helper to create a MaterialColor from a single Color
  MaterialColor _createMaterialColor(Color color) {
    final strengths = <double>[.05, .1, .2, .3, .4, .5, .6, .7, .8, .9];
    final swatch = <int, Color>{};
    final r = color.red, g = color.green, b = color.blue;

    for (final strength in strengths) {
      final ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}

