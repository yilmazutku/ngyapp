import '../constants/app_constants.dart';

/// What the running build should do about the version published on the store.
enum AppUpdateAction {
  /// A newer version exists, but the current one still works: the user may
  /// postpone the update.
  optional,

  /// The running version is older than the minimum the backend still supports.
  /// The app stays unusable until the user updates.
  forced,
}

/// The admin-managed version rules stored at `admininput/appVersion`, already
/// resolved for the platform the app is running on.
///
/// Document fields (all optional; a missing document simply means "no update"):
/// - [enabledField]: set to `false` to switch the whole check off.
/// - [latestVersionField]: newest published version, e.g. `"1.0.2"`.
///   Users below it get a dismissible prompt.
/// - [minSupportedVersionField]: oldest version still allowed to run.
///   Users below it are blocked until they update.
/// - [iosLatestVersionField] / [androidLatestVersionField] and
///   [iosMinSupportedVersionField] / [androidMinSupportedVersionField]:
///   per-store overrides, for when one store is still in review while the
///   other is already live. They win over the shared fields above.
/// - [iosAppIdField]: App Store numeric id; falls back to
///   [AppUpdateConstants.iosAppId].
/// - [androidPackageNameField]: Play Store listing id; falls back to
///   [AppUpdateConstants.androidPackageName].
/// - [messageField]: custom wording shown instead of the default text.
///
/// Nothing here depends on the signed-in user, so the outcome is identical for
/// a restored session and a fresh login.
class AppUpdateInfo {
  // Firestore field names, kept together so the admin document and the parser
  // cannot drift apart.
  static const String enabledField = 'enabled';
  static const String latestVersionField = 'latestVersion';
  static const String minSupportedVersionField = 'minSupportedVersion';
  static const String iosLatestVersionField = 'iosLatestVersion';
  static const String iosMinSupportedVersionField = 'iosMinSupportedVersion';
  static const String androidLatestVersionField = 'androidLatestVersion';
  static const String androidMinSupportedVersionField =
      'androidMinSupportedVersion';
  static const String iosAppIdField = 'iosAppId';
  static const String androidPackageNameField = 'androidPackageName';
  static const String messageField = 'message';
  static const String updatedAtField = 'updatedAt';

  /// Whether the user may postpone the update.
  final AppUpdateAction action;

  /// The version the user is being asked to move up to.
  final String targetVersion;

  /// Admin-supplied wording; empty when the default text should be used.
  final String customMessage;

  /// Store name as the user knows it ("App Store" / "Google Play").
  final String storeName;

  /// Store address using the platform's own scheme, tried first so the store
  /// app opens directly instead of a browser tab.
  final Uri storeUri;

  /// The https listing for the same app, used when [storeUri] cannot be
  /// handled by the device.
  final Uri webStoreUri;

  const AppUpdateInfo({
    required this.action,
    required this.targetVersion,
    required this.customMessage,
    required this.storeName,
    required this.storeUri,
    required this.webStoreUri,
  });

  bool get isForced => action == AppUpdateAction.forced;

  /// The text shown to the user: the admin's own wording when the document
  /// carries one, otherwise the default for this kind of update.
  String get userMessage {
    if (customMessage.isNotEmpty) return customMessage;
    return isForced
        ? AppUpdateConstants.forcedMessage(targetVersion, storeName)
        : AppUpdateConstants.optionalMessage(targetVersion, storeName);
  }

  /// Builds the prompt for [currentVersion], or null when there is nothing to
  /// show the user.
  ///
  /// Returns null — rather than throwing or guessing — for every "we cannot
  /// tell" case: no document, check disabled, versions that are not dotted
  /// numbers, an up-to-date build, or no store address to send the user to.
  /// A prompt whose button leads nowhere is worse than no prompt at all.
  static AppUpdateInfo? resolve({
    required Map<String, dynamic>? data,
    required String currentVersion,
    required bool isIos,
  }) {
    if (data == null || data[enabledField] == false) return null;

    final latest = _stringOf(
            data, isIos ? iosLatestVersionField : androidLatestVersionField) ??
        _stringOf(data, latestVersionField);
    final minSupported = _stringOf(
            data,
            isIos
                ? iosMinSupportedVersionField
                : androidMinSupportedVersionField) ??
        _stringOf(data, minSupportedVersionField);

    final AppUpdateAction action;
    final String targetVersion;
    if (minSupported != null && _isOlder(currentVersion, minSupported)) {
      action = AppUpdateAction.forced;
      // Point at the newest build when there is one: no reason to send the
      // user to the bare minimum and prompt them again tomorrow.
      targetVersion =
          (latest != null && _isOlder(minSupported, latest)) ? latest : minSupported;
    } else if (latest != null && _isOlder(currentVersion, latest)) {
      action = AppUpdateAction.optional;
      targetVersion = latest;
    } else {
      return null;
    }

    final appId = _stringOf(data, iosAppIdField) ?? AppUpdateConstants.iosAppId;
    final package = _stringOf(data, androidPackageNameField) ??
        AppUpdateConstants.androidPackageName;
    final listingId = isIos ? appId : package;
    if (listingId.isEmpty) return null;

    return AppUpdateInfo(
      action: action,
      targetVersion: targetVersion,
      customMessage: _stringOf(data, messageField) ?? '',
      storeName: isIos
          ? AppUpdateConstants.iosStoreName
          : AppUpdateConstants.androidStoreName,
      storeUri: Uri.parse(isIos
          ? 'itms-apps://itunes.apple.com/app/id$listingId'
          : 'market://details?id=$listingId'),
      webStoreUri: Uri.parse(isIos
          ? 'https://apps.apple.com/app/id$listingId'
          : 'https://play.google.com/store/apps/details?id=$listingId'),
    );
  }

  /// True only when [version] is provably older than [other]. Unparseable
  /// input answers "no", which keeps a typo in the admin document from
  /// locking users out.
  static bool _isOlder(String version, String other) {
    final result = compareVersions(version, other);
    return result != null && result < 0;
  }

  /// Compares two dotted version strings, so `1.0.10` counts as newer than
  /// `1.0.9` instead of sorting like text.
  ///
  /// Returns a negative number when [a] is older than [b], zero when they are
  /// the same, and a positive number when [a] is newer. Returns null when
  /// either side is not a dotted number sequence.
  static int? compareVersions(String a, String b) {
    final left = _numericParts(a);
    final right = _numericParts(b);
    if (left == null || right == null) return null;

    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final leftPart = i < left.length ? left[i] : 0;
      final rightPart = i < right.length ? right[i] : 0;
      if (leftPart != rightPart) return leftPart < rightPart ? -1 : 1;
    }
    return 0;
  }

  /// Splits `1.0.1+11` or `1.0.1-beta` into `[1, 0, 1]`; null when a segment
  /// is not a number. The build number is dropped on purpose: the store shows
  /// users the version name, not the build.
  static List<int>? _numericParts(String version) {
    final core = version.trim().split(RegExp(r'[+\-]')).first;
    if (core.isEmpty) return null;

    final parts = <int>[];
    for (final segment in core.split('.')) {
      final value = int.tryParse(segment.trim());
      if (value == null) return null;
      parts.add(value);
    }
    return parts;
  }

  static String? _stringOf(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
