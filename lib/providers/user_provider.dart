// user_provider.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/logger.dart';
import '../models/user_model.dart';
import '../models/kvkk_consent_model.dart';

final Logger logger = Logger.forClass(UserProvider);

/// Provides user management functionality, including user data handling, authentication,
/// and subscription management. Implements ChangeNotifier pattern for state management.
class UserProvider extends ChangeNotifier {
  /// Base URL for the project's HTTPS Cloud Functions (default us-central1
  /// region). Callable functions are invoked over HTTP here instead of via the
  /// `cloud_functions` plugin, which has no Windows desktop support.
  static const String _functionsBaseUrl =
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
      logger.info('Fetching user details for userId={} ', [userId]);

      if (doc.exists) {
        return UserModel.fromDocument(doc);
      } else {
        return null;
      }
    } catch (e) {
      logger.err('Error fetching user details: {}', [e]);
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
      logger.info('User details updated successfully for userId={}',
          [updatedUser.userId]);
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error updating user details for userId={}: {}',
          [updatedUser.userId, e]);
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
        Uri.parse('$_functionsBaseUrl/updateUserEmail'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uid': userId, 'newEmail': newEmail},
        }),
      );
    } catch (e) {
      logger.err('updateUserEmail network error: {}', [e]);
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
      logger.info('Sign-in email updated for userId={}', [userId]);
      notifyListeners();
      return;
    }

    final error = decoded['error'];
    final message = (error is Map && error['message'] is String)
        ? error['message'] as String
        : 'E-posta güncellenirken bir hata oluştu.';
    logger.err('updateUserEmail failed: status={}, body={}',
        [response.statusCode, response.body]);
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
        Uri.parse('$_functionsBaseUrl/deleteUserAccount'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'uid': userId},
        }),
      );
    } catch (e) {
      logger.err('deleteUserAccount network error: {}', [e]);
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
      logger.info('User account deleted for userId={}', [userId]);
      notifyListeners();
      return;
    }

    final error = decoded['error'];
    final message = (error is Map && error['message'] is String)
        ? error['message'] as String
        : 'Kullanıcı silinirken bir hata oluştu.';
    logger.err('deleteUserAccount failed: status={}, body={}',
        [response.statusCode, response.body]);
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
      logger.info('Password reset email sent to signed-in user');
    } on FirebaseAuthException catch (e) {
      logger.err('sendPasswordResetEmailToCurrentUser failed: {}', [e.code]);
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
      logger.debug('Fetched users: {}', [users]);
      return users;
    } catch (e) {
      logger.err('Error fetching users: $e');
      rethrow;
    }
  }

  /// Fetches all customer users from the database
  /// 
  /// @return A list of UserModel objects representing all customer users
  Future<List<UserModel>> fetchAllCustomers() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .get();

      final users = querySnapshot.docs.map((doc) {
        return UserModel.fromDocument(doc);
      }).toList();

      logger.info('Fetched {} customer users', [users.length]);
      return users;
    } catch (e) {
      logger.err('Error fetching customer users: {}', [e]);
      rethrow;
    }
  }

  // ============ KVKK Consent Methods ============

  /// Fetches KVKK consent status for a user
  /// 
  /// @param userId The ID of the user to check consent for
  /// 
  /// @return KvkkConsentModel containing consent status, or null if not found
  Future<KvkkConsentModel?> fetchKvkkConsent({required String userId}) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          return KvkkConsentModel.fromMap(data);
        }
      }
      return null;
    } catch (e) {
      logger.err('Error fetching KVKK consent for userId={}: {}', [userId, e]);
      rethrow;
    }
  }

  /// Checks if a user has valid KVKK consent for the current version
  /// 
  /// @param userId The ID of the user to check
  /// 
  /// @return true if user has valid consent, false otherwise
  Future<bool> hasValidKvkkConsent({required String userId}) async {
    try {
      final consent = await fetchKvkkConsent(userId: userId);
      if (consent == null) {
        logger.info('No KVKK consent found for userId={}', [userId]);
        return false;
      }
      final hasValid = consent.hasValidConsent;
      logger.info('KVKK consent check for userId={}: hasValid={}', [userId, hasValid]);
      return hasValid;
    } catch (e) {
      logger.err('Error checking KVKK consent for userId={}: {}', [userId, e]);
      return false;
    }
  }

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

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update(consentData);

      logger.info(
        'KVKK consent saved for userId={}: version={}, kvkkAccepted={}, explicitConsentAccepted={}',
        [userId, kvkkCurrentVersion, kvkkAccepted, explicitConsentAccepted],
      );
      
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error saving KVKK consent for userId={}: {}', [userId, e]);
      rethrow;
    }
  }
}
