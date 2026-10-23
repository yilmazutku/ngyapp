import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/utils/dialog_utils.dart';
import 'package:ngy_app/utils/postponement_notices.dart';

void main() {
  const String returnOption = 'Danışana Erteleme Hakkını Geri Ver';
  const String keepOption = 'Geri Verme';
  const String deleteButton = 'Randevuyu Sil';

  AppointmentModel appointment({PostponeSource? postponedBy, String? sub}) =>
      AppointmentModel(
        appointmentId: 'a1',
        userId: 'u1',
        subscriptionId: sub,
        meetingType: MeetingType.online,
        appointmentType: AppointmentType.haftalik,
        appointmentDateTime: DateTime(2030, 1, 10, 10),
        status: AppointmentStatus.postponed,
        createDate: DateTime(2030, 1, 1),
        postponedBy: postponedBy,
        durationMinutes: 30,
      );

  /// Silme sorusunu açar; sonucu [onResult]'a verir.
  Future<void> ask(
    WidgetTester tester,
    AppointmentModel appt,
    void Function(bool?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
                await PostponementNotices.askReturnRightOnDelete(
                    context, appt)),
            child: const Text('sil'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('sil'));
    await tester.pumpAndSettle();
  }

  FilledButton deleteButtonWidget(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, deleteButton));

  final AppointmentModel consumed =
      appointment(postponedBy: PostponeSource.user, sub: 's1');

  testWidgets('danışan kaynaklı ertelenmiş randevuda iki kutucuk çıkar; seçim yapılmadan silinmez',
      (tester) async {
    bool? result = true;
    bool answered = false;
    await ask(tester, consumed, (value) {
      result = value;
      answered = true;
    });

    expect(find.text(returnOption), findsOneWidget);
    expect(find.text(keepOption), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(deleteButtonWidget(tester).onPressed, isNull);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(returnOption), findsOneWidget,
        reason: 'dışarı dokununca kapanmaz');

    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(result, isNull, reason: 'vazgeçilince randevu silinmez');
  });

  testWidgets('"Geri Ver" seçilince true döner', (tester) async {
    bool? result;
    await ask(tester, consumed, (value) => result = value);

    await tester.tap(find.text(returnOption));
    await tester.pump();
    expect(deleteButtonWidget(tester).onPressed, isNotNull);
    await tester.tap(find.text(deleteButton));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('kutucuklar tek seçimli: sonradan "Geri Verme" seçilince false döner',
      (tester) async {
    bool? result;
    await ask(tester, consumed, (value) => result = value);

    await tester.tap(find.text(returnOption));
    await tester.pump();
    await tester.tap(find.text(keepOption));
    await tester.pump();
    final List<CheckboxListTile> tiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(tiles.map((tile) => tile.value), [false, true]);

    await tester.tap(find.text(deleteButton));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('hak kullanmamış randevuda soru sorulmaz, false döner',
      (tester) async {
    for (final AppointmentModel appt in [
      appointment(postponedBy: PostponeSource.admin, sub: 's1'),
      appointment(postponedBy: PostponeSource.user),
      appointment(sub: 's1'),
    ]) {
      bool? result;
      await ask(tester, appt, (value) => result = value);
      expect(find.text(returnOption), findsNothing);
      expect(result, isFalse);
    }
  });

  test('silme mesajının erteleme notu', () {
    expect(PostponementNotices.deleteResultNote(consumed, returned: true),
        contains('geri verildi'));
    expect(PostponementNotices.deleteResultNote(consumed, returned: false),
        contains('geri verilmedi'));
    expect(
        PostponementNotices.deleteResultNote(
            appointment(postponedBy: PostponeSource.admin, sub: 's1'),
            returned: false),
        isEmpty);
  });

  testWidgets(
      'openAttentionChoice: seçili kutucuğa yeniden dokununca seçim kalkar, '
      'onay kapanır', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => DialogUtils.openAttentionChoice<bool>(
            context,
            title: 'Başlık',
            message: 'Mesaj',
            options: const [(true, 'Evet'), (false, 'Hayır')],
            confirmText: 'Sil',
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    FilledButton confirm() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sil'));

    await tester.tap(find.text('Evet'));
    await tester.pump();
    expect(confirm().onPressed, isNotNull);

    await tester.tap(find.text('Evet'));
    await tester.pump();
    expect(confirm().onPressed, isNull);
  });
}
