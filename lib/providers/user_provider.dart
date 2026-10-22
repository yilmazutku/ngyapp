// user_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/kvkk_consent_model.dart';

/// Provides user management functionality, including user data handling, authentication,
/// and subscription management. Implements ChangeNotifier pattern for state management.
class UserProvider extends ChangeNotifier {
  /// Base URL for the project's HTTPS Cloud Functions (default us-central1
  /// region). Callable functions are invoked over HTTP here instead of via the
  /// `cloud_functions` plugin, which has no Windows desktop support.
  static const String functionsBaseUrl =
      'https://us-central1-deneme2-bc96d.cloudfunctions.net';

  /// Fetches user details from Firestore based on the provided user ID
  /// 
  /// @param userId The ID of the user whose details to fetch
  /// 
  /// @return A UserModel object if the user exists, otherwise null
  Future<UserModel?> fetchUserDetails({required String userId}) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (doc.exists) {
        return UserModel.fromDocument(doc);
      } else {
        return null;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Updates an existing user's details in Firestore
  /// 
  /// @param updatedUser The UserModel containing the updated user information
  /// 
  /// @return A boolean indicating whether the update was successful
  Future<bool> updateUserDetails(UserModel updatedUser) async {
    try {
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(updatedUser.userId);
      await userDoc.update(updatedUser.toMap());
      invalidateCustomers();
      notifyListeners();
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Updates a user's sign-in email on Firebase Authentication and Firestore.
  ///
  /// Calls the `updateUserEmail` Cloud Function (Admin SDK) over HTTP using the
  /// callable protocol, passing the caller's Firebase ID token for auth. The
  /// function changes the email in place: the user keeps the SAME UID and the
  /// SAME password. After this completes, the user signs in with [newEmail]
  /// using their existing password and the old email can no longer be used.
  ///
  /// Authorization is enforced server-side (only admins may call it), so no
  /// data migration, admin re-login, or password reset is required.
  ///
  /// @param userId The UID of the user whose email should change
  /// @param newEmail The new email address
  ///
  /// @throws Exception with a user-friendly message when the update fails
  Future<void> updateUserEmail({
    required String userId,
    required String newEmail,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Oturum bulunamadı. Lütfen tekrar giriş yapın.');
    }

    final String? idToken = await currentUser.getIdToken();
    if (idToken == null) {
      throw Exception('Kimlik doğrulanamadı. Lütfen tekrar giriş yapın.');
    }

    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$functionsBaseUrl/updateUserEmail'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uid': userId, 'newEmail': newEmail},
        }),
      );
    } catch (e) {
      throw Exception(
          'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.');
    }

    // Callable protocol: success => { "result": ... }, failure => non-2xx with
    // { "error": { "message": ..., "status": ... } }.
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Ignore non-JSON bodies; handled by the status-code check below.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      invalidateCustomers();
      notifyListeners();
      return;
    }

    final error = decoded['error'];
    final message = (error is Map && error['message'] is String)
        ? error['message'] as String
        : 'E-posta güncellenirken bir hata oluştu.';
    throw Exception(message);
  }

  /// Permanently deletes a user and EVERYTHING that belongs to them.
  ///
  /// Calls the admin-only `deleteUserAccount` Cloud Function (Admin SDK) over
  /// HTTP using the callable protocol, passing the caller's Firebase ID token
  /// for authorization. The function removes the user's Firestore document and
  /// every subcollection (appointments, payments, subscriptions, measurements
  /// + Tanita PDFs, tests/documents, diet lists, meals, daily data), their chat
  /// and messages, every file stored under them in Firebase Storage
  /// (users/{uid}/** and chats/{uid}/**) and finally their Firebase
  /// Authentication account.
  ///
  /// Authorization is enforced server-side (only admins may call it and admin
  /// accounts can never be deleted).
  ///
  /// @param userId The UID of the user to delete
  ///
  /// @throws Exception with a user-friendly message when the deletion fails
  Future<void> deleteUserAccount({required String userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Oturum bulunamadı. Lütfen tekrar giriş yapın.');
    }

    final String? idToken = await currentUser.getIdToken();
    if (idToken == null) {
      throw Exception('Kimlik doğrulanamadı. Lütfen tekrar giriş yapın.');
    }

    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$functionsBaseUrl/deleteUserAccount'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uid': userId},
        }),
      );
    } catch (e) {
      throw Exception(
          'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.');
    }

    // Callable protocol: success => { "result": ... }, failure => non-2xx with
    // { "error": { "message": ..., "status": ... } }.
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Ignore non-JSON bodies; handled by the status-code check below.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      invalidateCustomers();
      notifyListeners();
      return;
    }

    final error = decoded['error'];
    final message = (error is Map && error['message'] is String)
        ? error['message'] as String
        : 'Kullanıcı silinirken bir hata oluştu.';
    throw Exception(message);
  }

  /// Sends a Firebase password reset email to the currently signed-in user's
  /// own email address.
  ///
  /// The address is read from [FirebaseAuth.instance.currentUser] so callers
  /// (e.g. the profile page) never have to ask the user to type it. The user
  /// must be signed in and have an email associated with their account.
  ///
  /// @throws Exception with a user-friendly message when there is no signed-in
  ///         user/email or when Firebase rejects the request.
  Future<void> sendPasswordResetEmailToCurrentUser() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw Exception(
          'Hesabınıza tanımlı bir e-posta adresi bulunmadığından şifre sıfırlama bağlantısı gönderilemedi.');
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      throw Exception(
          'Şifre sıfırlama bağlantısı gönderilemedi. Lütfen tekrar deneyiniz.');
    }
  }

  // Subscription-related methods moved to SubProvider

  /// Fetches all users from the database
  /// 
  /// @return A list of UserModel objects representing all users in the database
  Future<List<UserModel>> fetchUsers() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').get();
      final users =
          snapshot.docs.map((doc) => UserModel.fromDocument(doc)).toList();
      return users;
    } catch (e) {
      rethrow;
    }
  }

  /// [fetchAllCustomers] sonucunun oturum içinde saklandığı süre.
  static const Duration customersCacheTtl = Duration(minutes: 5);

  List<UserModel>? _customersCache;
  DateTime? _customersCachedAt;

  /// Önbelleği dolduran oturumun kullanıcısı: hesap değişince eski liste
  /// kullanılmaz.
  String? _customersCacheOwner;
  Future<List<UserModel>>? _customersInFlight;

  /// Fetches all customer users from the database
  ///
  /// Liste [customersCacheTtl] boyunca saklanır: Tüm Sohbetler, Yeni Sohbet,
  /// Öğün Fotoğrafları gibi ekranlar arka arkaya açılınca bütün danışanlar
  /// her seferinde yeniden okunmaz; aynı anda gelen istekler tek okumayı
  /// paylaşır. "Yenile" gibi durumlarda [forceRefresh] ile sunucudan okunur.
  /// Çağıranlar listeyi sıralayabilsin diye her seferinde kopyası döner.
  ///
  /// @return A list of UserModel objects representing all customer users
  Future<List<UserModel>> fetchAllCustomers({bool forceRefresh = false}) async {
    final String? owner = FirebaseAuth.instance.currentUser?.uid;
    final List<UserModel>? cached = _customersCache;
    final DateTime? cachedAt = _customersCachedAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        owner == _customersCacheOwner &&
        DateTime.now().difference(cachedAt) < customersCacheTtl) {
      return List<UserModel>.of(cached);
    }

    final Future<List<UserModel>> loading =
        _customersInFlight ??= _loadCustomers(owner);
    try {
      return List<UserModel>.of(await loading);
    } finally {
      if (identical(_customersInFlight, loading)) _customersInFlight = null;
    }
  }

  Future<List<UserModel>> _loadCustomers(String? owner) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'customer')
        .get();

    final List<UserModel> users =
        querySnapshot.docs.map(UserModel.fromDocument).toList();
    _customersCache = users;
    _customersCachedAt = DateTime.now();
    _customersCacheOwner = owner;
    return users;
  }

  /// Danışan listesi değişti (kayıt, silme, güncelleme): bir sonraki
  /// [fetchAllCustomers] sunucudan okur.
  void invalidateCustomers() {
    _customersCache = null;
    _customersCachedAt = null;
  }

  /// Hesap silme talebinde sunucunun en fazla bekleneceği süre.
  static const Duration _removalRequestTimeout = Duration(seconds: 10);

  /// Kullanıcının hesap silme talebini (`isUserRequestedRemoval`) sunucuya
  /// yazar. Bağlantı gerekir: talepten sonra oturum kapanır ve kapanan
  /// oturumun sıradaki yazımı ancak aynı kullanıcı yeniden girince gider.
  /// Önce sunucuya ulaşılabildiği denenir; ulaşılamazsa ya da yazım zamanında
  /// bitmezse hata fırlatır (çağıran oturumu kapatmaz).
  Future<void> requestAccountRemoval({required String userId}) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        FirebaseFirestore.instance.collection('users').doc(userId);
    await userDoc
        .get(const GetOptions(source: Source.server))
        .timeout(_removalRequestTimeout);
    await userDoc
        .set({'isUserRequestedRemoval': true}, SetOptions(merge: true))
        .timeout(_removalRequestTimeout);
  }

  // ============ KVKK Consent Methods ============

  /// Onay okumasında sunucunun en fazla bekleneceği süre: internete çıkmayan
  /// bir ağda Firestore'un çevrimdışı olduğunu anlaması uzun sürebiliyor.
  static const Duration _kvkkReadTimeout = Duration(seconds: 8);

  /// Onay yazımında sunucu onayının en fazla bekleneceği süre. Çevrimdışıyken
  /// yazım sunucuya ulaşmaz ama cihazda kalıcı sırada bekler ve bağlantı
  /// gelince gider; bu süreden sonra kaydedilmiş sayılır.
  static const Duration _kvkkSaveAckTimeout = Duration(seconds: 5);

  /// Kullanıcının KVKK onayı. Önce cihazdaki kopyaya bakılır: orada geçerli
  /// onay varsa sunucu beklenmez (onayı yalnızca kullanıcı verir, sunucuda
  /// daha eskisi olamaz), çevrimdışı açılış da hemen geçer. Yoksa sunucudan
  /// (bağlantı yoksa cihazdaki kopyadan) okunur. Kayıt hiç okunamazsa
  /// (çevrimdışı ve cihazda kopyası yok) [KvkkConsentStatus.unknown]: onay
  /// vermiş kullanıcıya onay sayfası gösterilmesin.
  Future<KvkkConsentStatus> checkKvkkConsent({required String userId}) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        FirebaseFirestore.instance.collection('users').doc(userId);

    DocumentSnapshot<Map<String, dynamic>>? cached;
    try {
      cached = await userDoc.get(const GetOptions(source: Source.cache));
      if (_hasValidConsent(cached)) return KvkkConsentStatus.valid;
    } catch (e) {
      // Cihazda kopyası yok.
    }

    try {
      final doc = await userDoc.get().timeout(_kvkkReadTimeout);
      return _hasValidConsent(doc)
          ? KvkkConsentStatus.valid
          : KvkkConsentStatus.missing;
    } on TimeoutException {
      // Sunucu yanıt vermedi: cihazdaki kopya varsa (geçerli onay yok, ör.
      // metin sürümü değişti) ona göre karar verilir.
      return (cached?.exists ?? false)
          ? KvkkConsentStatus.missing
          : KvkkConsentStatus.unknown;
    } on FirebaseException catch (e) {
      return e.code == 'unavailable'
          ? KvkkConsentStatus.unknown
          : KvkkConsentStatus.missing;
    } catch (e) {
      return KvkkConsentStatus.missing;
    }
  }

  static bool _hasValidConsent(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    return data != null && KvkkConsentModel.fromMap(data).hasValidConsent;
  }

  /// Checks if a user has valid KVKK consent for the current version
  /// (see [checkKvkkConsent]); an unreadable record counts as no consent.
  Future<bool> hasValidKvkkConsent({required String userId}) async =>
      await checkKvkkConsent(userId: userId) == KvkkConsentStatus.valid;

  /// Saves KVKK consent for a user
  /// 
  /// @param userId The ID of the user
  /// @param kvkkAccepted Whether the user acknowledged the KVKK information notice
  /// @param explicitConsentAccepted Whether the user gave explicit consent for special data
  /// 
  /// @return true if consent was saved successfully
  Future<bool> saveKvkkConsent({
    required String userId,
    required bool kvkkAccepted,
    required bool explicitConsentAccepted,
  }) async {
    try {
      final now = DateTime.now();
      final consentData = <String, dynamic>{
        'kvkkVersion': kvkkCurrentVersion,
      };

      if (kvkkAccepted) {
        consentData['kvkkAcceptedAt'] = Timestamp.fromDate(now);
      }
      if (explicitConsentAccepted) {
        consentData['explicitConsentAcceptedAt'] = Timestamp.fromDate(now);
      }

      final DocumentReference<Map<String, dynamic>> userDoc =
          FirebaseFirestore.instance.collection('users').doc(userId);
      try {
        await userDoc.update(consentData).timeout(_kvkkSaveAckTimeout);
      } on TimeoutException {
        // Sunucu onayı gelmedi (çevrimdışı): onay cihazdaki kayda işlendiyse
        // sırada bekler, bağlantı gelince gider. İşlenmediyse (kayıt cihazda
        // yok) kaydedilmiş sayılmaz.
        DocumentSnapshot<Map<String, dynamic>>? local;
        try {
          local = await userDoc.get(const GetOptions(source: Source.cache));
        } catch (e) {
          // Cihazda kopyası yok.
        }
        if (local == null || !_hasValidConsent(local)) rethrow;
      }

      notifyListeners();
      return true;
    } catch (e) {
      rethrow;
    }
  }
}
