import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sohbete seçilen ya da düzenlenen fotoğrafların cihazda kalan geçici
/// kopyaları.
///
/// Android'de fotoğraf seçici kamerayla çekileni önbellek klasörüne yazar,
/// galeriden seçileni oraya (`cache/<uuid>/`) kopyalar; iOS'ta `tmp`
/// klasörüne yazar. Düzenleme ekranı da kırptığı fotoğrafı
/// [photoEditDirectory]'ye yazar. Bunları kimse silmez, önbellek durmadan
/// büyür: fotoğraf yüklenince ya da ondan vazgeçilince [delete] ile silinir.
///
/// Yalnızca Android ve iOS'ta, yalnızca uygulamanın geçici klasörlerindeki
/// dosyalar silinir: masaüstünde ve web'de seçici kullanıcının kendi
/// dosyasını verir. Hata fırlatılmaz; silinemeyen dosya kalır.
class TempPhotoFiles {
  TempPhotoFiles._();

  static const String _photoEditFolderName = 'photo_edit';

  /// Düzenleme klasöründe bu süreden eski, sırada olmayan dosyalar silinir
  /// (bkz. [deleteStalePhotoEdits]).
  static const Duration _staleAge = Duration(days: 2);

  static bool get _enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Düzenlenen fotoğrafların yazıldığı klasör; yoksa oluşturulur.
  static Future<Directory> photoEditDirectory() async {
    final Directory directory = _photoEditDirectoryIn(
      await getTemporaryDirectory(),
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Directory _photoEditDirectoryIn(Directory temporary) =>
      Directory(p.join(temporary.path, _photoEditFolderName));

  /// [path]'teki fotoğrafı, uygulamanın geçici klasörlerinden birindeyse
  /// siler. Bulunduğu klasör boşaldıysa ve kendisi bu klasörlerin içindeyse
  /// (Android'de galeriden seçilenin `cache/<uuid>/` klasörü) o da silinir;
  /// geçici klasörlerin kendisi ve düzenleme klasörü kalır (düzenleme ekranı
  /// o sırada içine yazıyor olabilir).
  static Future<void> delete(String path) async {
    if (!_enabled || path.isEmpty) return;
    try {
      final File file = File(path);
      if (!await file.exists()) return;
      final String target = await _canonical(file);
      final List<String> roots = await _roots();
      if (!roots.any((root) => p.isWithin(root, target))) return;
      await File(target).delete();

      final String parent = p.dirname(target);
      final String photoEdit = await _canonical(
        _photoEditDirectoryIn(await getTemporaryDirectory()),
      );
      final bool removable = parent != photoEdit &&
          !roots.contains(parent) &&
          roots.any((root) => p.isWithin(root, parent));
      // Boş değilse silinmez (hata yok sayılır).
      if (removable) await Directory(parent).delete();
    } catch (e) {
      return;
    }
  }

  /// Düzenleme klasöründe [_staleAge]'den eski ve [keep] içinde olmayan
  /// dosyaları siler: yüklenip silinemeden kalanlar (ör. uygulama o sırada
  /// kapandı). [keep] sırada bekleyen fotoğrafların yollarıdır.
  static Future<void> deleteStalePhotoEdits({
    required Iterable<String> keep,
  }) async {
    if (!_enabled) return;
    try {
      final Directory directory =
          _photoEditDirectoryIn(await getTemporaryDirectory());
      if (!await directory.exists()) return;
      final Set<String> kept = {
        for (final String path in keep) await _canonical(File(path)),
      };
      final DateTime cutoff = DateTime.now().subtract(_staleAge);
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is! File) continue;
        try {
          if (kept.contains(await _canonical(entity)) ||
              (await entity.lastModified()).isAfter(cutoff)) {
            continue;
          }
          await entity.delete();
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      return;
    }
  }

  /// Uygulamanın geçici klasörleri. iOS'ta [getTemporaryDirectory]
  /// `Library/Caches`'i verir, seçici ise `tmp`'ye ([Directory.systemTemp])
  /// yazar.
  static Future<List<String>> _roots() async {
    final List<String> roots = [];
    for (final Future<Directory> Function() find in [
      getTemporaryDirectory,
      getApplicationCacheDirectory,
      () async => Directory.systemTemp,
    ]) {
      try {
        roots.add(await _canonical(await find()));
      } catch (e) {
        continue;
      }
    }
    return roots;
  }

  /// Sembolik bağları çözülmüş (iOS'ta `/var` -> `/private/var`),
  /// normalleştirilmiş mutlak yol; çözülemezse yalnızca normalleştirilmiş
  /// hâli.
  static Future<String> _canonical(FileSystemEntity entity) async {
    String path = entity.path;
    try {
      path = await entity.resolveSymbolicLinks();
    } catch (e) {
      path = entity.path;
    }
    return p.normalize(p.absolute(path));
  }
}
