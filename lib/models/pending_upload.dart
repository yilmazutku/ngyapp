import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/image_thumbnail.dart';
import '../utils/storage_upload.dart';
import '../widgets/meal_thumbnail_image.dart';
import 'meal_model.dart';

/// Sohbette yüklenmeyi bekleyen bir fotoğrafın durumu.
enum PendingUploadStatus {
  /// Sırada; önündeki fotoğraflar bitince yüklenir.
  waiting,

  /// Yükleniyor (ilerleme [PendingUpload.progress]).
  uploading,

  /// Dosyalar yüklendi; öğün kaydı ve sohbet mesajı birlikte yazılıyor. Artık
  /// iptal edilemez.
  committing,

  /// Dosyalar yüklendi, mesaj yazıldı: sohbette gerçek mesaj görünür, bekleyen
  /// baloncuk kalkar.
  saving,

  /// Yüklenemedi (sebep [PendingUpload.errorText]).
  failed,
}

/// Kullanıcıya gösterilecek bir yükleme hatası; [canRetry] false ise "Tekrar
/// dene" sunulmaz (ör. öğünün fotoğraf sınırı dolmuş).
class UploadFailure implements Exception {
  final String message;
  final bool canRetry;

  /// Kayıt işleminin sonucu belli değil: fotoğraf gönderilmiş olabilir (bkz.
  /// [PendingUpload.commitUnconfirmed]).
  final bool unconfirmed;

  const UploadFailure(
    this.message, {
    this.canRetry = true,
    this.unconfirmed = false,
  });

  @override
  String toString() => 'UploadFailure($message)';
}

/// Sohbette yüklenmeyi bekleyen öğün fotoğrafı. Sohbet ekranı kilitlenmeden,
/// listenin altında ilerlemesiyle görünür; iptal edilebilir, bağlantı kesilip
/// yükleme ilerlemezse [stallTimeout] sonunda durdurulur ve "Tekrar dene"
/// sunulur.
///
/// Sıra `ChatManager` içinde tutulur: sohbetten çıkılsa da yükleme sürer,
/// sohbete dönülünce kaldığı yerden görünür. [runner] asıl yüklemeyi yapar
/// (öğün kaydı + sohbet mesajı) ve ilerlemeyi bu nesne üzerinden
/// ([UploadObserver]) bildirir.
class PendingUpload implements UploadObserver {
  PendingUpload({
    required this.chatId,
    required this.image,
    required this.meal,
    required this.runner,
    DateTime? createdAt,
    String? persistKey,
    this.autoRetries = 0,
    double? previewAspectRatio,
  })  : id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
        createdAt = createdAt ?? DateTime.now(),
        previewAspectRatio = ValueNotifier<double?>(previewAspectRatio) {
    this.persistKey = persistKey ?? id;
  }

  static int _sequence = 0;

  /// Yükleme bu süre boyunca hiç ilerlemezse (bağlantı yok ya da çok yavaş)
  /// durdurulur.
  static const Duration stallTimeout = Duration(seconds: 30);

  /// Dosyalar yüklendikten sonra kayıt işlemi en fazla bu kadar beklenir.
  /// Arka planda geçen süre sayılmaz (bkz. [suspendWatchdog]).
  static const Duration commitTimeout = Duration(seconds: 60);

  static const String timeoutText =
      'Bağlantı yok ya da çok yavaş; fotoğraf gönderilemedi.';

  /// Yüklenemeyen fotoğraf, bağlantı geri gelince en fazla bu kadar kez
  /// kendiliğinden yeniden denenir (bkz. `ChatManager`); sonra "Tekrar dene"
  /// beklenir.
  static const int maxAutoRetries = 5;
  static const String defaultErrorText =
      'Fotoğraf gönderilemedi. Lütfen tekrar deneyin.';

  /// Kayıt işleminin sonucu zamanında gelmedi: fotoğraf gönderilmiş de
  /// olabilir. Yeniden deneme aynı fotoğrafı ikinci kez göndermez.
  static const String unconfirmedText =
      'Fotoğrafın gönderildiği doğrulanamadı.';

  final String id;
  final String chatId;
  final XFile image;

  /// Fotoğrafın eklendiği öğün.
  final Meals meal;

  /// Fotoğrafın gönderildiği an. Yükleme gecikse de (sırada bekledi, bağlantı
  /// yoktu, uygulama kapanıp açıldı) fotoğraf bu anın gününe ve saatine
  /// kaydedilir.
  final DateTime createdAt;

  /// Cihazda saklanan sıra kaydının anahtarı; yeniden denemelerde aynı kalır
  /// (bkz. `ChatManager.restorePendingUploads`).
  late final String persistKey;

  /// Kendiliğinden yapılmış yeniden deneme sayısı ([maxAutoRetries]).
  final int autoRetries;

  final Future<void> Function(PendingUpload upload) runner;

  final ValueNotifier<PendingUploadStatus> status =
      ValueNotifier<PendingUploadStatus>(PendingUploadStatus.waiting);

  /// Asıl dosyanın yüklenme oranı (0-1); hazırlanırken null.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  /// Fotoğrafın en/boy oranı; dosyanın başlığından okunur (bkz.
  /// [loadPreviewAspectRatio]), okunana kadar null. Bekleyen baloncuk
  /// fotoğrafı gerçek oranında gösterir; mesaj gelince boyut değişmez.
  final ValueNotifier<double?> previewAspectRatio;

  String? errorText;
  bool canRetry = true;

  bool _cancelledByUser = false;
  bool _timedOut = false;

  /// Dosyalar yüklendi, kayıt işlemi sürüyor: sayaç [commitTimeout] sayar.
  bool _committing = false;

  /// Kayıt işleminin süresi doldu: sonucu belli değil (bkz.
  /// [commitUnconfirmed]).
  bool _commitTimedOut = false;

  /// Kayıtlar yazıldı (bkz. [onWritten]).
  bool _written = false;

  /// Kayıt işlemi hata verdi, sonucu belli değil (bkz. [markFailed]).
  bool _unconfirmedFailure = false;
  final List<UploadTask> _tasks = [];
  final List<StreamSubscription<TaskSnapshot>> _subscriptions = [];
  Timer? _watchdog;

  /// Uygulama arka plandayken süre sayılmaz: iOS uygulamayı askıya alır,
  /// dönüşte geçmiş süre "bağlantı yok" sanılmasın.
  bool _watchdogSuspended = false;
  final Completer<void> _aborted = Completer<void>();

  /// Sırada, yükleniyor ya da yazılıyor: öğün kaydına henüz yazılmadı ama
  /// yazılacak. Yazıldıysa ([onWritten]) öğünün kaydında zaten sayılır.
  bool get isQueued =>
      !_written &&
      (status.value == PendingUploadStatus.waiting ||
          status.value == PendingUploadStatus.uploading ||
          status.value == PendingUploadStatus.committing);

  /// Kayıt işleminin süresi doldu, sonucu belli değil: fotoğraf gönderilmiş
  /// olabilir. Baloncuk "Kaldır" sunmaz; yeniden deneme güvenlidir (aynı
  /// mesaj kimliği, bkz. `MealManager.uploadMealImg`).
  bool get commitUnconfirmed => _commitTimedOut || _unconfirmedFailure;

  /// Yüklenemedi ama bağlantı gelince kendiliğinden yeniden denenecek.
  bool get willAutoRetry =>
      status.value == PendingUploadStatus.failed &&
      canRetry &&
      autoRetries < maxAutoRetries;

  bool get cancelledByUser => _cancelledByUser;
  bool get timedOut => _timedOut;

  /// Kullanıcı iptal edince ya da zaman aşımında tamamlanır; sıra, yarıda
  /// kalan yüklemeyi beklemeden ilerler.
  Future<void> get aborted => _aborted.future;

  @override
  bool get isCancelled => _cancelledByUser || _timedOut;

  @override
  void onTask(UploadTask task) {
    _tasks.add(task);
    if (isCancelled) {
      task.cancel();
      return;
    }

    final bool isMainFile = _tasks.length == 1;
    _armWatchdog();
    _subscriptions.add(task.snapshotEvents.listen(
      (TaskSnapshot snapshot) {
        _armWatchdog();
        if (isMainFile && snapshot.totalBytes > 0) {
          progress.value = snapshot.bytesTransferred / snapshot.totalBytes;
        }
      },
      onError: (Object e) {},
    ));
  }

  /// Fotoğrafın oranını dosyanın başlığından okur (bir kez).
  Future<void> loadPreviewAspectRatio() async {
    if (previewAspectRatio.value != null) return;
    final ImagePixelSize? size = await readImageFilePixelSize(image);
    if (size != null) previewAspectRatio.value = size.width / size.height;
  }

  /// Küçük görsel cihazda üretildi: mesaj yazılınca sohbet onu indirmeden
  /// gösterir.
  @override
  void onUploaded(UploadedImage image) {
    // Dosyalar yüklendi: sayaç bundan sonra kayıt işlemini [commitTimeout]
    // ile izler. İptal artık yok: işlem yazılmış olabilir, geri alınamaz.
    _stopTracking();
    _committing = true;
    status.value = PendingUploadStatus.committing;
    _armWatchdog();
    final String? thumbUrl = image.thumbUrl;
    final Uint8List? thumbBytes = image.thumbBytes;
    if (thumbUrl != null && thumbBytes != null) {
      MealThumbnailProvider.seed(thumbUrl, thumbBytes);
    }
  }

  @override
  void onWritten() {
    _committing = false;
    _written = true;
    _stopTracking();
  }

  @override
  void onSaving() {
    _committing = false;
    _stopTracking();
    status.value = PendingUploadStatus.saving;
  }

  void markUploading() {
    progress.value = null;
    status.value = PendingUploadStatus.uploading;
  }

  void markFailed(
    String message, {
    bool canRetry = true,
    bool unconfirmed = false,
  }) {
    _committing = false;
    _unconfirmedFailure = unconfirmed;
    _stopTracking();
    errorText = message;
    this.canRetry = canRetry;
    status.value = PendingUploadStatus.failed;
  }

  /// Başarısız yüklemenin yeniden denenecek kopyası. Yeni nesnedir: zaman
  /// aşımına uğrayıp arka planda hâlâ süren eski deneme, iptal edilmiş
  /// saydığı bu nesneyle kayıt yazamaz (aynı fotoğraf iki kez gönderilmez).
  /// [automatic] ise kendiliğinden deneme sayısı artar; kullanıcı "Tekrar
  /// dene"ye basınca sayı sıfırlanır.
  PendingUpload retryCopy({bool automatic = false}) => PendingUpload(
        chatId: chatId,
        image: image,
        meal: meal,
        runner: runner,
        createdAt: createdAt,
        persistKey: persistKey,
        autoRetries: automatic ? autoRetries + 1 : 0,
        previewAspectRatio: previewAspectRatio.value,
      );

  /// Kullanıcı yüklemeyi iptal etti: süren Storage görevi durdurulur, yüklenmiş
  /// dosyalar yükleme adımı tarafından silinir, mesaj yazılmaz.
  void cancel() {
    _cancelledByUser = true;
    _abort();
  }

  /// Uygulama arka plana geçti: zaman aşımı sayacı durur.
  void suspendWatchdog() {
    _watchdogSuspended = true;
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Uygulama öne geldi: yükleme sürüyorsa sayaç baştan başlar.
  void resumeWatchdog() {
    if (!_watchdogSuspended) return;
    _watchdogSuspended = false;
    if (_subscriptions.isNotEmpty || _committing) _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    if (_watchdogSuspended) return;
    _watchdog = Timer(_committing ? commitTimeout : stallTimeout, () {
      _timedOut = true;
      _commitTimedOut = _committing;
      _abort();
    });
  }

  void _abort() {
    _stopTracking();
    for (final UploadTask task in _tasks) {
      final TaskState state = task.snapshot.state;
      if (state == TaskState.running || state == TaskState.paused) {
        task.cancel();
      }
    }
    if (!_aborted.isCompleted) _aborted.complete();
  }

  void _stopTracking() {
    _watchdog?.cancel();
    _watchdog = null;
    for (final StreamSubscription<TaskSnapshot> subscription
        in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
