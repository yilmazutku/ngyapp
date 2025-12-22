import 'dart:developer' as developer;
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class Logger {
  final String name;

  // --- Static state shared by all Logger instances ---
  static IOSink? _logFileSink;
  static String? _logDirectory;
  static bool _initialized = false;
  static bool _debugEnabled = true; // Controls whether .debug() messages are logged
  static bool _logToFileEnabled = true; // Controls whether any messages are saved to file

  // Rotation state
  static const int _maxBytes = 5 * 1024 * 1024; // 5 MB
  static String _currentDateStr = '';
  static int _currentIndex = 1; // 1 = no suffix; 2 => _2, etc.
  static String? _currentFilePath;

  // Serializes all disk writes to avoid "StreamSink is bound to a stream"
  static Future<void> _writeChain = Future.value();
  static int _unflushedWrites = 0;

  Logger(this.name);
  factory Logger.forClass(Type type) => Logger(type.toString());

  /// Call early (e.g., before runApp): await Logger.initialize();
  static Future<void> initialize({bool debugEnabled = true, bool logToFileEnabled = true}) async {
    if (_initialized) return;
    
    // Store flags
    _debugEnabled = debugEnabled;
    _logToFileEnabled = logToFileEnabled;
    
    // If file logging is disabled, mark as initialized and skip file logging setup
    if (!_logToFileEnabled) {
      _initialized = true;
      return;
    }

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (!isDesktop) {
      _initialized = true; // console-only on mobile/web
      return;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final logsDir = Directory(p.join(appDocDir.path, 'IlkApp', 'logs'));
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      _logDirectory = logsDir.path;

      // Prepare sink for "now" (sets date/index and opens the correct file).
      await _prepareSinkForNow();

      _initialized = true;
      final logger = Logger('LogSystem');
      logger.info('Logging system initialized. Log directory: $_logDirectory');
    } catch (e, st) {
      developer.log('Failed to initialize logging system: $e',
          name: 'LogSystem', stackTrace: st);
      _initialized = true; // allow console logging even if file logging failed
    }
  }

  /// Close cleanly on app shutdown.
  static Future<void> dispose() async {
    // Finish queued writes first
    try {
      await _writeChain;
    } catch (_) {}

    final sink = _logFileSink;
    _logFileSink = null;
    if (sink != null) {
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
    }
  }

  void info(String message, [List<Object?>? args]) =>
      _log('INFO', _format(message, args));
  void debug(String message, [List<Object?>? args]) =>
      _log('DEBUG', _format(message, args));
  void warn(String message, [List<Object?>? args]) =>
      _log('WARN', _format(message, args));
  void err(String message, [List<Object?>? args]) =>
      _log('ERROR', _format(message, args));

  void _log(String level, String message,
      {Object? error, StackTrace? stackTrace}) {
    // Skip debug level messages if debug is disabled
    if (level == 'DEBUG' && !_debugEnabled) return;
    
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    final line = '[$ts] [$level] [$name] $message';

    // Always log to console
    developer.log(line, name: name, error: error, stackTrace: stackTrace);

    // Attempt file logging (desktop only)
    _logToFile(line, error, stackTrace);
  }

  void _logToFile(String line, Object? error, StackTrace? stackTrace) {
    // Skip file logging if disabled
    if (!_logToFileEnabled) return;
    if (_logDirectory == null) return;
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    _writeChain = _writeChain.then((_) async {
      try {
        // Ensure sink is open for the current date, and rotate if size limit hit.
        await _prepareSinkForNow();

        final sink = _logFileSink;
        if (sink == null) return;

        // --- Write the log lines ---
        sink.writeln(line);
        if (error != null) sink.writeln('ERROR: $error');
        if (stackTrace != null) sink.writeln('STACK TRACE:\n$stackTrace');

        // Flush occasionally (reduce disk churn)
        if (++_unflushedWrites >= 20) {
          _unflushedWrites = 0;
          await sink.flush();
        }

        // If we just crossed the limit, rotate so the NEXT write starts fresh.
        await _rotateIfSizeExceeded();
      } catch (e, st) {
        developer.log('Failed to write to log file: $e',
            name: 'LogSystem', stackTrace: st);
      }
    });
  }

  // -------- Rotation helpers --------

  /// Ensure the sink is ready for "now":
  /// - If date changed, switch to the new date and pick the correct index.
  /// - If current file already >= max, rotate before writing.
  static Future<void> _prepareSinkForNow() async {
    final nowDateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    // Date changed? start a new set for today (index chosen based on existing files & sizes)
    if (nowDateStr != _currentDateStr || _logFileSink == null) {
      await _openLatestForDate(nowDateStr);
      return;
    }

    // Same date: if file is already at/over limit, rotate before next write.
    await _rotateIfSizeExceeded();
  }

  /// If current file size >= _maxBytes, close it and open the next suffix.
  static Future<void> _rotateIfSizeExceeded() async {
    final path = _currentFilePath;
    if (path == null) return;

    try {
      final file = File(path);
      final len = await file.length();
      if (len >= _maxBytes) {
        await _reopenWithIndex(_currentDateStr, _currentIndex + 1);
      }
    } catch (e) {
      // If stat fails, fail silently; next write will try again.
    }
  }

  /// Open the correct file for the given date:
  /// - Finds the highest existing index for that date.
  /// - If that file has size >= max, advance to next index.
  /// - Opens sink in append mode.
  static Future<void> _openLatestForDate(String dateStr) async {
    if (_logDirectory == null) return;
    final dir = Directory(_logDirectory!);

    // Scan existing files for this date
    final pattern = RegExp(r'^application_' + dateStr + r'(?:_(\d+))?\.log$');
    int maxFoundIndex = 0;
    File? latestFile;

    try {
      final entries = await dir
          .list(followLinks: false, recursive: false)
          .where((e) => e is File)
          .cast<File>()
          .toList();

      for (final f in entries) {
        final name = p.basename(f.path);
        final m = pattern.firstMatch(name);
        if (m != null) {
          final idx = (m.group(1) == null) ? 1 : int.parse(m.group(1)!);
          if (idx >= maxFoundIndex) {
            maxFoundIndex = idx;
            latestFile = f;
          }
        }
      }
    } catch (_) {
      // ignore listing errors; we'll just start a fresh file
    }

    int targetIndex = (maxFoundIndex == 0) ? 1 : maxFoundIndex;
    // If the latest existing file is already full, move to the next index.
    if (latestFile != null) {
      try {
        final len = await latestFile.length();
        if (len >= _maxBytes) {
          targetIndex = maxFoundIndex + 1;
        }
      } catch (_) {
        // If size check fails, keep the targetIndex as-is.
      }
    }

    await _reopenWithIndex(dateStr, targetIndex);
  }

  /// Close current sink (if any) and open the file for [dateStr] and [index].
  static Future<void> _reopenWithIndex(String dateStr, int index) async {
    // Close previous sink
    final old = _logFileSink;
    _logFileSink = null;
    if (old != null) {
      try {
        await old.flush();
      } catch (_) {}
      try {
        await old.close();
      } catch (_) {}
    }

    _currentDateStr = dateStr;
    _currentIndex = index;

    final filePath = _buildLogPath(dateStr, index);
    _currentFilePath = filePath;

    final file = File(filePath);
    try {
      // Ensure parent dir exists
      await file.parent.create(recursive: true);
      _logFileSink = file.openWrite(mode: FileMode.append);
    } catch (e, st) {
      developer.log('Failed to open log file "$filePath": $e',
          name: 'LogSystem', stackTrace: st);
      _logFileSink = null; // fall back to console only
    }
  }

  static String _buildLogPath(String dateStr, int index) {
    // application_YYYYMMDD.log  or  application_YYYYMMDD_2.log
    final base = (index <= 1)
        ? 'application_$dateStr.log'
        : 'application_${dateStr}_$index.log';
    return p.join(_logDirectory!, base);
  }

  // -------- formatting --------
  String _format(String message, [List<Object?>? args]) {
    if (args == null || args.isEmpty) return message;
    for (final arg in args) {
      message = message.replaceFirst(RegExp(r'\{\}'), arg?.toString() ?? 'null');
    }
    return message;
  }
}
