import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/app_update_info.dart';
import '../models/logger.dart';

/// Reads the admin-managed version rules from `admininput/appVersion` and
/// decides whether the running build should ask the user to update.
///
/// The check never touches Firebase Auth: it does not read the current user,
/// does not sign anyone out and does not sit in front of the auth state
/// stream. The saved session keeps restoring while this runs, so a user who
/// was already signed in stays signed in whatever the check answers.
///
/// Every failure resolves to "no update" instead of an error the user has to
/// deal with: no network, missing document, denied read, timeout or malformed
/// data all leave the app running as before.
class AppUpdateProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(AppUpdateProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Whether this platform ships through a store we can send the user to.
  /// Windows and macOS builds are installed by hand, so there is nothing to
  /// link them to.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  DocumentReference<Map<String, dynamic>> get _docRef => _firestore
      .collection(AppUpdateConstants.collection)
      .doc(AppUpdateConstants.docId);

  /// Returns what to show the user, or null when there is nothing to do.
  ///
  /// [currentVersion] defaults to the version this build reports; it is a
  /// parameter so the decision can be exercised without a rebuild.
  Future<AppUpdateInfo?> checkForUpdate({
    String currentVersion = AppConstants.appVersion,
  }) async {
    if (!isSupported) {
      logger.debug('Update check skipped: platform has no app store');
      return null;
    }

    try {
      final snapshot =
          await _docRef.get().timeout(AppUpdateConstants.checkTimeout);
      final info = AppUpdateInfo.resolve(
        data: snapshot.data(),
        currentVersion: currentVersion,
        isIos: Platform.isIOS,
      );
      logger.info('Update check: current={} outcome={}',
          [currentVersion, info?.action.name ?? 'up-to-date']);
      return info;
    } catch (e) {
      // Deliberately swallowed: the check is an extra, never a gate the user
      // can get stuck behind.
      logger.warn('Update check failed, continuing without it: {}', [e]);
      return null;
    }
  }
}
