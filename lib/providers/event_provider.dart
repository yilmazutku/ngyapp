import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../models/logger.dart';

class EventProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(EventProvider);

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

      logger.info('Fetched {} events for range {}-{}',
          [events.length, startDate, endDate]);
      return events;
    } catch (e) {
      logger.err('Error fetching events: {}', [e]);
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
      logger.info('Event created: {}', [newEvent]);
      notifyListeners();
      return newEvent;
    } catch (e) {
      logger.err('Error creating event: {}', [e]);
      rethrow;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await eventsCollection.doc(eventId).delete();
      logger.info('Event deleted: {}', [eventId]);
      notifyListeners();
    } catch (e) {
      logger.err('Error deleting event: {}', [e]);
      rethrow;
    }
  }
}
