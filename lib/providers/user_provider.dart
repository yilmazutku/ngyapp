// user_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import '../models/kvkk_consent_model.dart';
import '../pages/admin_create_user_page.dart';

final Logger logger = Logger.forClass(UserProvider);

/// Provides user management functionality, including user data handling, authentication,
/// and subscription management. Implements ChangeNotifier pattern for state management.
class UserProvider extends ChangeNotifier {
  static final List<String> collections = [
    'subscriptions',
    'appointments',
    'dietlists',
    'dailyData',
    'meals',
    'payments',
    'measurements'
  ];

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

  /// Updates a user's email address and migrates all their data to a new account
  /// 
  /// This complex operation creates a new user with the new email, migrates all data from the old user,
  /// and then deletes the old user account.
  /// 
  /// @param oldUid The user ID of the current user account
  /// @param oldEmail The current email address of the user
  /// @param password The password for authentication
  /// @param newEmail The new email address to use for the user
  /// @param updatedUser The UserModel containing updated user information
  /// 
  /// @return The new user ID if migration was successful, otherwise null
  Future<String?> updateEmailAndMigrate({
    required String oldUid,
    required String oldEmail,
    required String password,
    required String newEmail,
    required UserModel updatedUser,
  }) async {
    try {
      final adminUser = FirebaseAuth.instance.currentUser;
      if (adminUser == null) {
        logger.err('updateEmailAndMigrate: Admin is not signed in.');
        return null;
      }

      final newUid = await _migrateUserDataAndRecreateAuth(
        oldUid: oldUid,
        newEmail: newEmail,
        password: password,
        updatedUser: updatedUser,
      );

      if (newUid == null) {
        logger.err(
            'updateEmailAndMigrate: Data migration or user creation failed.');
        return null;
      }

      try {
        final oldUser = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: oldEmail,
          password: CreateUserPage.tempPw,
        );
        await oldUser.user?.delete();
        logger.info(
            'Deleted the old user and Successfully updated email and migrated data for oldUid={}',
            [oldUid]);
      } on Exception catch (e) {
        logger.err('Exception when deleting old user: {}', [e]);
      }

      await signInAutomatically(); //TODO TEST EDILMELI!!!

      await FirebaseFirestore.instance.collection('users').doc(oldUid).delete();
      logger.info('Deleted old Firestore user document for UID={}', [oldUid]);

      return newUid;
    } catch (e) {
      logger.err(
          'updateEmailAndMigrate: Error during email update and migration: {}',
          [e]);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Migrates user data and recreates authentication for a user with a new email
  /// 
  /// This is a helper method for the updateEmailAndMigrate process.
  /// 
  /// @param oldUid The user ID of the current user account
  /// @param newEmail The new email address to use for the user
  /// @param password The password for authentication
  /// @param updatedUser The UserModel containing updated user information
  /// 
  /// @return The new user ID if migration was successful, otherwise null
  Future<String?> _migrateUserDataAndRecreateAuth({
    required String oldUid,
    required String newEmail,
    required String password,
    required UserModel updatedUser,
  }) async {
    try {
      final newUid = FirebaseFirestore.instance.collection('users').doc().id;

      await _migrateUserData(oldUid, newUid);

      UserCredential newUserCred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: newEmail,
        password: password,
      );

      if (newUserCred.user == null) {
        logger.err(
            'Failed to create new Firebase user with email={}', [newEmail]);
        return null;
      }

      final updatedUserMap = updatedUser.toMap();
      updatedUserMap['userId'] = newUid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUid)
          .set(updatedUserMap);

      return newUid;
    } catch (e) {
      logger.err('Error during data migration and user recreation: {}', [e]);
      rethrow;
    }
  }

  /// Migrates user data from one user ID to another
  /// 
  /// @param oldUid The source user ID to migrate data from
  /// @param newUid The destination user ID to migrate data to
  Future<void> _migrateUserData(String oldUid, String newUid) async {
    final oldDocRef =
        FirebaseFirestore.instance.collection('users').doc(oldUid);
    final newDocRef =
        FirebaseFirestore.instance.collection('users').doc(newUid);

    final oldDataSnapshot = await oldDocRef.get();
    if (oldDataSnapshot.exists) {
      final userData = oldDataSnapshot.data();
      if (userData != null) {
        userData['userId'] = newUid;
        await newDocRef.set(userData, SetOptions(merge: true));
        logger.info('Top-level data migrated from oldUid={} to newUid={}',
            [oldUid, newUid]);
      }
    }

    await _migrateSubcollections(oldDocRef, newDocRef);
  }

  /// Migrates all subcollections from one user document to another
  /// 
  /// @param oldDocRef The source document reference to migrate subcollections from
  /// @param newDocRef The destination document reference to migrate subcollections to
  Future<void> _migrateSubcollections(
      DocumentReference oldDocRef, DocumentReference newDocRef) async {
    for (String subcollectionName in collections) {
      final oldSubcollectionRef = oldDocRef.collection(subcollectionName);
      final querySnapshot = await oldSubcollectionRef.get();

      for (final doc in querySnapshot.docs) {
        final newDocRefSub =
            newDocRef.collection(subcollectionName).doc(doc.id);
        await newDocRefSub.set(doc.data());
        logger.info('Migrated doc id={} in subcollection={} for newUid={}',
            [doc.id, subcollectionName, newDocRef.id]);
      }
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
