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
      final adminTimeSlots = await getAdminTimeSlotsForDate(date);

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final appointmentSnapshot = await FirebaseFirestore.instance
          .collectionGroup('appointments')
          .where('appointmentDateTime', isGreaterThanOrEqualTo: startOfDay)
          .where('appointmentDateTime', isLessThan: endOfDay)
          .get();

      final dayAppointments = appointmentSnapshot.docs
          .map((doc) => AppointmentModel.fromDocument(doc))
          .toList();

      // Also fetch events for the day
      final dayEvents =
          await EventProvider.eventsCollection
              .where('startDateTime', isGreaterThanOrEqualTo: startOfDay)
              .where('startDateTime', isLessThan: endOfDay)
              .get()
              .then((snap) =>
                  snap.docs.map((d) => EventModel.fromDocument(d)).toList());

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

      // Get existing slots to avoid duplicates
      final docSnapshot = await docRef.get();
      final List<dynamic> rawSlots =
      docSnapshot.exists ? (docSnapshot.data()?['slots'] ?? []) : [];
      final List<String> existingSlots =
      rawSlots.map((e) => e.toString()).toList();

      // Merge and deduplicate
      final allSlots = {...existingSlots, ...timeSlots}.toList();

      await docRef.set(
        {
          'slots': allSlots,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      logger.info(
        'Saved {} time slots for date {}',
        [allSlots.length, dateString],
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

        // Extract booked time slots
        final bookedTimeSlots = <String>[];
        for (var appointment in appointments) {
          if (appointment.status != AppointmentStatus.canceled) {
            final hour =
            appointment.appointmentDateTime.hour.toString().padLeft(2, '0');
            final minute = appointment
                .appointmentDateTime.minute
                .toString()
                .padLeft(2, '0');
            final timeSlot = '$hour:$minute';
            bookedTimeSlots.add(timeSlot);
          }
        }

        if (bookedTimeSlots.isNotEmpty) {
          // Keep only booked slots
          await docRef.set({
            'slots': bookedTimeSlots,
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
      final docSnapshot = await FirebaseFirestore.instance
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString)
          .get();

      final List<dynamic> rawSlots =
      docSnapshot.exists ? (docSnapshot.data()?['slots'] ?? []) : [];
      final List<String> adminSlots =
      rawSlots.map((e) => e.toString()).toList();
      final List<String> storedTimes = List<String>.from(adminSlots);

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final appointments =
      await _fetchAppointmentsForDateRange(startOfDay, endOfDay);

      final hasAppointment = <String, bool>{};
      final bookedTimeSlots = <String>[];
      final appointmentsBySlot = <String, List<AppointmentModel>>{};

      final activeAppointments = appointments
          .where((a) => a.status != AppointmentStatus.canceled)
          .toList();

      // Batch-fetch user data for all active appointments
      final uniqueUserIds =
          activeAppointments.map((a) => a.userId).toSet();
      final usersCollection = FirebaseFirestore.instance.collection('users');
      final userCache = <String, UserModel>{};
      for (final uid in uniqueUserIds) {
        try {
          final doc = await usersCollection.doc(uid).get();
          if (doc.exists) {
            userCache[uid] = UserModel.fromDocument(doc);
          }
        } catch (_) {}
      }
      for (final appt in activeAppointments) {
        appt.user = userCache[appt.userId];
      }

      // Ensure each appointment's own start-time slot exists in storedTimes
      for (var appointment in activeAppointments) {
        final hour =
            appointment.appointmentDateTime.hour.toString().padLeft(2, '0');
        final minute =
            appointment.appointmentDateTime.minute.toString().padLeft(2, '0');
        final timeSlot = '$hour:$minute';
        if (!storedTimes.contains(timeSlot)) {
          storedTimes.add(timeSlot);
        }
      }

      // Fetch events for the day
      final dayEvents = await EventProvider.eventsCollection
          .where('startDateTime', isGreaterThanOrEqualTo: startOfDay)
          .where('startDateTime', isLessThan: endOfDay)
          .get()
          .then((snap) =>
              snap.docs.map((d) => EventModel.fromDocument(d)).toList());

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
            if (!bookedTimeSlots.contains(slotStr)) {
              bookedTimeSlots.add(slotStr);
            }
            appointmentsBySlot.putIfAbsent(slotStr, () => []);
            if (!appointmentsBySlot[slotStr]!
                .any((a) => a.appointmentId == appointment.appointmentId)) {
              appointmentsBySlot[slotStr]!.add(appointment);
            }
          }
        }

        for (final event in dayEvents) {
          if (isSlotBlockedByEvent(slotDateTime, event)) {
            hasAppointment[slotStr] = true;
            if (!bookedTimeSlots.contains(slotStr)) {
              bookedTimeSlots.add(slotStr);
            }
            eventsBySlot.putIfAbsent(slotStr, () => []);
            if (!eventsBySlot[slotStr]!
                .any((e) => e.eventId == event.eventId)) {
              eventsBySlot[slotStr]!.add(event);
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
        'bookedTimeSlots': bookedTimeSlots,
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
