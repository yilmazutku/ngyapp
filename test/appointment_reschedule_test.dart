import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/providers/appointment_manager.dart';
import 'package:ngy_app/providers/sub_provider.dart';

class _RecordingSubProvider extends SubProvider {
  final List<({String userId, String subscriptionId, int delta})> adjustments =
      [];

  @override
  Future<bool> adjustPostponementsUsed({
    required String userId,
    required String subscriptionId,
    required int delta,
    String updateUser = 'admin',
  }) async {
    adjustments
        .add((userId: userId, subscriptionId: subscriptionId, delta: delta));
    return true;
  }
}

class _RecordingAppointmentManager extends AppointmentManager {
  _RecordingAppointmentManager(this.subs) : super(subProvider: subs);

  final _RecordingSubProvider subs;
  final List<AppointmentModel> updates = [];

  @override
  Future<void> updateAppointment(AppointmentModel updated) async {
    updates.add(updated);
  }
}

final DateTime _firstDate = DateTime(2026, 11, 10, 10);
final DateTime _postponedDate = DateTime(2026, 11, 12, 14, 30);
final DateTime _newStart = DateTime(2026, 11, 13, 16, 40);

AppointmentModel _appointment({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? postponedDate,
  PostponeSource? postponedBy,
  List<DateTime> repostponedFrom = const <DateTime>[],
  String? subscriptionId = 's1',
}) =>
    AppointmentModel(
      appointmentId: 'a1',
      userId: 'u1',
      subscriptionId: subscriptionId,
      meetingType: MeetingType.online,
      appointmentType: AppointmentType.haftalik,
      appointmentDateTime: _firstDate,
      status: status,
      notes: 'not',
      createDate: DateTime(2026, 11, 1),
      createUser: 'kuran',
      postponedDate: postponedDate,
      postponedBy: postponedBy,
      repostponedFrom: repostponedFrom,
      durationMinutes: 20,
    );

void main() {
  group('sürüklenebilirlik', () {
    test('yalnızca Planlandı ve Ertelendi randevular taşınabilir', () {
      expect(_appointment().isReschedulable, isTrue);
      expect(_appointment(status: AppointmentStatus.postponed).isReschedulable,
          isTrue);
      expect(_appointment(status: AppointmentStatus.completed).isReschedulable,
          isFalse);
      expect(_appointment(status: AppointmentStatus.burned).isReschedulable,
          isFalse);
    });
  });

  group('rescheduledTo', () {
    test(
        'hak düşülmezse planlanan randevu yalnızca düzenlenir: durum '
        'Planlandı kalır, tarih değişir', () {
      final AppointmentModel moved = _appointment()
          .rescheduledTo(_newStart, deductPostponementRight: false);

      expect(moved.status, AppointmentStatus.scheduled);
      expect(moved.appointmentDateTime, _newStart);
      expect(moved.postponedDate, isNull);
      expect(moved.postponedBy, isNull);
      expect(moved.wasPostponed, isFalse);
    });

    test(
        'hak düşülürse planlanan randevu Ertelendi olur, kaynak danışan '
        'kaynaklı seçilir, ilk tarih korunur', () {
      final AppointmentModel moved = _appointment()
          .rescheduledTo(_newStart, deductPostponementRight: true);

      expect(moved.status, AppointmentStatus.postponed);
      expect(moved.postponedBy, PostponeSource.user);
      expect(moved.postponedDate, _newStart);
      expect(moved.appointmentDateTime, _firstDate);
      expect(moved.effectiveDateTime, _newStart);
    });

    test(
        'ofis kaynaklı ertelenmiş randevu hak düşülmeden taşınırsa yalnızca '
        'ertelendiği tarih değişir', () {
      final AppointmentModel moved = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.admin,
      ).rescheduledTo(_newStart, deductPostponementRight: false);

      expect(moved.status, AppointmentStatus.postponed);
      expect(moved.postponedBy, PostponeSource.admin);
      expect(moved.postponedDate, _newStart);
      expect(moved.appointmentDateTime, _firstDate);
    });

    test(
        'ofis kaynaklı ertelenmiş randevuda hak düşülürse kaynak danışan '
        'kaynaklı olur', () {
      final AppointmentModel moved = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.admin,
      ).rescheduledTo(_newStart, deductPostponementRight: true);

      expect(moved.status, AppointmentStatus.postponed);
      expect(moved.postponedBy, PostponeSource.user);
      expect(moved.postponedDate, _newStart);
    });

    test(
        'yeni tarihi seçilmemiş ertelenmiş randevunun ertelendiği tarih '
        'doldurulur', () {
      final AppointmentModel moved = _appointment(
        status: AppointmentStatus.postponed,
        postponedBy: PostponeSource.user,
      ).rescheduledTo(_newStart, deductPostponementRight: false);

      expect(moved.status, AppointmentStatus.postponed);
      expect(moved.postponedBy, PostponeSource.user);
      expect(moved.postponedDate, _newStart);
      expect(moved.appointmentDateTime, _firstDate);
    });

    test(
        'danışan kaynaklı ertelenmiş randevuda tekrar erteleme seçilirse '
        'önceki ertelendiği tarih tekrar ertelemelere eklenir', () {
      final AppointmentModel moved = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.user,
      ).rescheduledTo(_newStart, deductPostponementRight: true);

      expect(moved.status, AppointmentStatus.postponed);
      expect(moved.postponedBy, PostponeSource.user);
      expect(moved.appointmentDateTime, _firstDate);
      expect(moved.postponedDate, _newStart);
      expect(moved.repostponedFrom, [_postponedDate]);
      expect(moved.postponementRightsSpent, 2);

      final DateTime later = DateTime(2026, 11, 20, 9);
      final AppointmentModel movedAgain =
          moved.rescheduledTo(later, deductPostponementRight: true);
      expect(movedAgain.repostponedFrom, [_postponedDate, _newStart]);
      expect(movedAgain.postponedDate, later);
      expect(movedAgain.postponementRightsSpent, 3);
    });

    test(
        'tekrar erteleme seçilmezse yalnızca ertelendiği tarih değişir, '
        'tekrar ertelemeler korunur', () {
      final AppointmentModel moved = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.user,
        repostponedFrom: [_firstDate.add(const Duration(days: 1))],
      ).rescheduledTo(_newStart, deductPostponementRight: false);

      expect(moved.postponedDate, _newStart);
      expect(moved.repostponedFrom, [_firstDate.add(const Duration(days: 1))]);
      expect(moved.postponementRightsSpent, 2);
    });

    test('diğer alanlar korunur, güncelleme bilgisi yazılır', () {
      final AppointmentModel original = _appointment();
      final AppointmentModel moved =
          original.rescheduledTo(_newStart, deductPostponementRight: true);

      expect(moved.appointmentId, original.appointmentId);
      expect(moved.userId, original.userId);
      expect(moved.subscriptionId, original.subscriptionId);
      expect(moved.meetingType, original.meetingType);
      expect(moved.appointmentType, original.appointmentType);
      expect(moved.durationMinutes, original.durationMinutes);
      expect(moved.notes, original.notes);
      expect(moved.createDate, original.createDate);
      expect(moved.createUser, original.createUser);
      expect(moved.updateUser, 'admin');
      expect(moved.updateDate, isNotNull);
    });
  });

  group('erteleme hakları', () {
    test('randevunun harcadığı erteleme hakkı sayısı', () {
      expect(_appointment().postponementRightsSpent, 0);
      expect(
          _appointment(
            status: AppointmentStatus.postponed,
            postponedBy: PostponeSource.admin,
          ).postponementRightsSpent,
          0);
      expect(
          _appointment(
            status: AppointmentStatus.postponed,
            postponedBy: PostponeSource.user,
          ).postponementRightsSpent,
          1);
      expect(
          _appointment(
            status: AppointmentStatus.completed,
            postponedDate: _newStart,
            postponedBy: PostponeSource.user,
            repostponedFrom: [_postponedDate],
          ).postponementRightsSpent,
          2);
    });

    test('ham dokümandan da aynı sayı okunur', () {
      expect(AppointmentModel.postponementRightsSpentIn(<String, dynamic>{}),
          0);
      expect(
          AppointmentModel.postponementRightsSpentIn(<String, dynamic>{
            'postponedBy': 'user',
          }),
          1);
      expect(
          AppointmentModel.postponementRightsSpentIn(<String, dynamic>{
            'postponedBy': 'user',
            AppointmentModel.repostponedFromField: <Timestamp>[
              Timestamp.fromDate(_postponedDate),
              Timestamp.fromDate(_newStart),
            ],
          }),
          3);
    });

    test('yalnızca tekrar ertelenmiş randevu tekrar ertelemeleri yazar', () {
      expect(
          _appointment().toMap().containsKey(
              AppointmentModel.repostponedFromField),
          isFalse);

      final Map<String, dynamic> map = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _newStart,
        postponedBy: PostponeSource.user,
        repostponedFrom: [_postponedDate],
      ).toMap();
      expect(map[AppointmentModel.repostponedFromField],
          [Timestamp.fromDate(_postponedDate)]);
    });

    test('güncellemede boşalan tekrar ertelemeler dokümandan silinir', () {
      expect(_appointment().toUpdateMap()[AppointmentModel.repostponedFromField],
          FieldValue.delete());

      final Map<String, dynamic> map = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _newStart,
        postponedBy: PostponeSource.user,
        repostponedFrom: [_postponedDate],
      ).toUpdateMap();
      expect(map[AppointmentModel.repostponedFromField],
          [Timestamp.fromDate(_postponedDate)]);
    });

    test('tekrar erteleme yalnızca tarihi belli danışan kaynaklı ertelemede '
        'sorulur', () {
      expect(
          _appointment(
            status: AppointmentStatus.postponed,
            postponedDate: _postponedDate,
            postponedBy: PostponeSource.user,
          ).canBeRepostponed,
          isTrue);
      expect(
          _appointment(
            status: AppointmentStatus.postponed,
            postponedBy: PostponeSource.user,
          ).canBeRepostponed,
          isFalse);
      expect(
          _appointment(
            status: AppointmentStatus.postponed,
            postponedDate: _postponedDate,
            postponedBy: PostponeSource.admin,
          ).canBeRepostponed,
          isFalse);
      expect(
          _appointment(
            status: AppointmentStatus.completed,
            postponedDate: _postponedDate,
            postponedBy: PostponeSource.user,
          ).canBeRepostponed,
          isFalse);
    });
  });

  group('AppointmentManager.rescheduleAppointment', () {
    late _RecordingSubProvider subs;
    late _RecordingAppointmentManager manager;

    setUp(() {
      subs = _RecordingSubProvider();
      manager = _RecordingAppointmentManager(subs);
    });

    test(
        'hak düşülürse randevu ertelenir ve paketten bir erteleme hakkı '
        'düşülür', () async {
      await manager.rescheduleAppointment(_appointment(), _newStart,
          deductPostponementRight: true);

      expect(manager.updates.single.status, AppointmentStatus.postponed);
      expect(manager.updates.single.postponedBy, PostponeSource.user);
      expect(manager.updates.single.postponedDate, _newStart);
      expect(
          subs.adjustments, [(userId: 'u1', subscriptionId: 's1', delta: 1)]);
    });

    test('hak düşülmezse randevu yalnızca düzenlenir, sayaç değişmez',
        () async {
      await manager.rescheduleAppointment(_appointment(), _newStart,
          deductPostponementRight: false);

      expect(manager.updates.single.status, AppointmentStatus.scheduled);
      expect(manager.updates.single.appointmentDateTime, _newStart);
      expect(subs.adjustments, isEmpty);
    });

    test('paketsiz randevuda sayaç değişmez', () async {
      for (final String? subscriptionId in <String?>[null, '']) {
        await manager.rescheduleAppointment(
            _appointment(subscriptionId: subscriptionId), _newStart,
            deductPostponementRight: true);
      }

      expect(manager.updates, hasLength(2));
      expect(manager.updates.every((a) => a.postponedBy == PostponeSource.user),
          isTrue);
      expect(subs.adjustments, isEmpty);
    });

    test(
        'hakkı daha önce düşülmüş randevu yalnızca tarihi değiştirilerek '
        'taşınırsa ikinci kez düşülmez', () async {
      final AppointmentModel alreadySpent = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.user,
      );

      await manager.rescheduleAppointment(alreadySpent, _newStart,
          deductPostponementRight: false);

      expect(manager.updates.single.postponedDate, _newStart);
      expect(manager.updates.single.repostponedFrom, isEmpty);
      expect(subs.adjustments, isEmpty);
    });

    test(
        'hakkı daha önce düşülmüş randevu tekrar ertelenirse paketten bir '
        'erteleme hakkı daha düşülür', () async {
      final AppointmentModel alreadySpent = _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: _postponedDate,
        postponedBy: PostponeSource.user,
      );

      await manager.rescheduleAppointment(alreadySpent, _newStart,
          deductPostponementRight: true);

      expect(manager.updates.single.postponedDate, _newStart);
      expect(manager.updates.single.repostponedFrom, [_postponedDate]);
      expect(
          subs.adjustments, [(userId: 'u1', subscriptionId: 's1', delta: 1)]);
    });

    test(
        'yeni tarihi seçilmemiş danışan kaynaklı ertelemede tarih '
        'doldurulurken hak yeniden düşülmez', () async {
      await manager.rescheduleAppointment(
        _appointment(
          status: AppointmentStatus.postponed,
          postponedBy: PostponeSource.user,
        ),
        _newStart,
        deductPostponementRight: true,
      );

      expect(manager.updates.single.postponedDate, _newStart);
      expect(manager.updates.single.repostponedFrom, isEmpty);
      expect(subs.adjustments, isEmpty);
    });

    test('ofis kaynaklı erteleme danışan kaynaklıya çevrilirse hak düşülür',
        () async {
      await manager.rescheduleAppointment(
        _appointment(
          status: AppointmentStatus.postponed,
          postponedDate: _postponedDate,
          postponedBy: PostponeSource.admin,
        ),
        _newStart,
        deductPostponementRight: true,
      );

      expect(
          subs.adjustments, [(userId: 'u1', subscriptionId: 's1', delta: 1)]);
    });

    test('randevu yazılamazsa hak düşülmez', () async {
      final _FailingAppointmentManager failing =
          _FailingAppointmentManager(subs);

      await expectLater(
        failing.rescheduleAppointment(_appointment(), _newStart,
            deductPostponementRight: true),
        throwsStateError,
      );
      expect(subs.adjustments, isEmpty);
    });
  });
}

class _FailingAppointmentManager extends AppointmentManager {
  _FailingAppointmentManager(SubProvider subs) : super(subProvider: subs);

  @override
  Future<void> updateAppointment(AppointmentModel updated) async {
    throw StateError('yazılamadı');
  }
}
