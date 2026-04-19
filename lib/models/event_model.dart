import 'package:cloud_firestore/cloud_firestore.dart';

class EventModel {
  final String eventId;
  final String name;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final DateTime createDate;

  EventModel({
    required this.eventId,
    required this.name,
    required this.startDateTime,
    required this.endDateTime,
    required this.createDate,
  });

  int get durationMinutes =>
      endDateTime.difference(startDateTime).inMinutes;

  factory EventModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel(
      eventId: doc.id,
      name: data['name'] ?? '',
      startDateTime: (data['startDateTime'] as Timestamp).toDate(),
      endDateTime: (data['endDateTime'] as Timestamp).toDate(),
      createDate: data['createDate'] != null
          ? (data['createDate'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'createDate': Timestamp.fromDate(createDate),
    };
  }

  @override
  String toString() {
    return 'EventModel{eventId: $eventId, name: $name, start: $startDateTime, end: $endDateTime}';
  }
}
