import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';
import '../models/event_model.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import 'event_provider.dart';

class TimeslotManager extends ChangeNotifier {
  final Logger logger = Logger.forClass(TimeslotManager);

  TimeslotManager();

  // ---------------------- ADMIN TIME SLOTS ----------------------

  /// Fetches raw time slot strings for a specific date
  /// Returns a list of time strings in "HH:mm" format
  Future<List<String>> getAdminTimeSlotsAsStrings(DateTime date) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final timeslotDoc = await FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString)
          .get();

      if (!timeslotDoc.exists) {
        logger.info('No admin time slots for date {}', [dateString]);
        return [];
      }

      final data = timeslotDoc.data();
      if (data == null) {
        logger.err('Document exists but data is null for date {}', [dateString]);
        return [];
      }

      logger.info('Document data for {}: {}', [dateString, data]);
      final List<dynamic> timesList = data['slots'] ?? [];
      return timesList.map<String>((e) => e.toString()).toList();
    } catch (e) {
      logger.err('Error fetching admin time slots for date {}: {}', [date, e]);
      rethrow;
    }
  }

  Future<List<TimeOfDay>> getAdminTimeSlotsForDate(DateTime date) async {
    try {
      final timeStrings = await getAdminTimeSlotsAsStrings(date);
      return timeStrings.map<TimeOfDay>((timeString) {
        final parts = timeString.split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }).toList();
    } catch (e) {
      logger.err('Error fetching admin time slots for date {}: {}', [date, e]);
      rethrow;
    }
  }

  // ---------------------- AVAILABILITY ----------------------

  Future<List<TimeOfDay>> getAvailableTimeSlotsForDate(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // The three reads do not depend on each other, so they run concurrently
      // instead of costing three sequential round trips.
      final adminSlotsFuture = getAdminTimeSlotsForDate(date);
      final appointmentsFuture =
          _fetchAppointmentsForDateRange(startOfDay, endOfDay);
      final eventsFuture = _fetchEventsForDateRange(startOfDay, endOfDay);

      final adminTimeSlots = await adminSlotsFuture;
      final dayAppointments = await appointmentsFuture;
      final dayEvents = await eventsFuture;

      final availableSlots = adminTimeSlots.where((time) {
        if (!isTimeSlotAvailable(date, time, dayAppointments)) {
          return false;
        }
        final slotDt = DateTime(
            date.year, date.month, date.day, time.hour, time.minute);
        for (final event in dayEvents) {
          if (isSlotBlockedByEvent(slotDt, event)) {
            return false;
          }
        }
        return true;
      }).toList();

      logger.info(
        'Available time slots for date {}: {}',
        [date, availableSlots],
      );
      return availableSlots;
    } catch (e) {
      logger.err(
        'Error fetching available time slots for date {}: {}',
        [date, e],
      );
      rethrow;
    }
  }

  bool isTimeSlotAvailable(
      DateTime date,
      TimeOfDay time,
      List<AppointmentModel>? dayAppointments,
      ) {
    final dateTimeWithHour = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (dayAppointments != null) {
      if (dateTimeWithHour.isBefore(DateTime.now())) return false;

      for (var appointment in dayAppointments) {
        if (isSlotBlockedByAppointment(dateTimeWithHour, appointment)) {
          return false;
        }
      }
    }
    return true;
  }

  /// A slot is blocked if it falls within the appointment's duration [start, end).
  bool isSlotBlockedByAppointment(
      DateTime slotDateTime, AppointmentModel appointment) {
    if (appointment.status == AppointmentStatus.canceled) return false;

    final apptStart = appointment.appointmentDateTime;
    final apptEnd =
        apptStart.add(Duration(minutes: appointment.durationMinutes));

    return !slotDateTime.isBefore(apptStart) && slotDateTime.isBefore(apptEnd);
  }

  /// A slot is blocked if it falls within the event's duration [start, end).
  bool isSlotBlockedByEvent(DateTime slotDateTime, EventModel event) {
    final eventStart = event.startDateTime;
    final eventEnd = event.endDateTime;

    return !slotDateTime.isBefore(eventStart) &&
        slotDateTime.isBefore(eventEnd);
  }

  // ---------------------- TIMESLOT CRUD ----------------------

  /// Saves time slots for a specific date
  /// Merges with existing slots to avoid duplicates
  Future<void> saveTimeSlots(DateTime date, List<String> timeSlots) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final docRef = FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString);

      // arrayUnion appends only the slots that are not stored yet, so the merge
      // happens server-side: no read-modify-write, and two admins saving at the
      // same time can no longer overwrite each other's slots.
      await docRef.set(
        {
          'slots': FieldValue.arrayUnion(timeSlots),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      logger.info(
        'Saved {} time slots for date {}',
        [timeSlots.length, dateString],
      );
    } catch (e) {
      logger.err('Error saving time slots for date {}: {}', [date, e]);
      rethrow;
    }
  }

  /// Updates time slots for a specific date (overwrites existing)
  Future<void> updateTimeSlots(DateTime date, List<String> timeSlots) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final docRef = FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString);

      await docRef.set(
        {
          'slots': timeSlots,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      logger.info(
        'Updated time slots for date {}. Total: {}',
        [dateString, timeSlots.length],
      );
    } catch (e) {
      logger.err('Error updating time slots for date {}: {}', [date, e]);
      rethrow;
    }
  }

  /// Deletes all time slots for a specific date
  /// If preserveBooked is true, keeps time slots that have appointments
  Future<void> deleteTimeSlots(
      DateTime date, {
        bool preserveBooked = true,
      }) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final docRef = FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString);

      if (preserveBooked) {
        // Fetch appointments for the date (all users)
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));

        final appointments =
        await _fetchAppointmentsForDateRange(startOfDay, endOfDay);

        // Extract booked time slots. A set: two appointments sharing a start
        // time must not write the same slot twice.
        final bookedTimeSlots = <String>{};
        for (var appointment in appointments) {
          if (appointment.status != AppointmentStatus.canceled) {
            bookedTimeSlots.add(_slotKey(appointment.appointmentDateTime));
          }
        }

        if (bookedTimeSlots.isNotEmpty) {
          // Keep only booked slots
          await docRef.set({
            'slots': bookedTimeSlots.toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          logger.info(
            'Deleted unbooked time slots for date {}. Preserved {} booked slots',
            [dateString, bookedTimeSlots.length],
          );
        } else {
          // No booked slots, delete document
          await docRef.delete();
          logger.info(
            'Deleted all time slots for date {} (no bookings)',
            [dateString],
          );
        }
      } else {
        // Delete all slots regardless of bookings
        await docRef.delete();
        logger.info('Deleted all time slots for date {}', [dateString]);
      }
    } catch (e) {
      logger.err('Error deleting time slots for date {}: {}', [date, e]);
      rethrow;
    }
  }

  /// Returns:
  ///  - storedTimes: List<String>
  ///  - hasAppointment: Map<String, bool>
  ///  - bookedTimeSlots: List<String>
  ///  - appointmentsBySlot: Map<String, List<AppointmentModel>>
  Future<Map<String, dynamic>> fetchTimeslotDataForDate(DateTime date) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Stored slots, appointments and events are independent reads, so they
      // are issued together rather than one after the other.
      final slotDocFuture = FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString)
          .get();
      final appointmentsFuture =
          _fetchAppointmentsForDateRange(startOfDay, endOfDay);
      final eventsFuture = _fetchEventsForDateRange(startOfDay, endOfDay);

      final docSnapshot = await slotDocFuture;
      final List<dynamic> rawSlots =
      docSnapshot.exists ? (docSnapshot.data()?['slots'] ?? []) : [];
      final List<String> adminSlots =
      rawSlots.map((e) => e.toString()).toList();
      final List<String> storedTimes = List<String>.from(adminSlots);
      // Mirrors storedTimes for O(1) membership tests.
      final storedTimeSet = storedTimes.toSet();

      final appointments = await appointmentsFuture;

      final hasAppointment = <String, bool>{};
      final bookedTimeSlots = <String>{};
      final appointmentsBySlot = <String, List<AppointmentModel>>{};

      final activeAppointments = appointments
          .where((a) => a.status != AppointmentStatus.canceled)
          .toList();

      // One read per client, in parallel: several appointments of the day
      // usually belong to the same person.
      final userCache = await _fetchUsersByIds(
        activeAppointments.map((a) => a.userId).toSet(),
      );
      for (final appt in activeAppointments) {
        appt.user = userCache[appt.userId];
      }

      // Ensure each appointment's own start-time slot exists in storedTimes
      for (var appointment in activeAppointments) {
        final timeSlot = _slotKey(appointment.appointmentDateTime);
        if (storedTimeSet.add(timeSlot)) {
          storedTimes.add(timeSlot);
        }
      }

      final dayEvents = await eventsFuture;
      final eventsBySlot = <String, List<EventModel>>{};

      // Check every stored slot against every active appointment and event
      for (final slotStr in storedTimes) {
        final parts = slotStr.split(':');
        final slotDateTime = startOfDay.add(
          Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])),
        );

        for (final appointment in activeAppointments) {
          if (isSlotBlockedByAppointment(slotDateTime, appointment)) {
            hasAppointment[slotStr] = true;
            bookedTimeSlots.add(slotStr);
            final slotAppointments =
                appointmentsBySlot.putIfAbsent(slotStr, () => []);
            if (!slotAppointments
                .any((a) => a.appointmentId == appointment.appointmentId)) {
              slotAppointments.add(appointment);
            }
          }
        }

        for (final event in dayEvents) {
          if (isSlotBlockedByEvent(slotDateTime, event)) {
            hasAppointment[slotStr] = true;
            bookedTimeSlots.add(slotStr);
            final slotEvents = eventsBySlot.putIfAbsent(slotStr, () => []);
            if (!slotEvents.any((e) => e.eventId == event.eventId)) {
              slotEvents.add(event);
            }
          }
        }
      }

      // Keep times sorted everywhere
      storedTimes.sort((a, b) {
        final ap = a.split(':');
        final bp = b.split(':');
        final am = int.parse(ap[0]) * 60 + int.parse(ap[1]);
        final bm = int.parse(bp[0]) * 60 + int.parse(bp[1]);
        return am.compareTo(bm);
      });

      logger.info(
        'Fetched timeslot data for date {}. Stored: {}, Booked: {}',
        [dateString, storedTimes.length, bookedTimeSlots.length],
      );

      return {
        'storedTimes': storedTimes,
        'adminSlots': adminSlots,
        'hasAppointment': hasAppointment,
        'bookedTimeSlots': bookedTimeSlots.toList(),
        'appointmentsBySlot': appointmentsBySlot,
        'eventsBySlot': eventsBySlot,
        'events': dayEvents,
      };
    } catch (e) {
      logger.err('Error fetching timeslot data for date {}: {}', [date, e]);
      rethrow;
    }
  }

  // ---------------------- PRIVATE HELPERS ----------------------

  /// "HH:mm" key a date-time falls on; the format slots are stored in.
  static String _slotKey(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Internal helper: fetch the events overlapping a date range.
  Future<List<EventModel>> _fetchEventsForDateRange(
      DateTime startDate,
      DateTime endDate,
      ) async {
    final snapshot = await EventProvider.eventsCollection
        .where('startDateTime', isGreaterThanOrEqualTo: startDate)
        .where('startDateTime', isLessThan: endDate)
        .get();
    return snapshot.docs.map((d) => EventModel.fromDocument(d)).toList();
  }

  /// Reads the given users once each, in parallel, and returns them by id.
  /// A user that cannot be read is simply absent from the map.
  Future<Map<String, UserModel>> _fetchUsersByIds(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};

    final usersCollection = FirebaseFirestore.instance.collection('users');
    final ids = userIds.toList();
    final snapshots = await Future.wait(
      ids.map((id) => usersCollection.doc(id).get().then<DocumentSnapshot<Map<String, dynamic>>?>(
            (doc) => doc,
            onError: (Object e) {
              logger.warn('Could not read user {}: {}', [id, e]);
              return null;
            },
          )),
    );

    final result = <String, UserModel>{};
    for (int i = 0; i < ids.length; i++) {
      final doc = snapshots[i];
      if (doc != null && doc.exists) {
        result[ids[i]] = UserModel.fromDocument(doc);
      }
    }
    return result;
  }

  /// Internal helper: fetch appointments across all users for a date range.
  Future<List<AppointmentModel>> _fetchAppointmentsForDateRange(
      DateTime startDate,
      DateTime endDate,
      ) async {
    try {
      Query query = FirebaseFirestore.instance
          .collectionGroup('appointments')
          .where('appointmentDateTime', isGreaterThanOrEqualTo: startDate)
          .where('appointmentDateTime', isLessThan: endDate);

      final snapshot = await query.get();
      final appointments = snapshot.docs
          .map((doc) => AppointmentModel.fromDocument(doc))
          .toList();

      logger.info(
        'Fetched {} appointments for date range {}-{}',
        [appointments.length, startDate, endDate],
      );
      return appointments;
    } catch (e) {
      logger.err('Error fetching appointments for date range: {}', [e]);
      rethrow;
    }
  }
}
