import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

Future<void> migrateDailyDataForUser(String userId) async {
  final dailyDataRef = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('dailyData');

  final snapshot = await dailyDataRef.get();

  final oldFormat = DateFormat('dd-MM-yyyy');   // current IDs
  final newFormat = DateFormat('yyyy-MM-dd');   // target IDs

  for (final doc in snapshot.docs) {
    final oldId = doc.id;

    // Try to parse as dd-MM-yyyy
    DateTime date;
    try {
      date = oldFormat.parseStrict(oldId);
    } catch (_) {
      // Not in old format, skip (maybe already migrated)
      continue;
    }

    final newId = newFormat.format(date);

    // Already correct format? skip
    if (oldId == newId) continue;

    final data = doc.data();

    // Copy to new ID
    await dailyDataRef.doc(newId).set(data, SetOptions(merge: true));

    // Delete old
    await doc.reference.delete();
  }
}
Future<void> migrateAllUsersDailyData() async {
  final usersSnapshot =
  await FirebaseFirestore.instance.collection('users').get();

  for (final userDoc in usersSnapshot.docs) {
    final userId = userDoc.id;
    await migrateDailyDataForUser(userId);
  }
}
Future<void> migrateMealsForUser(String userId) async {
  final mealsCol = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('meals');

  final daySnapshot = await mealsCol.get();

  final oldFormat = DateFormat('dd-MM-yyyy');   // current IDs
  final newFormat = DateFormat('yyyy-MM-dd');   // target IDs

  for (final dayDoc in daySnapshot.docs) {
    final oldId = dayDoc.id;

    // Parse old dd-MM-yyyy id
    DateTime date;
    try {
      date = oldFormat.parseStrict(oldId);
    } catch (_) {
      // Not in old format, skip
      continue;
    }

    final newId = newFormat.format(date);

    if (oldId == newId) continue;

    // 1) Copy main day doc
    final dayData = dayDoc.data();
    final newDayDocRef = mealsCol.doc(newId);

    await newDayDocRef.set(dayData, SetOptions(merge: true));

    // 2) Copy subcollection mealEntries
    final entriesSnap =
    await dayDoc.reference.collection('mealEntries').get();

    for (final entryDoc in entriesSnap.docs) {
      await newDayDocRef
          .collection('mealEntries')
          .doc(entryDoc.id)
          .set(entryDoc.data(), SetOptions(merge: true));
    }

    // 3) Delete old subdocs then old parent
    for (final entryDoc in entriesSnap.docs) {
      await entryDoc.reference.delete();
    }

    await dayDoc.reference.delete();
  }
}
Future<void> migrateAllUsersMeals() async {
  final usersSnap =
  await FirebaseFirestore.instance.collection('users').get();

  for (final userDoc in usersSnap.docs) {
    final userId = userDoc.id;
    await migrateMealsForUser(userId);
  }
}
