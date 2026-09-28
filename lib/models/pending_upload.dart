import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/storage_upload.dart';
import 'meal_model.dart';

/// Sohbette yüklenmeyi bekleyen bir fotoğrafın durumu.
enum PendingUploadStatus {
  /// Sırada; önündeki fotoğraflar bitince yüklenir.
  waiting,

  /// Yükleniyor (ilerleme [PendingUpload.progress]).
  uploading,

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

  const UploadFailure(this.message, {this.canRetry = true});

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
  }) : id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  static int _sequence = 0;

  /// Yükleme bu süre boyunca hiç ilerlemezse (bağlantı yok ya da çok yavaş)
  /// durdurulur.
  static const Duration stallTimeout = Duration(seconds: 30);

  static const String timeoutText =
      'Bağlantı yok ya da çok yavaş; fotoğraf gönderilemedi.';
  static const String defaultErrorText =
      'Fotoğraf gönderilemedi. Lütfen tekrar deneyin.';

  final String id;
  final String chatId;
  final XFile image;

  /// Fotoğrafın eklendiği öğün.
  final Meals meal;

  final Future<void> Function(PendingUpload upload) runner;

  final ValueNotifier<PendingUploadStatus> status =
      ValueNotifier<PendingUploadStatus>(PendingUploadStatus.waiting);

  /// Asıl dosyanın yüklenme oranı (0-1); hazırlanırken null.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  String? errorText;
  bool canRetry = true;

  bool _cancelledByUser = false;
  bool _timedOut = false;
  final List<UploadTask> _tasks = [];
  final List<StreamSubscription<TaskSnapshot>> _subscriptions = [];
  Timer? _watchdog;

  /// Uygulama arka plandayken süre sayılmaz: iOS uygulamayı askıya alır,
  /// dönüşte geçmiş süre "bağlantı yok" sanılmasın.
  bool _watchdogSuspended = false;
  final Completer<void> _aborted = Completer<void>();

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

  @override
  void onSaving() {
    _stopTracking();
    status.value = PendingUploadStatus.saving;
  }

  void markUploading() {
    progress.value = null;
    status.value = PendingUploadStatus.uploading;
  }

  void markFailed(String message, {bool canRetry = true}) {
    _stopTracking();
    errorText = message;
    this.canRetry = canRetry;
    status.value = PendingUploadStatus.failed;
  }

  /// Başarısız yüklemenin yeniden denenecek kopyası. Yeni nesnedir: zaman
  /// aşımına uğrayıp arka planda hâlâ süren eski deneme, iptal edilmiş
  /// saydığı bu nesneyle kayıt yazamaz (aynı fotoğraf iki kez gönderilmez).
  PendingUpload retryCopy() => PendingUpload(
        chatId: chatId,
        image: image,
        meal: meal,
        runner: runner,
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
    if (_subscriptions.isNotEmpty) _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    if (_watchdogSuspended) return;
    _watchdog = Timer(stallTimeout, () {
      _timedOut = true;
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
