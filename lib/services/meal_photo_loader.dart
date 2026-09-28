import 'dart:async';
import 'dart:collection';
import 'dart:io' show Directory, File, FileStat, FileSystemEntity;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Fotoğraf baytlarını indirir; aynı anda açık indirme sayısını sınırlar.
///
/// `Image.network` her görsel için anında bir istek açar: ekranda 30 kart
/// varsa 30 paralel indirme başlar, bağlantı ve işlemci boğulur, liste kasar.
/// Burada indirmeler bir kuyruktan [maxConcurrent] adet olarak çekilir; ilk
/// görseller hızla gelir, gerisi sırayla dolar.
///
/// İndirilen dosyalar cihazdaki önbellek klasöründe de saklanır: sohbet,
/// Öğün Fotoğrafları ya da admin listesi yeniden açılınca aynı küçük görseller
/// tekrar indirilmez. Klasör [diskCacheMaxBytes]'ı aşınca en uzun süredir
/// kullanılmayan dosyalar silinir. Web'de disk önbelleği yoktur.
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

  /// Disk önbelleğinin üst sınırı. Küçük görseller ~50 KB: binlercesi sığar.
  static const int diskCacheMaxBytes = 150 * 1024 * 1024;

  /// Sınır aşılınca önbellek bu orana kadar boşaltılır; her yeni dosyada
  /// yeniden temizlik gerekmesin.
  static const double _pruneTargetRatio = 0.8;

  /// Bu kadar yeni dosya yazılınca önbelleğin boyutuna yeniden bakılır.
  static const int _writesPerPrune = 50;

  /// Bellekte tutulan, cihazda üretilmiş küçük görsellerin sayısı (bkz.
  /// [remember]).
  static const int _rememberedLimit = 24;

  static const String _cacheFolderName = 'meal_photo_cache';

  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  /// Cihazda üretilip yüklenen küçük görseller (adres -> bayt), en yeni sonda.
  final LinkedHashMap<String, Uint8List> _remembered =
      LinkedHashMap<String, Uint8List>();

  Future<Directory?>? _cacheDirectory;
  int _writesSincePrune = 0;
  bool _pruning = false;

  /// Şu an süren indirme sayısı (test/izleme).
  int get activeCount => _active;

  /// Testlerde disk önbelleği klasörünü vermek (ya da null ile kapatmak)
  /// için.
  @visibleForTesting
  set cacheDirectory(Directory? directory) =>
      _cacheDirectory = Future<Directory?>.value(directory);

  /// [url] adresindeki dosyayı verir: önce bellekte ve diskte arar, yoksa
  /// indirir (sıra doluysa bekler) ve diske yazar.
  Future<Uint8List> fetch(String url) async {
    final Uint8List? remembered = _remembered[url];
    if (remembered != null) return remembered;

    final File? cached = await _cacheFileFor(url);
    if (cached != null) {
      final Uint8List? bytes = await _readCached(cached);
      if (bytes != null) return bytes;
    }

    await _acquire();
    final Uint8List bytes;
    try {
      final http.Response response =
          await _client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw PhotoDownloadException(url, response.statusCode);
      }
      bytes = response.bodyBytes;
    } finally {
      _release();
    }
    if (cached != null) unawaited(_writeCached(cached, bytes));
    return bytes;
  }

  /// Cihazda üretilip [url] adresine yüklenen dosyanın baytları: indirilmeden
  /// hemen gösterilir (ör. az önce gönderilen fotoğrafın küçük görseli
  /// sohbette yeniden inmez) ve diske de yazılır.
  void remember(String url, Uint8List bytes) {
    _remembered.remove(url);
    _remembered[url] = bytes;
    while (_remembered.length > _rememberedLimit) {
      _remembered.remove(_remembered.keys.first);
    }
    unawaited(_cacheFileFor(url).then((File? file) {
      if (file != null) return _writeCached(file, bytes);
    }));
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

  // ===== Disk önbelleği =====

  /// Önbellek klasörü; kullanılamıyorsa (web, izin, test) null ve önbellek
  /// devre dışı kalır.
  Future<Directory?> _directory() => _cacheDirectory ??= _openDirectory();

  Future<Directory?> _openDirectory() async {
    if (kIsWeb) return null;
    try {
      final Directory base = await getApplicationCacheDirectory();
      final Directory directory =
          Directory('${base.path}/$_cacheFolderName');
      await directory.create(recursive: true);
      unawaited(_prune(directory));
      return directory;
    } catch (e) {
      return null;
    }
  }

  Future<File?> _cacheFileFor(String url) async {
    final Directory? directory = await _directory();
    if (directory == null) return null;
    return File('${directory.path}/${cacheKeyFor(url)}');
  }

  /// Adresin dosya adı: FNV-1a (64 bit) özeti. Adres değişmedikçe aynıdır;
  /// Storage adresleri dosya başına sabit olduğundan eski dosya yanlışlıkla
  /// gösterilmez.
  @visibleForTesting
  static String cacheKeyFor(String url) {
    int hash = 0xcbf29ce484222325;
    for (final int unit in url.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    final String high = ((hash >> 32) & 0xFFFFFFFF).toRadixString(16);
    final String low = (hash & 0xFFFFFFFF).toRadixString(16);
    return '${high.padLeft(8, '0')}${low.padLeft(8, '0')}';
  }

  Future<Uint8List?> _readCached(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      // Son kullanım zamanı: temizlikte en uzun süredir kullanılmayan silinir.
      unawaited(
        file.setLastModified(DateTime.now()).catchError((Object e) {}),
      );
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Önce geçici dosyaya yazılıp taşınır: yarım yazılmış dosya okunmaz.
  Future<void> _writeCached(File file, Uint8List bytes) async {
    try {
      final File temp = File('${file.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } catch (e) {
      return;
    }
    if (++_writesSincePrune >= _writesPerPrune) {
      _writesSincePrune = 0;
      final Directory? directory = await _directory();
      if (directory != null) unawaited(_prune(directory));
    }
  }

  /// Önbellek [diskCacheMaxBytes]'ı aştıysa en uzun süredir kullanılmayan
  /// dosyaları siler.
  Future<void> _prune(Directory directory) async {
    if (_pruning) return;
    _pruning = true;
    try {
      final List<({File file, int size, DateTime used})> entries = [];
      int total = 0;
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is! File) continue;
        try {
          final FileStat stat = await entity.stat();
          entries.add((file: entity, size: stat.size, used: stat.modified));
          total += stat.size;
        } catch (e) {
          continue;
        }
      }
      if (total <= diskCacheMaxBytes) return;

      entries.sort((a, b) => a.used.compareTo(b.used));
      final int target = (diskCacheMaxBytes * _pruneTargetRatio).round();
      for (final ({File file, int size, DateTime used}) entry in entries) {
        if (total <= target) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      return;
    } finally {
      _pruning = false;
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
