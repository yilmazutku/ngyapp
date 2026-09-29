import 'package:flutter_test/flutter_test.dart';

import 'package:ngy_app/utils/diet_menu_parser.dart';

void main() {
  void expectHeader(String line, String? time, String inlineContent) {
    final MealHeaderLine header = parseMealHeaderLine(line);
    expect(header.time, time, reason: line);
    expect(header.inlineContent, inlineContent, reason: line);
  }

  test('saat parantez içinde nokta ile yazılınca okunur', () {
    expectHeader('ÖĞLE (12.30) :', '12:30', '');
    expectHeader('AKŞAM (19.30) :', '19:30', '');
    expectHeader('ÖĞLE (12.30) :\t\t', '12:30', '');
  });

  test('saat parantez içinde iki nokta ile yazılınca okunur', () {
    expectHeader('ÖĞLE (12:30) :', '12:30', '');
    expectHeader('AKŞAM (19:30) :', '19:30', '');
    expectHeader('ÖĞLE (12:30)', '12:30', '');
  });

  test('ayraç saatin içindeki ":" değil, parantezden sonraki ":"', () {
    expectHeader(
      'ARA (15.30) :200 ml sade kefir veya 4 yk yoğurt (150g) ',
      '15:30',
      '200 ml sade kefir veya 4 yk yoğurt (150g)',
    );
    expectHeader(
      'ARA (15:30) :200 ml sade kefir veya 4 yk yoğurt (150g) ',
      '15:30',
      '200 ml sade kefir veya 4 yk yoğurt (150g)',
    );
    expectHeader(
        'ARA (21.00) :1 fincan yeşil çay', '21:00', '1 fincan yeşil çay');
    expectHeader(
        'ARA (21:00):1 fincan yeşil çay', '21:00', '1 fincan yeşil çay');
    expectHeader(
      'ARA (21:00) :\t\t1 fincan yeşil çay',
      '21:00',
      '1 fincan yeşil çay',
    );
    expectHeader(
        'ARA (10:00) : 1 elma, 16:30 kefir', '10:00', '1 elma, 16:30 kefir');
  });

  test('tek haneli saat ve parantez içi boşluklar kabul edilir', () {
    expectHeader('SABAH (9.05) :', '09:05', '');
    expectHeader('SABAH ( 9 : 05 ) :', '09:05', '');
    expectHeader('ARA ÖĞÜN 1 (10:30) :', '10:30', '');
  });

  test('ayraçtan sonra gelen parantezli saat başlığın saati sayılmaz', () {
    expectHeader('ARA : 1 elma (15:30)', null, '1 elma (15:30)');
    expectHeader('ARA : 1 elma (15.30)', null, '1 elma (15.30)');
  });

  test('parantezsiz ya da geçersiz saat okunmaz, tahmin edilmez', () {
    expectHeader('ÖĞLE :', null, '');
    expectHeader('ÖĞLE', null, '');
    expectHeader('ARA 200gr üzüm', null, '');
    expectHeader('ARA 1.50 litre su', null, '');
    expectHeader('ARA (1.50 litre su) :', null, '');
    expectHeader('SABAH (25:70) :', null, '');
    expectHeader('SABAH (24.00) :', null, '');
    expectHeader('ARA (150g) : yoğurt', null, 'yoğurt');
  });
}
