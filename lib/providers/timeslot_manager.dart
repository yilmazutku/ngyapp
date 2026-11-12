import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';
import '../models/busy_slot.dart';
import '../models/event_model.dart';
import '../models/user_model.dart';
import 'event_provider.dart';
import 'user_provider.dart';

class TimeslotManager extends ChangeNotifier {
  TimeslotManager({FirebaseFirestore? db, String? Function()? currentUid})
      : _dbOverride = db,
        _currentUidOverride = currentUid;

  static const String _appointmentDateField = 'appointmentDateTime';
  static const String _postponedDateField = 'postponedDate';
  static const String _statusField = 'status';
  static const String _isDeletedField = 'isDeleted';

  final FirebaseFirestore? _dbOverride;
  final String? Function()? _currentUidOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  String? get _currentUid => _currentUidOverride != null
      ? _currentUidOverride()
      : FirebaseAuth.instance.currentUser?.uid;

  /// `busySlots` aynasını eski randevularla dolduran admin işlevi (bkz.
  /// functions/index.js).
  static const String _backfillBusySlotsFunction = 'backfillBusySlots';

  /// [backfillBusySlotsOnce] bu oturumda çağrıldı mı.
  bool _busySlotsBackfillRequested = false;

  // ---------------------- ADMIN TIME SLOTS ----------------------

  /// Fetches raw time slot strings for a specific date
  /// Returns a list of time strings in "HH:mm" format
  Future<List<String>> getAdminTimeSlotsAsStrings(DateTime date) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final timeslotDoc = await _db
          .collection('admininput')
          .doc('timeslots')
          .collection('dates')
          .doc(dateString)
          .get();

      if (!timeslotDoc.exists) {
        return [];
      }

      final data = timeslotDoc.data();
      if (data == null) {
        return [];
      }

      final List<dynamic> timesList = data['slots'] ?? [];
      return timesList.map<String>((e) => e.toString()).toList();
    } catch (e) {
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
      rethrow;
    }
  }

  // ---------------------- AVAILABILITY ----------------------

  Future<List<TimeOfDay>> getAvailableTimeSlotsForDate(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // The three reads do not depend on each other, so they run concurrently
      // instead of costing three sequential round trips. Danışan başka
      // danışanların randevularını okuyamaz; dolu saatler aynadan gelir.
      final adminSlotsFuture = getAdminTimeSlotsForDate(date);
      final busySlotsFuture = _fetchBusySlotsForDateRange(startOfDay, endOfDay);
      final eventsFuture = _fetchEventsForDateRange(startOfDay, endOfDay);

      final adminTimeSlots = await adminSlotsFuture;
      final dayBusySlots = await busySlotsFuture;
      final dayEvents = await eventsFuture;

      final availableSlots = adminTimeSlots.where((time) {
        if (!isTimeSlotAvailable(date, time, dayBusySlots)) {
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

      return availableSlots;
    } catch (e) {
      rethrow;
    }
  }

  bool isTimeSlotAvailable(
      DateTime date,
      TimeOfDay time,
      List<BusySlot>? dayBusySlots,
      ) {
    final dateTimeWithHour = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (dayBusySlots != null) {
      if (dateTimeWithHour.isBefore(DateTime.now())) return false;

      for (final busySlot in dayBusySlots) {
        if (busySlot.blocks(dateTimeWithHour)) {
          return false;
        }
      }
    }
    return true;
  }

  /// A slot is blocked if it falls within the appointment's duration [start, end).
  bool isSlotBlockedByAppointment(
      DateTime slotDateTime, AppointmentModel appointment) {
    return BusySlot.ofAppointment(appointment).blocks(slotDateTime);
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
      final docRef = _db
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
    } catch (e) {
      rethrow;
    }
  }

  /// Updates time slots for a specific date (overwrites existing)
  Future<void> updateTimeSlots(DateTime date, List<String> timeSlots) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final docRef = _db
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
    } catch (e) {
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
      final docRef = _db
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
          bookedTimeSlots.add(_slotKey(appointment.calendarDateTime));
        }

        if (bookedTimeSlots.isNotEmpty) {
          // Keep only booked slots
          await docRef.set({
            'slots': bookedTimeSlots.toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // No booked slots, delete document
          await docRef.delete();
        }
      } else {
        // Delete all slots regardless of bookings
        await docRef.delete();
      }
    } catch (e) {
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
      final slotDocFuture = _db
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

      final activeAppointments = appointments;

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
        final timeSlot = _slotKey(appointment.calendarDateTime);
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
      rethrow;
    }
  }

  /// `busySlots` aynası randevu yazıldıkça sunucuda güncellenir; ayna
  /// kurulmadan önceki randevular için admin uygulaması (Randevu Yönetimi)
  /// [_backfillBusySlotsFunction]'ı her oturumda bir kez çağırır. Sonuç
  /// beklenmez, hata yutulur; işlev yalnızca eksik ya da farklı aynayı yazar.
  Future<void> backfillBusySlotsOnce() async {
    if (_busySlotsBackfillRequested) return;
    _busySlotsBackfillRequested = true;
    try {
      final String? idToken =
          await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;
      await http.post(
        Uri.parse(
            '${UserProvider.functionsBaseUrl}/$_backfillBusySlotsFunction'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'data': <String, dynamic>{}}),
      );
    } catch (e) {
      // Yalnızca eski randevular için; ayna yeni yazımlarla zaten güncel.
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
    final snapshot = await EventProvider.eventsCollectionOf(_db)
        .where('startDateTime', isGreaterThanOrEqualTo: startDate)
        .where('startDateTime', isLessThan: endDate)
        .get();
    return snapshot.docs.map((d) => EventModel.fromDocument(d)).toList();
  }

  /// Reads the given users once each, in parallel, and returns them by id.
  /// A user that cannot be read is simply absent from the map.
  Future<Map<String, UserModel>> _fetchUsersByIds(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};

    final usersCollection = _db.collection('users');
    final ids = userIds.toList();
    final snapshots = await Future.wait(
      ids.map((id) => usersCollection.doc(id).get().then<DocumentSnapshot<Map<String, dynamic>>?>(
            (doc) => doc,
            onError: (Object e) {
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

  /// Gün aralığındaki dolu saatler (`busySlots` aynası); randevuların
  /// [_fetchAppointmentsForDateRange] ile aynı tarih süzgeci. Ayna sunucuda
  /// birkaç saniye geç güncellendiği için kullanıcının kendi randevuları
  /// ayrıca okunur.
  Future<List<BusySlot>> _fetchBusySlotsForDateRange(
      DateTime startDate,
      DateTime endDate,
      ) async {
    final String? uid = _currentUid;
    final List<List<BusySlot>> parts = await Future.wait([
      _fetchMirroredBusySlots(startDate, endDate),
      if (uid != null) _fetchOwnBusySlots(uid, startDate, endDate),
    ]);
    return [for (final List<BusySlot> part in parts) ...part];
  }

  /// Yayındaki kurallar `busySlots`'u henüz açmıyorsa (yeni sürüm kurallardan
  /// önce yayımlandı) eski yoldan, tüm randevulardan okunur.
  Future<List<BusySlot>> _fetchMirroredBusySlots(
      DateTime startDate,
      DateTime endDate,
      ) async {
    try {
      final snapshot = await _db
          .collection(BusySlot.collection)
          .where(BusySlot.startField, isGreaterThanOrEqualTo: startDate)
          .where(BusySlot.startField, isLessThan: endDate)
          .get();
      return snapshot.docs.map(BusySlot.fromDocument).toList();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      final appointments =
          await _fetchAppointmentsForDateRange(startDate, endDate);
      return appointments.map(BusySlot.ofAppointment).toList();
    }
  }

  Future<List<BusySlot>> _fetchOwnBusySlots(
      String uid,
      DateTime startDate,
      DateTime endDate,
      ) async {
    final CollectionReference<Map<String, dynamic>> appointments =
        _db.collection('users').doc(uid).collection('appointments');
    final List<AppointmentModel> own = await _appointmentsOnCalendar(
      byAppointmentDate: appointments
          .where(_appointmentDateField, isGreaterThanOrEqualTo: startDate)
          .where(_appointmentDateField, isLessThan: endDate),
      byPostponedDate: appointments
          .where(_postponedDateField, isGreaterThanOrEqualTo: startDate)
          .where(_postponedDateField, isLessThan: endDate),
      startDate: startDate,
      endDate: endDate,
    );
    return own.map(BusySlot.ofAppointment).toList();
  }

  /// Internal helper: fetch appointments across all users for a date range.
  /// Yalnızca admin okuyabilir; danışan tarafı [_fetchBusySlotsForDateRange].
  Future<List<AppointmentModel>> _fetchAppointmentsForDateRange(
      DateTime startDate,
      DateTime endDate,
      ) {
    final Query<Map<String, dynamic>> appointments =
        _db.collectionGroup('appointments');
    return _appointmentsOnCalendar(
      byAppointmentDate: appointments
          .where(_appointmentDateField, isGreaterThanOrEqualTo: startDate)
          .where(_appointmentDateField, isLessThan: endDate),
      byPostponedDate: appointments
          .where(_isDeletedField, isNull: true)
          .where(_statusField, isEqualTo: AppointmentStatus.postponed.label)
          .where(_postponedDateField, isGreaterThanOrEqualTo: startDate)
          .where(_postponedDateField, isLessThan: endDate),
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<List<AppointmentModel>> _appointmentsOnCalendar({
    required Query<Map<String, dynamic>> byAppointmentDate,
    required Query<Map<String, dynamic>> byPostponedDate,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final List<QuerySnapshot<Map<String, dynamic>>> snapshots =
        await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
      byAppointmentDate.get(),
      byPostponedDate.get(),
    ]);
    final Map<String, AppointmentModel> byPath = <String, AppointmentModel>{};
    for (final QuerySnapshot<Map<String, dynamic>> snapshot in snapshots) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        if (doc.data()[_appointmentDateField] is! Timestamp) continue;
        final AppointmentModel appointment = AppointmentModel.fromDocument(doc);
        final DateTime start = appointment.calendarDateTime;
        if (start.isBefore(startDate) || !start.isBefore(endDate)) continue;
        byPath[doc.reference.path] = appointment;
      }
    }
    return byPath.values.toList();
  }
}
