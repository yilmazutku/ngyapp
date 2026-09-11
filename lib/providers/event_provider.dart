import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/event_model.dart';

class EventProvider extends ChangeNotifier {
  static CollectionReference get eventsCollection =>
      FirebaseFirestore.instance.collection('admininput').doc('events').collection('items');

  Future<List<EventModel>> fetchEventsForDateRange(
      DateTime startDate, DateTime endDate) async {
    try {
      final snapshot = await eventsCollection
          .where('startDateTime', isGreaterThanOrEqualTo: startDate)
          .where('startDateTime', isLessThan: endDate)
          .get();

      final events =
          snapshot.docs.map((doc) => EventModel.fromDocument(doc)).toList();

      return events;
    } catch (e) {
      rethrow;
    }
  }

  Future<EventModel> addEvent(EventModel event) async {
    try {
      final docRef = eventsCollection.doc();
      final newEvent = EventModel(
        eventId: docRef.id,
        name: event.name,
        startDateTime: event.startDateTime,
        endDateTime: event.endDateTime,
        createDate: event.createDate,
      );
      await docRef.set(newEvent.toMap());
      notifyListeners();
      return newEvent;
    } catch (e) {
      rethrow;
    }
  }

  Future<EventModel> updateEvent(EventModel event) async {
    try {
      await eventsCollection.doc(event.eventId).update({
        'name': event.name,
        'startDateTime': Timestamp.fromDate(event.startDateTime),
        'endDateTime': Timestamp.fromDate(event.endDateTime),
      });
      notifyListeners();
      return event;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await eventsCollection.doc(eventId).delete();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
