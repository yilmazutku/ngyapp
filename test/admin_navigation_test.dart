import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/payment_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/pages/payment_type_payments_page.dart';
import 'package:ngy_app/providers/payment_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/widgets/app_bar_with_back.dart';
import 'package:ngy_app/widgets/home_button.dart';
import 'package:provider/provider.dart';

Widget _page(String name, {Widget? next}) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBarWithBack(title: name, showHomeButton: true),
        body: next == null
            ? Text('$name body')
            : ElevatedButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => next)),
                child: Text('open from $name'),
              ),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('Ana Sayfa returns to the first route, Geri returns one step',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _page('Home', next: _page('A', next: _page('B'))),
    ));
    await tester.tap(find.text('open from Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open from A'));
    await tester.pumpAndSettle();
    expect(find.text('B body'), findsOneWidget);

    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    expect(find.text('open from A'), findsOneWidget);

    await tester.tap(find.text('open from A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(HomeButton.label));
    await tester.pumpAndSettle();
    expect(find.text('open from Home'), findsOneWidget);
    expect(find.text('B body'), findsNothing);
  });

  testWidgets('payment type breakdown lists name, amount and date',
      (tester) async {
    final user = UserModel(
      userId: 'u1',
      name: 'Ayşe',
      surname: 'Yılmaz',
      email: 'a@b.c',
      password: '',
      role: 'customer',
    );
    final payment = PaymentModel(
      paymentId: 'p1',
      userId: 'u1',
      amount: 5000,
      paymentDate: DateTime(2026, 9, 12),
      status: PaymentStatus.completed,
      paymentType: PaymentType.nakit,
    );
    await tester.pumpWidget(ChangeNotifierProvider<PaymentProvider>(
      create: (_) => PaymentProvider(subProvider: SubProvider()),
      child: MaterialApp(
        home: PaymentTypePaymentsPage(
          title: 'Nakit Ödemeleri',
          periodText: 'Eylül 2026',
          icon: Icons.payments,
          payments: [payment],
          userOf: (id) => id == 'u1' ? user : null,
          reloadPayments: () async => [payment],
        ),
      ),
    ));
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('5.000 ₺'), findsOneWidget);
    expect(find.text('12.09.2026'), findsOneWidget);
    expect(find.text(HomeButton.label), findsOneWidget);
  });
}
