import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// Fotoğraf baytlarını indirir; aynı anda açık indirme sayısını sınırlar.
///
/// `Image.network` her görsel için anında bir istek açar: ekranda 30 kart
/// varsa 30 paralel indirme başlar, bağlantı ve işlemci boğulur, liste kasar.
/// Burada indirmeler bir kuyruktan [maxConcurrent] adet olarak çekilir; ilk
/// görseller hızla gelir, gerisi sırayla dolar.
class MealPhotoLoader {
  MealPhotoLoader._();

  static final MealPhotoLoader instance = MealPhotoLoader._();

  http.Client _client = http.Client();

  /// Testlerde ağ yerine sahte istemci takmak için.
  @visibleForTesting
  set client(http.Client client) => _client = client;

  /// Aynı anda sürdürülen indirme sayısı. Küçük görseller için 6 yeterli;
  /// daha fazlası bant genişliğini bölüştürüp hepsini geciktirir.
  static const int maxConcurrent = 6;

  /// Tek bir indirme için üst sınır. Küçük görseller saniyeler içinde iner;
  /// süre, küçük görseli henüz olmayan tam boy fotoğrafın yavaş bağlantıda
  /// da tamamlanabilmesi için geniş tutuldu.
  static const Duration _timeout = Duration(seconds: 90);

  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  /// Şu an süren indirme sayısı (test/izleme).
  int get activeCount => _active;

  /// [url] adresindeki dosyayı indirir. Sıra doluysa bekler.
  Future<Uint8List> fetch(String url) async {
    await _acquire();
    try {
      final http.Response response =
          await _client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw PhotoDownloadException(url, response.statusCode);
      }
      return response.bodyBytes;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final Completer<void> completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // Sıradaki bekleyen, boşalan yeri devralır; sayaç değişmez.
      _waiting.removeFirst().complete();
      return;
    }
    _active--;
    if (_active < 0) {
      _active = 0;
    }
  }
}

/// Başarısız HTTP yanıtı. (`dart:io`daki HttpException ile karışmasın diye
/// ayrı adlandırıldı.)
class PhotoDownloadException implements Exception {
  final String url;
  final int statusCode;

  const PhotoDownloadException(this.url, this.statusCode);

  @override
  String toString() => 'HTTP $statusCode: $url';
}
