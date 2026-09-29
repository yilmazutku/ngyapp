// lib/pages/chat_page_new.dart
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/diet_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/models/diet_model.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/widgets/chat/chat_date_separator.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';
import 'package:ngy_app/widgets/chat/message_reply_quote.dart';
import 'package:ngy_app/widgets/chat/pending_upload_bubble.dart';
import 'package:ngy_app/widgets/full_screen_image_page.dart';
import 'package:ngy_app/widgets/home_button.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:ngy_app/widgets/meal_thumbnail_image.dart';
import 'package:ngy_app/widgets/reaction_badge.dart';
import 'package:ngy_app/widgets/reaction_picker.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/pages/user_media_gallery_page.dart';
import 'package:ngy_app/utils/date_formatter.dart';
import 'package:ngy_app/utils/dialog_utils.dart';
import 'package:ngy_app/utils/diet_menu_parser.dart';
import 'package:ngy_app/services/fcm_service.dart';
import 'package:ngy_app/services/meal_reminder_service.dart';

import '../constants/app_constants.dart';

/// Masaüstü platformu mu (Windows, macOS, Linux). Enter ile gönderme, sağ tık
/// menüsü ve seçilebilir metin yalnızca burada açılır; dokunmatikte uzun basma
/// davranışları olduğu gibi kalır.
bool get _isDesktopPlatform => const {
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

/// ChatPage displays the chat interface for both regular users and admins.
/// 
/// Features:
/// - Send text messages
/// - Send images from gallery or camera
/// - Upload meal photos
/// - React to the other party's messages (WhatsApp-style, one per person)
/// - View message history with timestamps
/// - Real-time updates via Firestore streams
///
/// Admin behavior:
/// - Admins can view any user's chat by passing overrideChatId
/// - All features are available
///
/// User behavior:
/// - Regular users always view their own chat (overrideChatId is null)
/// - All features including meal upload and reactions are available
class ChatPage extends StatefulWidget {
  /// Optional chat ID override for admin users.
  /// - If null: Opens the current user's own chat
  /// - If non-null: Opens the specified user's chat (admin only)
  final String? overrideChatId;

  /// Açılışta gidilecek mesajın kimliği. Verilirse sohbet mesajı kapsayacak
  /// kadar geriden yüklenir ([ChatManager.openFocusWindow]), en yeni mesaj
  /// yerine o mesajda açılır ve mesaj kısa süre vurgulanır (bkz.
  /// [_buildMessageList]). Mesaj bulunamazsa ya da sohbetin çok gerisindeyse
  /// sohbet en yeni mesajdan açılır ve kullanıcıya söylenir. Öğün Fotoğrafları
  /// sayfasındaki "Sohbette göster" (bkz. [ChatManager.findImageMessage]) ve
  /// danışana giden ifade bildirimi bunu kullanır.
  final String? focusMessageId;

  /// Admin başlığında gösterilecek danışan adı. Çağıran adı zaten biliyorsa
  /// (ör. Öğün Fotoğrafları) verir; başlık için ayrıca okuma yapılmaz.
  final String? userDisplayName;

  const ChatPage({
    super.key,
    this.overrideChatId,
    this.focusMessageId,
    this.userDisplayName,
  });

  /// Sohbet silme onaylarında neyin silinip neyin kaldığı (bkz.
  /// [ChatManager.deleteChat]); sohbet sayfası ve Tüm Sohbetler listesi aynı
  /// metni gösterir.
  static const String deleteChatPhotosNote =
      'Sohbete doğrudan gönderilmiş fotoğraflar da silinir; öğün fotoğrafları '
      'danışanın öğün kayıtlarında kalır ve Öğün Fotoğrafları ile "Planım"da '
      'görünmeye devam eder.';

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// Sohbet başlığındaki menünün işlemleri (yalnızca admin).
enum _ChatMenuAction { deleteChat }

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const String _uploadErrorTitle = 'Hata';
  static const String _photoLimitTitle = 'Fotoğraf Sınırı';
  static const String _chatPostFailedTitle = 'Sohbete Gönderilemedi';
  static const String _chatPostFailedText =
      'Fotoğrafınız öğün kaydınıza eklendi ancak sohbete gönderilemedi. '
      'Diyetisyeniniz fotoğrafı öğün kayıtlarınızda görebilir; tekrar '
      'yüklemenize gerek yok.';
  static const String _focusNotFoundText =
      'Mesaj sohbette bulunamadı; sohbet en yeni mesajdan açıldı.';
  static const String _focusTooOldText =
      'Bu mesaj sohbetin çok gerisinde kaldığı için gösterilemiyor; sohbet en '
      'yeni mesajdan açıldı.';
  static const String _focusErrorText =
      'Mesaja gidilemedi; sohbet en yeni mesajdan açıldı.';
  static const String _messagesLoadErrorText =
      'Mesajlar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _historyStartText = 'Sohbetin başı';
  static const String _olderLoadErrorText = 'Eski mesajlar yüklenemedi.';
  static const String _olderOfflineText =
      'Bağlantı yok; daha eski mesajlar bağlantı gelince yüklenir.';
  static const String _retryLabel = 'Tekrar dene';
  static const String _sendErrorTitle = 'Mesaj Gönderim Hatası';
  static const String _sendErrorText = 'Mesaj gönderilemedi.';
  static const String _deletePhotoTitle = 'Fotoğrafı Sil';
  static const String _deletePhotoConfirmText =
      'Bu öğün fotoğrafı silinecek. Fotoğraf öğün kayıtlarınızdan da '
      'kaldırılır ve diyetisyeniniz artık göremez; sohbette yerine '
      '"fotoğraf silindi" notu kalır.\n\nDevam etmek istiyor musunuz?';
  static const String _deletePhotoConfirmLabel = 'Sil';
  static const String _deletePhotoCancelLabel = 'Vazgeç';
  static const String _deletingPhotoText = 'Fotoğraf siliniyor...';
  static const String _photoDeletedText = 'Fotoğraf silindi.';
  static const String _deletePhotoErrorText =
      'Fotoğraf silinemedi. Lütfen tekrar deneyin.';
  static const String _copiedText = 'Mesaj kopyalandı.';
  static const Duration _copiedFeedbackDuration = Duration(seconds: 1);
  static const String _youLabel = 'Siz';
  static const String _officeLabel = 'Diyetisyen';
  static const String _clientFallbackLabel = 'Danışan';
  static const String _chatMenuTooltip = 'Diğer işlemler';
  static const String _deleteChatLabel = 'Sohbeti Sil';

  /// Kullanıcı en yeni mesajdan bu kadar yukarı kaydırınca "En yeniye git"
  /// düğmesi görünür.
  static const double _jumpButtonThreshold = 300.0;

  final ImagePicker _picker = ImagePicker();

  /// Current authenticated user's UID
  late final String _currentUid;
  
  /// The resolved chat ID (cached to avoid recalculation)
  late final String _chatId;
  
  /// Whether the current user is an admin
  late final bool _isAdminUser;

  /// Mesaj akışı. Normalde son mesajlar ([ChatManager.messagesStreamFor]);
  /// sohbet bir mesajda açıldıysa o mesajı kapsayan pencere
  /// ([ChatManager.openFocusWindow]). Pencere yüklenirken null.
  Stream<List<MessageData>>? _messagesStream;

  /// Canlı akışın altına eklenen eski mesaj sayfaları (en yeni başta); canlı
  /// dinlenmez. Odaklı açılışta ilk sayfa, hedeften eski bağlam mesajlarıdır.
  /// Liste en üste yaklaştıkça bir sayfa daha eklenir (bkz.
  /// [_loadOlderMessages]).
  List<MessageData> _olderMessages = const [];

  /// Son gelen canlı mesaj listesi (en yeni başta).
  List<MessageData> _liveMessages = const [];

  /// Canlı akışın alt ucu sabit mi ([ChatManager.messagesSinceStream]):
  /// odaklı açılışta ya da ilk eski sayfa yüklenince sabitlenir; yeni mesaj
  /// geldikçe canlı liste büyür ve eski sayfalarla arasında boşluk kalmaz.
  bool _liveAnchored = false;

  bool _loadingOlder = false;

  /// Son eski sayfa yüklenemedi; otomatik tekrar denenmez, en üstte "Tekrar
  /// dene" görünür.
  bool _olderLoadFailed = false;

  /// Eski sayfa sunucu yerine cihazdaki önbellekten geldi (çevrimdışı) ve
  /// önbellekte daha eskisi yok: en üstte bağlantı notu görünür.
  bool _olderOffline = false;

  /// Sohbetin ilk mesajına gelindi; daha eski mesaj yok (bkz.
  /// [_atHistoryStart]).
  bool _reachedStart = false;

  /// Sayfalama sıfırlandıkça artar; bu arada tamamlanan eski bir yükleme
  /// sonucunu yok saymak için.
  int _pagingGeneration = 0;

  /// Liste en üste bu kadar piksel kala eski mesajlar istenir.
  static const double _loadOlderThreshold = 400.0;

  /// Uygulama ön planda mı; arka plandayken gelen mesajlar okunmuş sayılmaz.
  bool _appInForeground = true;

  late final ChatManager _chatManager;

  /// Mesaj yazma kutusu. Sayfaya aittir: bir sohbette yazılıp gönderilmeyen
  /// metin başka bir sohbetin kutusuna taşınmaz.
  final TextEditingController _messageController = TextEditingController();

  /// Mesaj kutusunun odağı: "Yanıtla" seçilince klavye açılsın.
  final FocusNode _inputFocusNode = FocusNode();

  /// Yanıtlanan mesaj; mesaj kutusunun üstünde alıntısı görünür ve gönderilen
  /// metin bu mesaja yanıt olarak yazılır.
  final ValueNotifier<MessageData?> _replyTarget =
      ValueNotifier<MessageData?>(null);

  /// Admin başlığındaki danışanın adı; alıntılarda danışanın mesajlarının
  /// sahibi olarak yazar.
  String? _clientName;

  /// Öğün seçicinin seçenekleri; seçici ilk açıldığında bir kez okunur (bkz.
  /// [_loadMealChoices]).
  Future<List<({Meals meal, String label})>>? _mealChoicesFuture;

  /// Mesaj listesinin kaydırma kontrolcüsü. Sayfaya aittir: iki sohbet üst
  /// üste açıldığında (ör. bildirimden) aynı kontrolcü iki listeye bağlanmaz.
  /// Konum saklanmaz: odaklı düzenden çıkınca liste en yeni mesajdan başlar.
  final ScrollController _scrollController =
      ScrollController(keepScrollOffset: false);

  /// Admin başlığındaki danışan adı. [ChatPage.userDisplayName] verilmediyse
  /// açılışta bir kez okunur; her çizimde yeniden okunup başlık titremez.
  Future<UserModel?>? _userFuture;

  /// Sohbet hedef mesajda (odaklı düzende) mı gösteriliyor. "En yeniye git"
  /// ile kapanır ve liste normal düzene, en yeni mesaja döner.
  late bool _focusActive;

  /// Gidilen mesaj: açılışta [ChatPage.focusMessageId]; sonra bir alıntıya ya
  /// da galerideki bir fotoğrafa dokununca o mesaj (bkz. [_focusOn]).
  String? _focusMessageId;

  /// [ChatPage.focusMessageId] ile gelen mesajın baloncuğuna takılan anahtar:
  /// mesajın ekranda kurulup kurulmadığı bununla izlenir.
  final GlobalKey _focusMessageKey = GlobalKey();

  /// Hedef mesajı taşıyan sliver'ın anahtarı; viewport'un sıfır noktası
  /// (bkz. [_buildMessageList]).
  static const Key _focusCenterKey = ValueKey<String>('focusCenterSliver');

  /// Hedef mesajı ortalama bir kez yapılır (mesaj listeye ilk girdiğinde).
  bool _focusRevealStarted = false;

  /// Hedef mesaj şu an vurgulu mu: ortalandıktan sonra kısa süre yanar.
  /// Yalnızca hedef baloncuk dinler; vurgu sayfayı yeniden çizmez.
  final ValueNotifier<bool> _focusHighlighted = ValueNotifier<bool>(false);

  /// "En yeniye git" düğmesi görünsün mü: odaklı düzende en yeni mesaj
  /// ekranda değilken.
  final ValueNotifier<bool> _showJumpToLatest = ValueNotifier<bool>(false);

  /// Düğmedeki okunmamış mesaj sayısı; odaklı açılışta bir kez okunur.
  final ValueNotifier<int> _unreadCount = ValueNotifier<int>(0);

  /// Sohbet henüz okundu işaretlenmedi mi. Odaklı açılışta ekran eski bir
  /// mesajdadır ve okunmamış mesajlar aşağıda görünmeden durur; okundu işareti
  /// kullanıcı en yeni mesaja inince konur (bkz. [_onListMetrics]).
  bool _markReadPending = false;

  /// En yeni mesaj bu kadar piksel içindeyse "ekranda" sayılır.
  static const double _latestTolerance = 16.0;

  /// En yeni mesaj şu an ekranda mı (bkz. [_onListMetrics]).
  bool _atLatest = true;

  /// Son çizilen listedeki en yeni mesajın kimliği; yeni gelen mesajları
  /// ayırt etmek için (bkz. [_noteNewMessages]).
  String? _newestMessageId;

  /// Mesaj listesi (boş da olsa) en az bir kez çizildi mi; ilk listedeki
  /// mesajlar yeni gelmiş sayılmaz.
  bool _messagesShown = false;

  /// En yeni mesaja kaydırma süresi.
  static const Duration _scrollToLatestDuration = Duration(milliseconds: 250);

  /// Hedef baloncuğun kurulmasını beklerken en fazla kaç kare denenir. Mesaj
  /// zaten ilk karede kurulu olur; bu, gecikmeli bir kareye karşı emniyet payı.
  static const int _maxFocusRevealAttempts = 10;

  /// Hedef mesajın ekrandaki yeri: 0.5 = tam orta.
  static const double _focusAlignment = 0.5;

  /// Hedefi ortalama süresi.
  static const Duration _focusRevealDuration = Duration(milliseconds: 300);

  /// Vurgunun ekranda kalma süresi.
  static const Duration _focusHighlightDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    
    // Register for app lifecycle changes to handle background/foreground transitions
    WidgetsBinding.instance.addObserver(this);
    
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    _chatManager = context.read<ChatManager>();
    
    // Resolve chat ID once and cache it
    _chatId = widget.overrideChatId ?? _currentUid;
    
    // Determine if current user is an admin
    _isAdminUser = ChatManager.isAdminUid(_currentUid);

    _focusMessageId = widget.focusMessageId;
    _focusActive = _focusMessageId != null;
    // Odaklı açılışta ekran eski bir mesajdadır, en yeni mesaj görünmez.
    _atLatest = !_focusActive;

    _clientName = widget.userDisplayName;
    if (_showsUserTitle && widget.userDisplayName == null) {
      final Future<UserModel?> userFuture =
          Provider.of<UserProvider>(context, listen: false)
              .fetchUserDetails(userId: _chatId);
      _userFuture = userFuture;
      userFuture.then((user) {
        if (!mounted || user == null) return;
        final String name = user.fullName;
        if (name.isNotEmpty) setState(() => _clientName = name);
      }, onError: (Object e) {});
    }

    // Suppress in-app notifications for this chat while it is on top.
    FcmService().openChat(_chatId);

    if (_focusActive) {
      // Ekran eski bir mesajda açılıyor: okundu işareti en yeniye inilince.
      _markReadPending = true;
      _loadUnreadCount();
      _openFocusWindow();
    } else {
      // Okundu işareti ilk liste gelince konur (bkz. [_noteNewMessages]).
      _messagesStream = _chatManager.messagesStreamFor(_chatId);
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Resume in-app notifications for this chat (another chat page below
    // keeps its own suppression).
    FcmService().closeChat(_chatId);
    _messageController.dispose();
    _inputFocusNode.dispose();
    _replyTarget.dispose();
    _scrollController.dispose();
    _focusHighlighted.dispose();
    _showJumpToLatest.dispose();
    _unreadCount.dispose();
    super.dispose();
  }

  /// Admin başka bir danışanın sohbetine bakıyorsa başlıkta danışanın adı
  /// görünür.
  bool get _showsUserTitle => widget.overrideChatId != null && _isAdminUser;

  /// Mark chat as read (resets unread count) based on user type. Sayfa
  /// kapanırken de çağrıldığı için context kullanmaz.
  Future<void> _markChatAsRead() async {
    try {
      if (_isAdminUser) {
        await _chatManager.markChatAsRead(_chatId);
      } else {
        await _chatManager.markChatAsReadForUser(_chatId);
      }
    } catch (e) {
    }
  }

  /// "En yeniye git" düğmesindeki okunmamış sayısını okur.
  Future<void> _loadUnreadCount() async {
    try {
      final int count = await _chatManager.currentUserUnreadCount(_chatId);
      // Bu arada en yeniye inilip okundu işaretlendiyse sayı artık geçersiz.
      if (!mounted || !_markReadPending) return;
      _unreadCount.value = count;
    } catch (e) {
      // Sayı yalnızca bilgi amaçlı: okunamazsa düğme sayısız görünür.
    }
  }

  /// Admin-only: confirm and permanently delete this chat.
  ///
  /// Deletes all messages and the photos sent directly to the chat (meal
  /// photos stay in the client's meal records, see [ChatManager.deleteChat]),
  /// then returns to the previous screen (the admin chat list).
  Future<void> _confirmAndDeleteChat() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Sohbeti Sil',
      message: 'Bu sohbet ve tüm mesajları kalıcı olarak silinecek. '
          '${ChatPage.deleteChatPhotosNote} Bu işlem geri alınamaz.\n\n'
          'Devam etmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed) {
      return;
    }

    // Re-checked after the await: the widget may be gone by now.
    if (!mounted) return;
    final chat = context.read<ChatManager>();

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Sohbet siliniyor...');
      loadingOpen = true;
    }

    try {
      await chat.deleteChat(_chatId);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Sohbet silindi.');
      }

      // Return to the previous screen (the chat list or Öğün Fotoğrafları)
      // now that this chat no longer exists.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Sohbet silinemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // In the background no chat's notifications are suppressed; back in the
    // foreground the chat on top is suppressed again.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _appInForeground = false;
      FcmService().setInForeground(false);
    } else if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      FcmService().setInForeground(true);
      // Ekran en yeni mesajdaysa (arka plandayken gelenler dahil) sohbet
      // okunmuş sayılır; değilse işaret en yeniye inilince konur.
      if (_atLatest) {
        _markReadPending = false;
        _unreadCount.value = 0;
        _markChatAsRead();
      }
    }
  }

  /// Check and request photo library permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkPhotoPermission() async {
    Permission permission;
    if (Platform.isIOS) {
      permission = Permission.photos;
    } else {
      permission = Permission.photos;
    }

    var status = await permission.status;

    // Already granted or limited access - proceed
    if (status.isGranted || status.isLimited) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await permission.request();
      
      if (status.isGranted || status.isLimited) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Fotoğraf İzni Gerekli',
      message: 'Fotoğraf göndermek için galeri erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek fotoğraf erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Check and request camera permission.
  /// Returns true if permission is granted, false otherwise.
  /// Shows a dialog to open Settings if permission is permanently denied.
  Future<bool> _checkCameraPermission() async {
    var status = await Permission.camera.status;

    // Already granted - proceed
    if (status.isGranted) {
      return true;
    }

    // On iOS, 'denied' means we can still request (user hasn't seen dialog yet)
    // On iOS, 'permanentlyDenied' means user denied and we must go to settings
    // Always try to request first if not permanently denied or restricted
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await Permission.camera.request();
      
      if (status.isGranted) {
        return true;
      }
    }

    // Permission denied or permanently denied - show dialog to open Settings
    if (!mounted) return false;
    
    final shouldOpenSettings = await DialogUtils.openConfirm(
      context,
      title: 'Kamera İzni Gerekli',
      message: 'Fotoğraf çekebilmek için kamera erişim izni gereklidir.\n\n'
          'Lütfen Ayarlar\'a giderek kamera erişimine izin verin.',
      confirmText: 'Ayarlara Git',
      cancelText: 'İptal',
    );

    if (shouldOpenSettings) {
      await openAppSettings();
    }
    return false;
  }

  /// Fotoğraf seçtirir: kameradan tek, galeriden en fazla [limit] tane.
  /// İzin yoksa ya da vazgeçilirse boş liste döner. Masaüstünde izin sorulmaz
  /// (galeri dosya seçicidir).
  Future<List<XFile>> _pickImages(ImageSource source, {required int limit}) async {
    if (source == ImageSource.camera) {
      if (!_isDesktopPlatform && !await _checkCameraPermission()) {
        return const [];
      }
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      return image == null ? const [] : [image];
    }

    if (!_isDesktopPlatform && !await _checkPhotoPermission()) {
      return const [];
    }
    // Çoklu seçicinin sınırı en az 2 olabilir.
    if (limit < 2) {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      return image == null ? const [] : [image];
    }
    return _picker.pickMultiImage(limit: limit);
  }

  /// Seçici sınırı uygulamadıysa (bazı platformlar) öğünün kalan hakkından
  /// fazla fotoğraflar bırakılır ve kullanıcıya söylenir.
  Future<List<XFile>> _limitPicked(List<XFile> picked, int limit) async {
    if (picked.length <= limit) return picked;
    if (mounted) {
      await DialogUtils.openInfo(
        context,
        title: _photoLimitTitle,
        message: '${MealModel.maxImagesReachedMessage}\n\nSeçtiğiniz '
            'fotoğraflardan ilk $limit tanesi gönderilecek.',
      );
    }
    return picked.take(limit).toList();
  }

  /// Seçilen öğün fotoğraflarını sıraya ekler: fotoğraflar listenin altında
  /// hemen görünür ve tek tek yüklenir (bkz. [PendingUpload]); ekran
  /// kilitlenmez.
  void _enqueueMealUploads(List<XFile> images, Meals meal) {
    if (images.isEmpty || !mounted) return;
    final ChatManager chat = context.read<ChatManager>();
    final MealManager mealManager =
        Provider.of<MealManager>(context, listen: false);

    chat.enqueueUploads([
      for (final XFile image in images)
        PendingUpload(
          chatId: _chatId,
          image: image,
          meal: meal,
          runner: (upload) => _uploadMealPhoto(upload, mealManager, chat),
        ),
    ]);
    _showLatest();
  }

  /// Öğün fotoğrafını öğün kaydına ekler ve sohbete gönderir (bkz.
  /// [MealManager.uploadChatMealPhoto]). Sohbet ekranı kapanmış olsa da
  /// çalışır: context'e dokunmaz, diyalog yalnızca ekran açıksa gösterilir.
  Future<void> _uploadMealPhoto(
    PendingUpload upload,
    MealManager mealManager,
    ChatManager chat,
  ) async {
    final bool postedToChat = await mealManager.uploadChatMealPhoto(
      upload,
      userId: _currentUid,
      chatManager: chat,
    );
    // Fotoğraf öğüne kaydedildi, yalnızca sohbete düşmedi: kullanıcı onu
    // tekrar yüklemesin. Beklenmez: sıradakiler diyalog kapanmadan da
    // yüklensin.
    if (!postedToChat && mounted) {
      DialogUtils.openInfo(
        context,
        title: _chatPostFailedTitle,
        message: _chatPostFailedText,
      );
    }
  }

  /// Öğün fotoğrafı yükleme akışı: öğün seçimi → öğünün kalan fotoğraf
  /// hakkı (seçtirmeden önce) → kaynak → fotoğraf(lar) → sıraya ekleme.
  /// Galeriden öğünün kalan hakkı kadar fotoğraf birden seçilebilir.
  Future<void> _startMealUploadFlow() async {
    final Meals? meal = await _chooseMeal();
    if (meal == null) {
      return;
    }

    final int slotsLeft = await _mealImageSlotsLeft(meal);
    if (slotsLeft <= 0) {
      return;
    }

    final ImageSource? source = await _chooseSource();
    if (source == null) {
      return;
    }

    final List<XFile> picked = await _limitPicked(
      await _pickImages(source, limit: slotsLeft),
      slotsLeft,
    );
    _enqueueMealUploads(picked, meal);
  }

  /// Öğüne bugün daha kaç fotoğraf eklenebilir ([MealModel.maxImages]).
  /// Sırada bekleyen ya da yüklenen aynı öğün fotoğrafları da hak sayılır:
  /// kayıtta henüz görünmeseler de yüklenecekler. Hak kalmadıysa uyarı
  /// gösterip 0 döner; kullanıcı fotoğraf seçip yüklemeyi beklemeden öğrenir.
  /// Okunamazsa sınır sayılır: yükleme sırasında [MealManager.uploadMealImg]
  /// sınırı yine uygular.
  Future<int> _mealImageSlotsLeft(Meals meal) async {
    if (!mounted) return 0;
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final ChatManager chat = context.read<ChatManager>();

    int slotsLeft;
    try {
      slotsLeft = await mealManager.mealImageSlotsLeft(
        userId: _currentUid,
        meal: meal,
      );
    } catch (e) {
      slotsLeft = MealModel.maxImages;
    }
    final DateTime now = DateTime.now();
    slotsLeft -= chat
        .pendingUploadsOf(_chatId)
        .where((upload) =>
            upload.meal == meal &&
            upload.isQueued &&
            DateFormatter.isSameDay(upload.createdAt, now))
        .length;
    if (slotsLeft > 0) return slotsLeft;

    if (!mounted) return 0;
    await _showMealImageLimitDialog();
    return 0;
  }

  Future<void> _showMealImageLimitDialog() {
    return DialogUtils.openInfo(
      context,
      title: MealModel.maxImagesReachedTitle,
      message: MealModel.maxImagesReachedMessage,
    );
  }

  /// Show a modal bottom sheet for meal type selection.
  ///
  /// Öğünler danışanın bugünkü diyetindeki saatleriyle listelenir ("Öğle
  /// (12:30)", "Ara (15:30)"; saat diyette yoksa "-"): birden çok ara öğünü
  /// olan danışan doğru olanı saatinden seçer, fotoğraf o öğüne kaydedilir ve
  /// o öğünün hatırlatması iptal olur. Seçenekler okunurken sayfa içinde
  /// yükleniyor gösterilir.
  ///
  /// Returns the selected Meals enum value, or null if cancelled.
  Future<Meals?> _chooseMeal() async {
    _mealChoicesFuture ??= _loadMealChoices();

    return showModalBottomSheet<Meals>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: FutureBuilder<List<({Meals meal, String label})>>(
            future: _mealChoicesFuture,
            builder: (context, snapshot) {
              final List<({Meals meal, String label})>? choices = snapshot.data;

              return ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Öğün Seçin', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (choices == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (final ({Meals meal, String label}) choice in choices)
                      ListTile(
                        title: Text(choice.label),
                        onTap: () {
                          Navigator.of(ctx).pop(choice.meal);
                        },
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Diyeti olmayan danışanın seçicideki öğünleri. Saat gösterilemediği için
  /// ara öğünler tek "Ara" seçeneğinde toplanır: saatsiz üç "Ara" birbirinden
  /// ayırt edilemezdi.
  static const List<Meals> _mealsWithoutDiet = [
    Meals.br,
    Meals.firstmid,
    Meals.lunch,
    Meals.dinner,
  ];

  /// Öğün seçicinin seçenekleri: danışanın bugünkü diyet menüsündeki öğünler,
  /// "Planım"daki sıra ve saatlerle ("Öğle (12:30)", "Ara (15:30)"); en sonda
  /// "Diğer". Saat her zaman diyetten gelir; diyette yazılı değilse "-"
  /// görünür, varsayılan saat uydurulmaz.
  ///
  /// Diyet yoksa ya da okunamazsa öğünler saatsiz listelenir ("Öğle (-)"):
  /// danışanın bir diyeti olmadığı anlaşılır ve seçici yine boş kalmaz.
  Future<List<({Meals meal, String label})>> _loadMealChoices() async {
    final DietProvider dietProvider =
        Provider.of<DietProvider>(context, listen: false);

    DietMenu menu = const DietMenu.empty();
    try {
      final DietDocument? diet =
          await dietProvider.fetchLatestDietDocument(_currentUid);
      menu = DietMenu.forDate(
        weekday: DietMenu.fromSubtitles(diet?.subtitles),
        weekend: DietMenu.fromSubtitles(diet?.weekendSubtitles),
        date: DateTime.now(),
      );
    } catch (e) {
      // Diyet okunamazsa diyetsiz seçenekler gösterilir.
    }

    final List<Meals> meals = menu.mealsWithContent.isNotEmpty
        ? menu.mealsWithContent
        : _mealsWithoutDiet;

    return [
      for (final Meals meal in meals)
        (
          meal: meal,
          label: '${meal.displayLabel} (${formatMealTime(menu.timeOf(meal))})',
        ),
      (meal: Meals.none, label: Meals.none.displayLabel),
    ];
  }

  /// Show a dialog for image source selection (gallery or camera).
  /// Masaüstünde kamera olmadığı için doğrudan galeri (dosya seçici) açılır.
  ///
  /// Returns the selected ImageSource, or null if cancelled.
  Future<ImageSource?> _chooseSource() async {
    if (_isDesktopPlatform) return ImageSource.gallery;
    return showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kaynak'),
        content: const Text('Görsel kaynağını seçin.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, ImageSource.gallery);
            },
            child: const Text('Galeri'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, ImageSource.camera);
            },
            child: const Text('Kamera'),
          ),
        ],
      ),
    );
  }

  /// Sohbeti hedef mesajda açmak için mesaj penceresini yükler (bkz.
  /// [ChatManager.openFocusWindow]). Açılamazsa sohbet en yeni mesajdan açılır
  /// ve nedeni kullanıcıya söylenir.
  Future<void> _openFocusWindow() async {
    final String? targetId = _focusMessageId;
    if (targetId == null) return;

    final FocusWindow window;
    try {
      window = await _chatManager.openFocusWindow(_chatId, targetId);
    } catch (e) {
      if (!mounted || !_focusActive || _focusMessageId != targetId) return;
      _showFocusUnavailable(_focusErrorText);
      return;
    }
    // Bu arada odaktan çıkıldıysa (ör. mesaj gönderildi) ya da başka bir
    // mesaja gidildiyse bu pencereye gerek yok.
    if (!mounted || !_focusActive || _focusMessageId != targetId) return;

    final Stream<List<MessageData>>? messages = window.messages;
    if (messages == null) {
      _showFocusUnavailable(window.failure == FocusWindowFailure.tooOld
          ? _focusTooOldText
          : _focusNotFoundText);
      return;
    }

    setState(() {
      _messagesStream = messages;
      _liveAnchored = true;
      _olderMessages = window.olderMessages;
      _reachedStart =
          window.olderMessages.length < ChatManager.focusWindowOlderCount;
    });
  }

  /// Hedef mesaja gidilemedi: sohbet en yeni mesajdan açılır ve nedeni kısa
  /// bir bilgi şeridiyle söylenir.
  void _showFocusUnavailable(String message) {
    _leaveFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Sohbeti [messageId] mesajında yeniden açar (bkz. [_openFocusWindow]):
  /// yanıttaki alıntıya ya da galerideki bir fotoğrafa dokununca. Mesaj
  /// yüklü olmasa da (eski sayfalarda) bulunur ve vurgulanır.
  ///
  /// Mesaj zaten yüklüyse (canlı listede ya da eski sayfalarda) sorgu
  /// yapılmaz: liste yerinde o mesaja odaklanır. Canlı akışın alt ucu
  /// sabitlenir ki yeni mesajlar gelince hedef listeden düşmesin.
  void _focusOn(String messageId) {
    _showJumpToLatest.value = false;
    final bool loaded =
        _liveMessages.any((message) => message.id == messageId) ||
            _olderMessages.any((message) => message.id == messageId);
    setState(() {
      _focusMessageId = messageId;
      _focusActive = true;
      _focusRevealStarted = false;
      if (loaded) {
        _anchorLiveMessages();
      } else {
        _resetPaging();
      }
    });
    if (!loaded) _openFocusWindow();
  }

  /// Canlı akışın alt ucunu listedeki en eski canlı mesaja sabitler
  /// ([ChatManager.messagesSinceStream]): yeni mesaj geldikçe liste büyür,
  /// hiçbir mesaj listeden düşmez. Zaten sabitse bir şey yapmaz.
  void _anchorLiveMessages() {
    if (_liveAnchored || _liveMessages.isEmpty) return;
    final MessageData oldestLive = _liveMessages.last;
    final Timestamp? cursor =
        oldestLive.createdAt ?? oldestLive.clientCreatedAt;
    if (cursor == null) return;
    _liveAnchored = true;
    _messagesStream = _chatManager.messagesSinceStream(_chatId, cursor);
  }

  /// Odaklı düzenden çıkar: liste son mesajlarla, en yeni mesajdan başlar.
  void _leaveFocus() {
    _showJumpToLatest.value = false;
    setState(() {
      _focusActive = false;
      _resetPaging();
      _messagesStream = _chatManager.messagesStreamFor(_chatId);
    });
  }

  /// Eski sayfaları bırakır; sohbet yeniden son mesajlarla başlar.
  void _resetPaging() {
    _pagingGeneration++;
    _olderMessages = const [];
    _liveAnchored = false;
    _loadingOlder = false;
    _olderLoadFailed = false;
    _olderOffline = false;
    _reachedStart = false;
  }

  /// Sohbetin başı listede mi. Canlı akış sabitlenmemişken yalnızca son
  /// [ChatManager.messagesPageSize] mesaj dinlenir; yeni mesajlarla liste
  /// dolunca en eski mesaj listeden düşer ve baş artık listede değildir.
  bool get _atHistoryStart =>
      _reachedStart &&
      (_liveAnchored || _liveMessages.length < ChatManager.messagesPageSize);

  /// Liste en üste yaklaşınca bir sonraki eski sayfayı ister. Kaydırma ya da
  /// ölçü bildirimi sırasında çağrılır; durum değişikliği hemen ardından
  /// yapılır.
  void _requestOlderMessages() {
    if (_loadingOlder ||
        _atHistoryStart ||
        _olderLoadFailed ||
        _liveMessages.isEmpty) {
      return;
    }
    Future<void>.microtask(_loadOlderMessages);
  }

  /// Eski mesajların bir sonraki sayfasını yükler ve listenin altına (en
  /// üste) ekler.
  ///
  /// İlk sayfada canlı akışın alt ucu, o an listedeki en eski mesaja
  /// sabitlenir ([_anchorLiveMessages]): yeni mesaj geldikçe canlı liste
  /// büyür, eski sayfalarla arasında boşluk kalmaz. Sayfa sunucudan okunur;
  /// çevrimdışıyken cihazdaki önbellekten gelir, önbellekte daha eskisi
  /// yoksa en üstte bağlantı notu ve "Tekrar dene" görünür.
  Future<void> _loadOlderMessages() async {
    if (!mounted ||
        _loadingOlder ||
        _atHistoryStart ||
        _olderLoadFailed ||
        _liveMessages.isEmpty) {
      return;
    }

    // Son mesajlar tek sayfaya sığdıysa daha eskisi yoktur.
    if (!_liveAnchored &&
        _liveMessages.length < ChatManager.messagesPageSize) {
      setState(() => _reachedStart = true);
      return;
    }

    final MessageData oldest =
        _olderMessages.isNotEmpty ? _olderMessages.last : _liveMessages.last;
    final Timestamp? cursor = oldest.createdAt ?? oldest.clientCreatedAt;
    if (cursor == null) return;

    final int generation = _pagingGeneration;
    setState(() {
      _loadingOlder = true;
      _anchorLiveMessages();
    });

    try {
      final ({List<MessageData> messages, bool fromCache}) page =
          await _chatManager.fetchOlderPage(_chatId, cursor);
      if (!mounted || generation != _pagingGeneration) return;
      final bool shortPage =
          page.messages.length < ChatManager.messagesPageSize;
      setState(() {
        _olderMessages = [..._olderMessages, ...page.messages];
        if (page.fromCache) {
          // Önbellek eksik olabilir: kısa sayfa sohbetin başı sayılmaz.
          _olderOffline = shortPage;
          _olderLoadFailed = shortPage;
        } else {
          _reachedStart = shortPage;
        }
        _loadingOlder = false;
      });
    } catch (e) {
      if (!mounted || generation != _pagingGeneration) return;
      setState(() {
        _loadingOlder = false;
        _olderLoadFailed = true;
      });
    }
  }

  void _retryOlderMessages() {
    setState(() {
      _olderLoadFailed = false;
      _olderOffline = false;
    });
    _loadOlderMessages();
  }

  /// Eski sayfalar canlı dinlenmez: üzerinde işlem yapılan mesaj (ifade,
  /// fotoğraf silme) yeniden okunup listede güncellenir. Canlı listedeki
  /// mesajlar zaten kendiliğinden güncellenir.
  Future<void> _refreshOlderMessage(String messageId) async {
    if (!_olderMessages.any((message) => message.id == messageId)) return;

    final int generation = _pagingGeneration;
    final MessageData? fresh;
    try {
      fresh = await _chatManager.fetchMessage(_chatId, messageId);
    } catch (e) {
      return;
    }
    if (fresh == null || !mounted || generation != _pagingGeneration) return;

    final int index =
        _olderMessages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _olderMessages = [..._olderMessages]..[index] = fresh!;
    });
  }

  /// Listenin en üstündeki satır: eski mesajlar yüklenirken gösterge,
  /// yüklenemediyse "Tekrar dene", sohbetin başına gelindiyse küçük bir not.
  Widget? _buildHistoryEdge() {
    if (_loadingOlder) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_olderLoadFailed) {
      return Center(
        child: TextButton.icon(
          onPressed: _retryOlderMessages,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(
            '${_olderOffline ? _olderOfflineText : _olderLoadErrorText} '
            '$_retryLabel',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_atHistoryStart) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text(
            _historyStartText,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return null;
  }

  /// İlk çizimden sonra hedef mesajı ortalamayı bir kez planlar.
  void _scheduleFocusReveal() {
    if (_focusRevealStarted) return;

    _focusRevealStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealFocusedMessage();
    });
  }

  /// Hedef mesajı ekranın ortasına getirir ve kısa süre vurgular.
  ///
  /// Mesaj, sıfır noktasına oturan sliver'ın ilk çocuğu olduğu için ilk karede
  /// zaten kuruludur ve ekranın alt kenarında durur; buradaki hareket onu
  /// ortaya alır.
  Future<void> _revealFocusedMessage() async {
    for (int attempt = 0; attempt < _maxFocusRevealAttempts; attempt++) {
      final BuildContext? bubbleContext = _focusMessageKey.currentContext;
      if (bubbleContext != null && bubbleContext.mounted) {
        await Scrollable.ensureVisible(
          bubbleContext,
          alignment: _focusAlignment,
          duration: _focusRevealDuration,
          curve: Curves.easeOut,
        );
        await _flashFocusHighlight();
        return;
      }

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  /// Hedef mesajı kısa süre vurgular; kullanıcı hangi mesaja geldiğini görsün.
  Future<void> _flashFocusHighlight() async {
    if (!mounted) return;
    _focusHighlighted.value = true;

    await Future<void>.delayed(_focusHighlightDuration);
    if (!mounted) return;
    _focusHighlighted.value = false;
  }

  /// Liste kaydırıldığında ya da ölçüleri değiştiğinde (ilk yerleşim, yeni
  /// mesaj) en yeni mesajın ekranda olup olmadığına bakar: ekrandaysa bekleyen
  /// okundu işaretini koyar, odaklı düzende değilse "En yeniye git" düğmesini
  /// gösterir.
  ///
  /// Liste ters (reverse) olduğundan en yeni mesaj kaydırma aralığının alt
  /// ucundadır ([ScrollMetrics.minScrollExtent]); odaklı düzende bu uç
  /// negatiftir, normal düzende sıfır.
  bool _onListMetrics(
    ScrollMetrics metrics,
    int depth, {
    required bool focusLayout,
  }) {
    if (depth != 0) return false;

    final bool atLatest =
        metrics.pixels <= metrics.minScrollExtent + _latestTolerance;
    _atLatest = atLatest;

    // Ters listede en eski mesaj kaydırma aralığının üst ucunda.
    if (metrics.maxScrollExtent - metrics.pixels <= _loadOlderThreshold) {
      _requestOlderMessages();
    }
    if (atLatest && _markReadPending && _appInForeground) {
      _markReadPending = false;
      _unreadCount.value = 0;
      _markChatAsRead();
    }
    // Odaklı düzende en yeni mesaj ekranda değilse; normal düzende kullanıcı
    // biraz yukarı kaydırınca.
    _showJumpToLatest.value = focusLayout
        ? !atLatest
        : metrics.pixels > metrics.minScrollExtent + _jumpButtonThreshold;
    return false;
  }

  /// Listeyi en yeni mesajın ekranda olup olmadığını izleyen dinleyicilerle
  /// sarar. Ölçü bildirimi ilk yerleşimde ve yeni mesaj eklenince, kaydırma
  /// bildirimi kullanıcı kaydırdıkça gelir.
  Widget _trackLatest(Widget list, {required bool focusLayout}) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _onListMetrics(
        notification.metrics,
        notification.depth,
        focusLayout: focusLayout,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _onListMetrics(
          notification.metrics,
          notification.depth,
          focusLayout: focusLayout,
        ),
        child: list,
      ),
    );
  }

  /// "En yeniye git": odaklı düzendeyse normal düzene döner (liste en
  /// yeniden başlar), normal düzende en yeni mesaja kaydırır; okundu işareti
  /// orada konur.
  void _jumpToLatest() => _showLatest();

  /// Kullanıcının az önce gönderdiği mesaj ekranda görünsün: odaklı düzendeyse
  /// normal düzene geçilir, normal düzende en yeni mesaja kaydırılır.
  void _showLatest() {
    if (_focusActive) {
      _leaveFocus();
      return;
    }
    _scrollToLatest();
  }

  /// Listeyi en yeni mesaja kaydırır (ters listede kaydırma aralığının alt
  /// ucu).
  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.positions.last;
    if (position.pixels <= position.minScrollExtent) return;
    position.animateTo(
      position.minScrollExtent,
      duration: _scrollToLatestDuration,
      curve: Curves.easeOut,
    );
  }

  /// Liste her yenilendiğinde yeni gelen mesajlara bakar.
  ///
  /// İlk liste gelince (odaklı açılış değilse) sohbet okunmuş işaretlenir:
  /// işaret listedeki mesajlardan sonra yazıldığı için açılış anında gelen
  /// bir mesaj da okunmuş sayılır. Sonra gelen mesajlar aşağıdaki gibi
  /// işaretlenir; çıkarken ayrıca işaret yazılmaz.
  ///
  /// Kullanıcı en yeni mesajdaysa yeni mesaj ekrandadır: sohbet okunmuş
  /// sayılır (sohbet açıkken gelen mesaj okunmamış rozeti bırakmaz); odaklı
  /// düzende yeni mesajlar görünür alanın altına eklendiği için liste onları
  /// gösterecek kadar kayar. Kullanıcı eski mesajlardaysa okundu işareti en
  /// yeniye inince konur; karşı taraftan gelenler "En yeniye git"
  /// rozetindeki sayıya eklenir.
  void _noteNewMessages(List<MessageData> items, {required bool focusLayout}) {
    final bool firstList = !_messagesShown;
    _messagesShown = true;
    final String? previous = _newestMessageId;
    _newestMessageId = items.isEmpty ? null : items.first.id;
    if (firstList) {
      if (!_markReadPending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markIncomingSeen();
        });
      }
      return;
    }

    // Liste boştuysa (yeni sohbet) gelen her mesaj yenidir.
    final int previousIndex = previous == null
        ? items.length
        : items.indexWhere((message) => message.id == previous);
    if (previousIndex <= 0) return;

    final int incoming = items
        .take(previousIndex)
        .where((message) => message.senderId != _currentUid)
        .length;
    final bool atLatest = _atLatest;

    // Liste bu karede yerleşince uygulanır: yeni mesajın yeri ancak o zaman
    // bellidir; bildirim de çizim sırasında değil sonrasında yapılmalı.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (atLatest) {
        if (focusLayout) _scrollToLatest();
        if (incoming > 0) _markIncomingSeen();
      } else if (incoming > 0) {
        _markReadPending = true;
        _unreadCount.value += incoming;
      }
    });
  }

  /// En yeni mesajdayken gelen mesaj görüldü: uygulama ön plandaysa sohbet
  /// okunmuş işaretlenir; arka plandaysa işaret, uygulamaya dönülünce konur.
  void _markIncomingSeen() {
    if (_appInForeground) {
      _markChatAsRead();
    } else {
      _markReadPending = true;
    }
  }

  /// Yazılan metni gönderir. Kutu hemen boşalır ve mesaj yerelde hemen
  /// listeye düşer (bkz. [ChatManager.sendTextTo]); ekranda görünsün diye en
  /// yeni mesaja inilir. Sunucu reddederse metin kutuya geri konur.
  Future<void> _sendText() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;

    final ChatManager chat = context.read<ChatManager>();
    final MessageData? replyTarget = _replyTarget.value;
    _messageController.clear();
    _replyTarget.value = null;

    final Future<void> sending = chat.sendTextTo(
      _chatId,
      text,
      replyTo: replyTarget == null ? null : MessageReply.of(replyTarget),
    );
    _showLatest();
    // Masaüstünde gönder düğmesine tıklamak kutunun odağını alır; yazmaya
    // devam edebilmek için odak kutuya döner.
    if (_isDesktopPlatform) _inputFocusNode.requestFocus();

    try {
      await sending;
    } catch (e) {
      if (!mounted) return;
      // Bu arada yeni bir şey yazılmadıysa gönderilemeyen metin (ve yanıtı)
      // geri gelir.
      if (_messageController.text.isEmpty) {
        _messageController.text = text;
        _replyTarget.value ??= replyTarget;
      }
      DialogUtils.openError(
        context,
        title: _sendErrorTitle,
        message: _sendErrorText,
      );
    }
  }

  /// Danışanın kendi gönderdiği öğün fotoğrafını onay alarak siler.
  ///
  /// Fotoğraf öğün kaydından (Öğün Fotoğrafları, Görseller sekmesi, "Planım")
  /// ve Storage'dan kalkar; sohbetteki mesaj "fotoğraf silindi" notuna döner
  /// (bkz. [MealManager.deleteChatMealPhoto]). Öğünün son fotoğrafı silindiyse
  /// öğün yüklenmemiş sayılır; hatırlatmalar buna göre yeniden kurulur.
  Future<void> _confirmAndDeleteMealPhoto(MessageData message) async {
    final String? imageUrl = message.imageUrl;
    if (imageUrl == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MealManager mealManager =
        Provider.of<MealManager>(context, listen: false);

    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: _deletePhotoTitle,
      message: _deletePhotoConfirmText,
      confirmText: _deletePhotoConfirmLabel,
      cancelText: _deletePhotoCancelLabel,
    );
    if (!confirmed) return;

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: _deletingPhotoText);
      loadingOpen = true;
    }

    try {
      await mealManager.deleteChatMealPhoto(
        userId: _currentUid,
        imageUrl: imageUrl,
        fallbackMeal: message.photoMeal,
        fallbackDate: (message.clientCreatedAt ?? message.createdAt)?.toDate(),
      );
      _refreshOlderMessage(message.id);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text(_photoDeletedText)),
      );
      _rescheduleMealReminders();
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _uploadErrorTitle,
        message: _deletePhotoErrorText,
      );
    }
  }

  /// Öğün hatırlatmalarını günün güncel durumuna göre yeniden kurar: silinen
  /// fotoğraf öğünün son fotoğrafıysa o öğünün hatırlatması geri gelir.
  void _rescheduleMealReminders() {
    final MealReminderService reminders = MealReminderService();
    if (!reminders.isSupported) return;
    reminders.scheduleMealReminders(_currentUid);
  }

  /// Toggle the current viewer's reaction on [message].
  ///
  /// Tapping the same reaction the viewer already left removes it; otherwise
  /// the reaction is set/replaced. A Cloud Function then notifies the other
  /// party that a reaction was left on their message: the office is notified
  /// for a client's reaction, the client for the office's.
  Future<void> _handleToggleReaction(MessageData message, String emoji) async {
    final chat = context.read<ChatManager>();
    final current = message.reactions[_currentUid];

    try {
      await chat.toggleReaction(_chatId, message.id, emoji, currentEmoji: current);
      _refreshOlderMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      DialogUtils.openError(
        context,
        title: 'İfade Bırakılamadı',
        message: 'İfade kaydedilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Mesaj menüsünde (uzun basma / sağ tık) seçilen işlem.
  void _handleMessageAction(MessageData message, MessageAction action) {
    switch (action) {
      case MessageAction.reply:
        _replyTarget.value = message;
        _inputFocusNode.requestFocus();
      case MessageAction.copy:
        _copyMessage(message);
      case MessageAction.showInMealPhotos:
        _openInMealPhotos(message);
      case MessageAction.deletePhoto:
        _confirmAndDeleteMealPhoto(message);
    }
  }

  /// Mesajın menüsündeki işlemler (ifadeler ayrıca, bkz. [_buildMessageBubble]).
  List<MessageAction> _actionsFor(MessageData message) {
    final bool hasText = (message.text ?? '').isNotEmpty;
    return [
      MessageAction.reply,
      if (hasText && !message.isMealPhoto && !message.photoDeleted)
        MessageAction.copy,
      // Admin, danışanın öğün fotoğrafını Öğün Fotoğrafları'nda görebilir.
      if (_isAdminUser && message.isMealPhoto && message.senderId == _chatId)
        MessageAction.showInMealPhotos,
      // Danışan sohbetten yüklediği öğün fotoğrafını silebilir.
      if (!_isAdminUser &&
          message.senderId == _currentUid &&
          message.isMealPhoto)
        MessageAction.deletePhoto,
    ];
  }

  /// Mesajın metnini panoya kopyalar.
  void _copyMessage(MessageData message) {
    Clipboard.setData(
      ClipboardData(text: Meals.chatTextForDisplay(message.text ?? '')),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(_copiedText),
        duration: _copiedFeedbackDuration,
      ),
    );
  }

  /// Alıntılarda mesajın sahibinin adı: kendi mesajı "Siz", ofisin mesajı
  /// danışana diyetisyenin adıyla, admin'e "Diyetisyen"; danışanın mesajı
  /// danışanın adıyla.
  String _senderLabel(String senderId) {
    if (senderId == _currentUid) return _youLabel;
    if (ChatManager.isAdminUid(senderId)) {
      return _isAdminUser
          ? _officeLabel
          : PushNotificationReference.chatAdminToUserTitle;
    }
    return _clientName ?? _clientFallbackLabel;
  }

  /// Fotoğrafı tam ekranda açar: önce küçük görsel görünür, orijinal iner.
  void _openPhoto(MessageData message) {
    final String? imageUrl = message.imageUrl;
    if (imageUrl == null) return;

    final Meals? meal = message.isMealPhoto ? message.photoMeal : null;
    final DateTime? sentAt = message.sentAt;
    showFullScreenImage<void>(
      context,
      imageUrl: imageUrl,
      thumbUrl: message.thumbUrl,
      title: [
        if (meal != null) meal.displayLabel,
        if (sentAt != null) DateFormatter.formatLongDateTime(sentAt),
      ].join(' · '),
    );
  }

  /// Admin: danışanın öğün fotoğrafını Öğün Fotoğrafları'nda, fotoğrafın
  /// günüyle ve danışana süzülmüş olarak açar; fotoğraf vurgulanır. Orada bu
  /// danışanın bir fotoğrafı için "Sohbette göster" seçilirse sayfa kapanır
  /// ve sohbet o mesaja gider (yeni bir sohbet sayfası açılmaz).
  Future<void> _openInMealPhotos(MessageData message) async {
    final String? imageUrl = message.imageUrl;
    if (imageUrl == null) return;

    final MealManager mealManager =
        Provider.of<MealManager>(context, listen: false);
    final DateTime day = mealManager.mealPhotoLocation(_chatId, imageUrl)?.date ??
        message.sentAt ??
        DateTime.now();
    final String? messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMealPhotosPage(
          initialDay: day,
          focusUserId: _chatId,
          focusImageUrl: imageUrl,
          returnToChatUserId: _chatId,
        ),
      ),
    );
    if (messageId == null || !mounted) return;
    _focusOn(messageId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // If admin is viewing a user's chat, show the user's name as a tappable
        // title that opens their uploaded-photos gallery.
        // Otherwise show the default (non-tappable) chat title.
        title: _showsUserTitle
            ? _buildTappableUserTitle(_chatId)
            : Text(PushNotificationReference.chatAdminToUserTitle),
        actions: [
          if (_isAdminUser) const HomeButton(),
          // Silme gibi geri alınamayan işlem menüde durur: başlıkta
          // yanlışlıkla basılmasın. Silmeden önce onay alınır.
          if (_isAdminUser)
            PopupMenuButton<_ChatMenuAction>(
              tooltip: _chatMenuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _ChatMenuAction.deleteChat:
                    _confirmAndDeleteChat();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<_ChatMenuAction>(
                  value: _ChatMenuAction.deleteChat,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      _deleteChatLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list - uses cached stream, doesn't rebuild on ChatManager
          // changes; yalnızca bekleyen yüklemeler değişince yeniden çizilir.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Selector<ChatManager, List<PendingUpload>>(
                  selector: (_, chat) => chat.pendingUploadsOf(_chatId),
                  builder: (context, pending, _) =>
                      StreamBuilder<List<MessageData>>(
                    stream: _messagesStream,
                    builder: (context, snap) {
                      // Akış değişince (ör. odaktan çıkınca) eldeki liste
                      // yenisi gelene kadar ekranda kalır; yalnızca hiç veri
                      // yokken yükleniyor gösterilir.
                      final List<MessageData>? data = snap.data;
                      if (data == null) {
                        if (snap.hasError) {
                          return const Center(
                            child: Text(_messagesLoadErrorText),
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      }

                      _liveMessages = data;
                      final List<MessageData> items = _olderMessages.isEmpty
                          ? data
                          : [...data, ..._olderMessages];

                      if (items.isEmpty && pending.isEmpty) {
                        _noteNewMessages(items, focusLayout: false);
                        return const Center(child: Text('Henüz mesaj yok.'));
                      }

                      return _buildMessageList(items, pending);
                    },
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _JumpToLatestButton(
                    visible: _showJumpToLatest,
                    unreadCount: _unreadCount,
                    onPressed: _jumpToLatest,
                  ),
                ),
              ],
            ),
          ),

          _ChatInputRow(
            controller: _messageController,
            focusNode: _inputFocusNode,
            onSend: _sendText,
            // Admin öğün yüklemez: yalnızca danışan öğün fotoğrafı yükler.
            onMealUpload: _isAdminUser ? null : _startMealUploadFlow,
            replyTarget: _replyTarget,
            replyLabelOf: (message) => _senderLabel(message.senderId),
          ),
        ],
      ),
    );
  }

  /// Mesaj listesi.
  ///
  /// Hedef mesaj yoksa -- ya da bulunamadıysa ya da "En yeniye git" veya bir
  /// gönderimle odaktan çıkıldıysa -- sohbet her zamanki gibi en yeni mesajdan
  /// açılır. Hedef varsa (odak penceresi onu hep kapsar) liste ikiye
  /// bölünür: hedef ve ondan eski mesajlar viewport'un sıfır noktasına oturan
  /// ("center") sliver'a, hedeften yeni mesajlar ise onun altına konur.
  /// Böylece aradaki mesajlar hiç kurulmadan doğrudan hedef mesaja açılır;
  /// liste yine tek parça gibi kaydırılır (yukarı eskiye, aşağı yeniye).
  ///
  /// Arka arkaya gönderilen aynı öğünün fotoğrafları tek albüm baloncuğunda
  /// toplanır (bkz. [_groupIntoRows]); liste satırlardan kurulur.
  Widget _buildMessageList(
    List<MessageData> items,
    List<PendingUpload> pending,
  ) {
    final List<_ChatRow> rows = _groupIntoRows(items);
    final String? focusMessageId = _focusActive ? _focusMessageId : null;
    final int targetIndex = focusMessageId == null
        ? -1
        : rows.indexWhere((row) => row.contains(focusMessageId));
    _noteNewMessages(items, focusLayout: targetIndex >= 0);

    // En üstteki satır (ters listede sonda): eski mesaj göstergesi ya da notu.
    final Widget? historyEdge = _buildHistoryEdge();
    final int edgeCount = historyEdge == null ? 0 : 1;
    final int pendingCount = pending.length;

    if (targetIndex < 0) {
      // Ters listede en altta (en yeni) bekleyen yüklemeler, sonra mesajlar.
      return _trackLatest(
        ListView.builder(
          controller: _scrollController,
          reverse: true, // Newest messages at bottom
          itemCount: pendingCount + rows.length + edgeCount,
          itemBuilder: (context, i) {
            if (i < pendingCount) {
              return _buildPendingBubble(
                pending,
                pendingCount - 1 - i,
                items,
              );
            }
            final int index = i - pendingCount;
            return index < rows.length
                ? _buildRow(rows, index)
                : historyEdge!;
          },
        ),
        focusLayout: false,
      );
    }

    _scheduleFocusReveal();

    return _trackLatest(
      CustomScrollView(
        controller: _scrollController,
        reverse: true, // Newest messages at bottom
        center: _focusCenterKey,
        slivers: [
          // Hedeften yeni mesajlar ve en altta bekleyen yüklemeler: sıfır
          // noktasının altında, yeniye doğru.
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => i < targetIndex
                  ? _buildRow(rows, targetIndex - 1 - i)
                  : _buildPendingBubble(pending, i - targetIndex, items),
              childCount: targetIndex + pendingCount,
            ),
          ),
          // Hedef ve ondan eski mesajlar: sıfır noktasından yukarı doğru.
          SliverList(
            key: _focusCenterKey,
            delegate: SliverChildBuilderDelegate(
              (context, i) => targetIndex + i < rows.length
                  ? _buildRow(rows, targetIndex + i)
                  : historyEdge!,
              childCount: rows.length - targetIndex + edgeCount,
            ),
          ),
        ],
      ),
      focusLayout: true,
    );
  }

  /// Baloncukların genişlik sınırları; mesaj ve bekleyen yükleme baloncuğu
  /// aynı ölçüleri kullanır.
  _BubbleMetrics _bubbleMetrics() =>
      _BubbleMetrics.of(MediaQuery.sizeOf(context));

  /// Satırın gün ayırıcısı: listede kendisinden eski satır başka bir günse
  /// (ya da yüklü en eski satırsa) üstünde gün yazar.
  String? _dayLabelAbove(List<_ChatRow> rows, int index) {
    final DateTime day = rows[index].oldest.sentAt ?? DateTime.now();
    if (index + 1 < rows.length) {
      final DateTime older = rows[index + 1].newest.sentAt ?? DateTime.now();
      if (DateFormatter.isSameDay(day, older)) return null;
    }
    return DateFormatter.formatChatDayLabel(day);
  }

  /// Albümdeki iki fotoğraf arasında en fazla bu kadar süre olabilir.
  static const Duration _albumGap = Duration(minutes: 2);

  /// Mesajları liste satırlarına ayırır (en yeni başta): aynı kişinin arka
  /// arkaya ([_albumGap] içinde, aynı gün) gönderdiği aynı öğünün
  /// fotoğrafları tek satırda (albüm) toplanır; diğer her mesaj kendi
  /// satırındadır. Yanıt olan ya da fotoğrafı silinmiş mesaj albüme girmez.
  static List<_ChatRow> _groupIntoRows(List<MessageData> items) {
    final List<_ChatRow> rows = [];
    List<MessageData> group = [];
    for (final MessageData message in items) {
      if (group.isNotEmpty && _joinsAlbum(group, message)) {
        group.add(message);
        continue;
      }
      if (group.isNotEmpty) rows.add(_ChatRow(group));
      group = [message];
    }
    if (group.isNotEmpty) rows.add(_ChatRow(group));
    return rows;
  }

  /// [older], en yeni başta sıralı [group] albümüne katılabilir mi.
  static bool _joinsAlbum(List<MessageData> group, MessageData older) {
    final MessageData first = group.first;
    final MessageData last = group.last;
    if (!_isAlbumPhoto(first) || !_isAlbumPhoto(older)) return false;
    if (older.senderId != first.senderId ||
        older.photoMeal != first.photoMeal) {
      return false;
    }
    final DateTime newerAt = last.sentAt!;
    final DateTime olderAt = older.sentAt!;
    return DateFormatter.isSameDay(newerAt, olderAt) &&
        newerAt.difference(olderAt).abs() <= _albumGap;
  }

  static bool _isAlbumPhoto(MessageData message) =>
      message.isMealPhoto &&
      !message.photoDeleted &&
      message.replyTo == null &&
      message.photoMeal != null &&
      message.sentAt != null;

  /// Bekleyen yükleme baloncuğu ([pending] sıra sırasıyla, [index] yüklenme
  /// sırası). İlki, son mesaj başka bir gündeyse "Bugün" ayırıcısıyla
  /// başlar.
  Widget _buildPendingBubble(
    List<PendingUpload> pending,
    int index,
    List<MessageData> items,
  ) {
    final PendingUpload upload = pending[index];
    final ChatManager chat = context.read<ChatManager>();
    final DateTime now = DateTime.now();
    final DateTime? newest = items.isEmpty ? null : items.first.sentAt;
    final bool showToday =
        index == 0 && (newest == null || !DateFormatter.isSameDay(newest, now));

    final Widget bubble = PendingUploadBubble(
      key: ValueKey<String>(upload.id),
      upload: upload,
      photoSizeOf: _bubbleMetrics().photoSize,
      bubbleColor: _MessageBubble.myBubbleColor,
      onDiscard: () => chat.discardUpload(upload),
      onRetry: () => chat.retryUpload(upload),
    );
    if (!showToday) return bubble;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatDateSeparator(label: DateFormatter.formatChatDayLabel(now)),
        bubble,
      ],
    );
  }

  /// Karşı tarafın mesajıysa ifade bırakılabilir. `_chatId` sohbet sahibinin
  /// (danışanın) UID'si: `senderId == _chatId` mesajın danışandan geldiğini,
  /// admin UID'si ofisten geldiğini gösterir. Kendi mesajına ifade
  /// bırakılamaz; fotoğrafı silinmiş mesaja da.
  bool _canReactTo(MessageData message) =>
      !message.photoDeleted &&
      (_isAdminUser
          ? message.senderId == _chatId
          : ChatManager.isAdminUid(message.senderId));

  /// Tek bir satır: mesaj baloncuğu ya da albüm (gerekirse üstünde gün
  /// ayırıcısıyla); listenin iki biçimi de bunu kullanır.
  Widget _buildRow(List<_ChatRow> rows, int index) {
    final _ChatRow row = rows[index];

    Widget bubble({required bool highlighted}) {
      if (row.isAlbum) {
        return _AlbumBubble(
          messages: row.messages.reversed.toList(),
          isMe: row.newest.senderId == _currentUid,
          myUid: _currentUid,
          highlighted: highlighted,
          metrics: _bubbleMetrics(),
          canReactTo: _canReactTo,
          actionsFor: _actionsFor,
          onImageTap: _openPhoto,
          onToggleReaction: _handleToggleReaction,
          onAction: _handleMessageAction,
        );
      }

      final MessageData msg = row.newest;
      final MessageReply? reply = msg.replyTo;
      return _MessageBubble(
        message: msg,
        highlighted: highlighted,
        isMe: msg.senderId == _currentUid,
        myUid: _currentUid,
        canReact: _canReactTo(msg),
        actions: _actionsFor(msg),
        metrics: _bubbleMetrics(),
        replySenderLabel: reply == null ? null : _senderLabel(reply.senderId),
        onImageTap: _openPhoto,
        onToggleReaction: _handleToggleReaction,
        onAction: _handleMessageAction,
        onReplyTap: _focusOn,
      );
    }

    final String? focusMessageId = _focusActive ? _focusMessageId : null;
    final Widget body;
    if (focusMessageId == null || !row.contains(focusMessageId)) {
      body = bubble(highlighted: false);
    } else {
      // Anahtar yalnızca hedef satırda: ortalama bu anahtarla yapılır. Vurgu
      // yalnızca bu satırı yeniden çizer.
      body = ValueListenableBuilder<bool>(
        key: _focusMessageKey,
        valueListenable: _focusHighlighted,
        builder: (context, highlighted, _) => bubble(highlighted: highlighted),
      );
    }

    final String? dayLabel = _dayLabelAbove(rows, index);
    if (dayLabel == null) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatDateSeparator(label: dayLabel),
        body,
      ],
    );
  }

  /// Admin-only tappable app bar title: the user's name plus a small photo
  /// icon hinting that it opens the user's uploaded-photos gallery.
  Widget _buildTappableUserTitle(String userId) {
    return Tooltip(
      message: 'Yüklenen fotoğrafları gör',
      child: InkWell(
        onTap: () => _openUserMediaGallery(userId),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _buildUserNameTitle()),
              const SizedBox(width: 6),
              const Icon(Icons.photo_library_outlined, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Open the gallery listing every photo uploaded by [userId]. Galeride bir
  /// fotoğraf için "Sohbette göster" seçilirse sohbet o mesaja gider.
  Future<void> _openUserMediaGallery(String userId) async {
    final String? messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => UserMediaGalleryPage(userId: userId),
      ),
    );
    if (messageId == null || !mounted) return;
    _focusOn(messageId);
  }

  /// Build a title widget displaying the user's full name.
  ///
  /// Uses [ChatPage.userDisplayName] when the caller already knows it;
  /// otherwise shows the name read once in [initState]. Shows loading text
  /// while fetching, and falls back to "Sohbet" on error.
  Widget _buildUserNameTitle() {
    final String? knownName = widget.userDisplayName;
    if (knownName != null) {
      return Text(
        knownName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return FutureBuilder<UserModel?>(
      future: _userFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Yükleniyor...');
        }
        
        String displayName = 'Sohbet'; // Fallback
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          final firstName = user.name.trim();
          final lastName = user.surname.trim();
          displayName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
        }
        
        return Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Baloncuk ölçüleri: ekran genişliğinin bir oranı, geniş ekranda (masaüstü)
/// sabit bir üst sınır. Mesaj ve bekleyen yükleme baloncukları aynı ölçüyü
/// kullanır.
class _BubbleMetrics {
  final double textMaxWidth;
  final double imageWidth;

  /// Ölçüsü kayıtlı olmayan eski fotoğrafların yüksekliği.
  final double legacyImageHeight;

  /// En dar (dikey) ve en geniş (yatay) fotoğraf oranı. Bunların dışındaki
  /// fotoğraflar (ör. uzun ekran görüntüsü) bu orana kırpılır; baloncuk aşırı
  /// uzamaz.
  static const double _minPhotoAspectRatio = 0.75;
  static const double _maxPhotoAspectRatio = 1.9;

  const _BubbleMetrics({
    required this.textMaxWidth,
    required this.imageWidth,
    required this.legacyImageHeight,
  });

  /// Metin baloncuğunun en fazla genişliği: geniş satırlar okumayı zorlaştırır.
  static const double _maxTextBubbleWidth = 520;
  static const double _maxImageWidth = 360;
  static const double _textWidthFactor = 0.75;
  static const double _imageWidthFactor = 0.65;
  static const double _legacyImageHeightFactor = 0.25;

  factory _BubbleMetrics.of(Size screen) {
    final double imageWidth =
        (screen.width * _imageWidthFactor).clamp(0.0, _maxImageWidth);
    return _BubbleMetrics(
      textMaxWidth:
          (screen.width * _textWidthFactor).clamp(0.0, _maxTextBubbleWidth),
      imageWidth: imageWidth,
      legacyImageHeight:
          (screen.height * _legacyImageHeightFactor).clamp(0.0, imageWidth),
    );
  }

  /// Fotoğrafın baloncuktaki ölçüsü: tam genişlik, yükseklik fotoğrafın
  /// oranından. Oranı kayıtlı olmayan eski fotoğrafta sabit yükseklik.
  /// Görsel inmeden doğru yer ayrılır; liste kaymaz, fotoğraf kırpılmaz.
  Size photoSize(double? aspectRatio) {
    if (aspectRatio == null) return Size(imageWidth, legacyImageHeight);
    final double ratio =
        aspectRatio.clamp(_minPhotoAspectRatio, _maxPhotoAspectRatio);
    return Size(imageWidth, imageWidth / ratio);
  }
}

/// Mesaj listesinin bir satırı: tek mesaj ya da aynı öğünün arka arkaya
/// gönderilmiş fotoğraflarından oluşan albüm (bkz.
/// [_ChatPageState._groupIntoRows]).
class _ChatRow {
  /// Satırdaki mesajlar, en yeni başta.
  final List<MessageData> messages;

  const _ChatRow(this.messages);

  MessageData get newest => messages.first;
  MessageData get oldest => messages.last;
  bool get isAlbum => messages.length > 1;

  bool contains(String messageId) =>
      messages.any((message) => message.id == messageId);
}

/// Albüm baloncuğu: aynı öğünün arka arkaya gönderilen fotoğrafları tek
/// baloncukta, iki sütunlu kare ızgarada (tek kalan son fotoğraf tam
/// genişlikte). Her fotoğraf kendi mesajıdır: dokununca tam ekranda açılır,
/// uzun basınca (masaüstünde sağ tıklayınca) o fotoğrafın menüsü açılır ve
/// ifadesi kendi köşesinde görünür.
class _AlbumBubble extends StatelessWidget {
  /// Albümdeki fotoğraf mesajları, eskiden yeniye.
  final List<MessageData> messages;
  final bool isMe;
  final String myUid;
  final bool highlighted;
  final _BubbleMetrics metrics;
  final bool Function(MessageData message) canReactTo;
  final List<MessageAction> Function(MessageData message) actionsFor;
  final void Function(MessageData message) onImageTap;
  final void Function(MessageData message, String emoji) onToggleReaction;
  final void Function(MessageData message, MessageAction action) onAction;

  const _AlbumBubble({
    required this.messages,
    required this.isMe,
    required this.myUid,
    required this.highlighted,
    required this.metrics,
    required this.canReactTo,
    required this.actionsFor,
    required this.onImageTap,
    required this.onToggleReaction,
    required this.onAction,
  });

  /// Izgaradaki fotoğraflar arası boşluk.
  static const double _gap = 3;
  static const double _padding = 4;
  static const String _reactLabel = 'İfade Bırak';

  /// Masaüstü menüsünde "İfade Bırak" seçeneğinin değeri.
  static const String _reactMenuValue = 'react';

  @override
  Widget build(BuildContext context) {
    final MessageData newest = messages.last;
    final double width = metrics.imageWidth;
    final double tile = (width - _gap) / 2;
    // Henüz sunucuya ulaşmamış fotoğraf varsa saat ikonu onda görünür.
    final MessageData timeOf = messages.firstWhere(
      (message) => message.createdAt == null,
      orElse: () => newest,
    );

    final List<Widget> gridRows = [
      for (int i = 0; i < messages.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
          child: i + 1 < messages.length
              ? Row(
                  children: [
                    _buildTile(context, messages[i], tile, tile),
                    const SizedBox(width: _gap),
                    _buildTile(context, messages[i + 1], tile, tile),
                  ],
                )
              : _buildTile(context, messages[i], width, tile),
        ),
    ];

    return AnimatedContainer(
      duration: _MessageBubble._highlightFadeDuration,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: width + _padding * 2,
        padding: const EdgeInsets.all(_padding),
        decoration: BoxDecoration(
          color: isMe
              ? _MessageBubble.myBubbleColor
              : _MessageBubble._otherBubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MealPhotoLabel(
              meal: newest.photoMeal,
              text: Meals.chatTextForDisplay(newest.text ?? ''),
            ),
            ...gridRows,
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 6, 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: _MessageTime(message: timeOf),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    MessageData message,
    double width,
    double height,
  ) {
    final String? thumbUrl = message.thumbUrl;
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () => onImageTap(message),
        onLongPress:
            _isDesktopPlatform ? null : () => _openActionsSheet(context, message),
        onSecondaryTapDown: _isDesktopPlatform
            ? (details) => _openMenuAt(context, message, details.globalPosition)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MealThumbnailImage(
                url: thumbUrl ?? message.imageUrl ?? '',
                isOriginal: thumbUrl == null,
              ),
            ),
            if (message.reactions.isNotEmpty)
              Positioned(
                left: 4,
                bottom: 0,
                child: ReactionBadge(reactions: message.reactions),
              ),
          ],
        ),
      ),
    );
  }

  /// Dokunmatikte uzun basınca: fotoğrafın ifade ve işlem menüsü.
  Future<void> _openActionsSheet(
    BuildContext context,
    MessageData message,
  ) async {
    final MessageActionChoice? choice = await showMessageActionsSheet(
      context,
      canReact: canReactTo(message),
      actions: actionsFor(message),
      currentEmoji: message.reactions[myUid],
    );
    if (choice == null) return;

    final String? emoji = choice.emoji;
    final MessageAction? action = choice.action;
    if (emoji != null) {
      onToggleReaction(message, emoji);
    } else if (action != null) {
      onAction(message, action);
    }
  }

  /// Masaüstünde sağ tıklayınca: "Yanıtla", karşı tarafın fotoğrafıysa
  /// "İfade Bırak" ve fotoğrafın diğer işlemleri.
  Future<void> _openMenuAt(
    BuildContext context,
    MessageData message,
    Offset position,
  ) async {
    final RenderObject? overlay =
        Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;

    final List<MessageAction> actions = actionsFor(message);
    final Object? choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final MessageAction action in actions)
          if (action == MessageAction.reply)
            PopupMenuItem<Object>(value: action, child: Text(action.label)),
        if (canReactTo(message))
          const PopupMenuItem<Object>(
            value: _reactMenuValue,
            child: Text(_reactLabel),
          ),
        for (final MessageAction action in actions)
          if (action != MessageAction.reply)
            PopupMenuItem<Object>(value: action, child: Text(action.label)),
      ],
    );
    if (choice == null || !context.mounted) return;

    if (choice is MessageAction) {
      onAction(message, choice);
      return;
    }
    final String? emoji = await showReactionPicker(
      context,
      globalPosition: position,
      currentEmoji: message.reactions[myUid],
    );
    if (emoji != null) onToggleReaction(message, emoji);
  }
}

/// Tek mesajın baloncuğu: varsa yanıtladığı mesajın alıntısı, öğün
/// fotoğrafında öğün etiketi, fotoğraf (oranında, küçük görselle), metin ve
/// yalnızca saat; hepsi tek baloncukta. Gün, listedeki gün ayırıcısında
/// yazar.
///
/// Dokunmatikte uzun basınca mesaj menüsü (ifadeler + işlemler) açılır;
/// masaüstünde metin seçilebilir ve sağ tık aynı işlemleri sunar.
class _MessageBubble extends StatelessWidget {
  final MessageData message;
  final bool isMe;

  /// UID of the person viewing the chat (used to find their own reaction).
  final String myUid;

  /// Karşı tarafın mesajı mı: ifade bırakılabilir.
  final bool canReact;

  /// Mesaj şu an vurgulu mu (bir mesaja gidildiğinde kısa süre arka planı
  /// yanar).
  final bool highlighted;

  /// Menüde sunulan işlemler (bkz. [MessageAction]).
  final List<MessageAction> actions;

  final _BubbleMetrics metrics;

  /// Yanıtlanan mesajın sahibinin adı; yanıt değilse null.
  final String? replySenderLabel;

  final void Function(MessageData message) onImageTap;

  /// Called with the tapped emoji when the viewer picks a reaction.
  final void Function(MessageData message, String emoji) onToggleReaction;

  final void Function(MessageData message, MessageAction action) onAction;

  /// Alıntıya dokununca yanıtlanan mesaja gidilir.
  final void Function(String messageId) onReplyTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.myUid,
    required this.canReact,
    required this.highlighted,
    required this.actions,
    required this.metrics,
    required this.replySenderLabel,
    required this.onImageTap,
    required this.onToggleReaction,
    required this.onAction,
    required this.onReplyTap,
  });

  /// Kendi mesajlarının baloncuk rengi (bekleyen yüklemeler de bu renkte).
  static const Color myBubbleColor = Color(0xFFBBDEFB);
  static const Color _otherBubbleColor = Color(0xFFE0E0E0);

  /// Fotoğraflı baloncuğun iç boşluğu.
  static const double _photoPadding = 4;

  /// Vurgunun açılıp kapanma süresi.
  static const Duration _highlightFadeDuration = Duration(milliseconds: 300);

  static const String _reactLabel = 'İfade Bırak';

  @override
  Widget build(BuildContext context) {
    final Color bubbleColor = isMe ? myBubbleColor : _otherBubbleColor;
    final CrossAxisAlignment align =
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // Uygulamanın yazdığı öğün açıklamaları eski mesajlarda da güncel adla
    // görünür ("Ara Öğün 2" -> "Ara").
    final String text = Meals.chatTextForDisplay(message.text ?? '');
    final String? imageUrl = message.imageUrl;
    final bool isMealPhoto = imageUrl != null && message.isMealPhoto;
    final MessageReply? reply = message.replyTo;
    final String? replyLabel = replySenderLabel;

    final Widget content = Container(
      constraints: BoxConstraints(
        maxWidth: imageUrl == null
            ? metrics.textMaxWidth
            : metrics.imageWidth + _photoPadding * 2,
      ),
      padding: imageUrl == null
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.all(_photoPadding),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      // Metin baloncuğunun genişliği içeriğe göre (kısa mesajın baloncuğu
      // kısa kalır, saat sağ alta oturur); fotoğraflı baloncuk fotoğrafın
      // genişliğindedir, ek ölçüm gerekmez.
      child: _shrinkToContent(
        imageUrl == null,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null && replyLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: MessageReplyQuote(
                  senderLabel: replyLabel,
                  text: reply.text,
                  imageUrl: reply.imageUrl,
                  onTap: () => onReplyTap(reply.messageId),
                ),
              ),
            if (isMealPhoto) _MealPhotoLabel(meal: message.photoMeal, text: text),
            if (imageUrl != null) _buildPhoto(imageUrl),
            if (message.photoDeleted)
              _DeletedPhotoNote(text: text)
            else if (text.isNotEmpty && !isMealPhoto)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  imageUrl == null ? 0 : 6,
                  imageUrl == null ? 0 : 6,
                  imageUrl == null ? 0 : 6,
                  0,
                ),
                child: Text(text, style: const TextStyle(fontSize: 15)),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                4,
                imageUrl == null ? 0 : 6,
                imageUrl == null ? 0 : 2,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: _MessageTime(message: message),
              ),
            ),
          ],
        ),
      ),
    );

    final Widget body = _isDesktopPlatform
        // Masaüstünde metin fareyle seçilebilir; sağ tık menüsü kopyalamayı
        // ve mesaj işlemlerini sunar.
        ? SelectionArea(
            contextMenuBuilder: (menuContext, region) =>
                _buildDesktopMenu(context, region),
            child: content,
          )
        // Uzun basınca mesaj menüsü. HitTestBehavior.deferToChild keeps taps
        // on the image working (opens the full-screen viewer).
        : GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onLongPress: () => _openActionsSheet(context),
            child: content,
          );

    return AnimatedContainer(
      duration: _highlightFadeDuration,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          // Reactions left on this message (shown to everyone in the chat).
          if (message.reactions.isNotEmpty)
            ReactionBadge(reactions: message.reactions),
        ],
      ),
    );
  }

  /// Fotoğraf: küçük görseli indirilir (liste kartlarının optimize
  /// görseliyle, [MealThumbnailImage]); küçük görseli olmayan eski mesajda
  /// orijinal küçültülerek çözülür. Orijinal yalnızca tam ekranda iner.
  static Widget _shrinkToContent(bool shrink, Widget child) =>
      shrink ? IntrinsicWidth(child: child) : child;

  Widget _buildPhoto(String imageUrl) {
    final Size size = metrics.photoSize(message.imageAspectRatio);
    final String? thumbUrl = message.thumbUrl;
    return GestureDetector(
      onTap: () => onImageTap(message),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MealThumbnailImage(
            url: thumbUrl ?? imageUrl,
            isOriginal: thumbUrl == null,
          ),
        ),
      ),
    );
  }

  /// Dokunmatikte uzun basınca açılan menü: ifade ya da işlem seçilir.
  Future<void> _openActionsSheet(BuildContext context) async {
    final MessageActionChoice? choice = await showMessageActionsSheet(
      context,
      canReact: canReact,
      actions: actions,
      currentEmoji: message.reactions[myUid],
    );
    if (choice == null) return;

    final String? emoji = choice.emoji;
    final MessageAction? action = choice.action;
    if (emoji != null) {
      onToggleReaction(message, emoji);
    } else if (action != null) {
      onAction(message, action);
    }
  }

  /// Masaüstü sağ tık menüsü: seçili metin varsa "Kopyala", ardından
  /// "Yanıtla", karşı tarafın mesajıysa "İfade Bırak" ve mesajın diğer
  /// işlemleri. Menü kapanır, sonra işlem yapılır.
  Widget _buildDesktopMenu(
    BuildContext context,
    SelectableRegionState region,
  ) {
    final Offset anchor = region.contextMenuAnchors.primaryAnchor;

    VoidCallback closeThen(VoidCallback action) => () {
          region.hideToolbar();
          action();
        };
    ContextMenuButtonItem itemFor(MessageAction action) =>
        ContextMenuButtonItem(
          label: action.label,
          onPressed: closeThen(() => onAction(message, action)),
        );

    final List<ContextMenuButtonItem> items = [
      ...region.contextMenuButtonItems
          .where((item) => item.type == ContextMenuButtonType.copy),
      if (actions.contains(MessageAction.reply))
        itemFor(MessageAction.reply),
      if (canReact)
        ContextMenuButtonItem(
          label: _reactLabel,
          onPressed: closeThen(() => _pickReactionAt(context, anchor)),
        ),
      for (final MessageAction action in actions)
        if (action != MessageAction.reply) itemFor(action),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: items,
    );
  }

  /// İfade seçicisini [globalPosition] noktasında açar.
  Future<void> _pickReactionAt(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final String? selected = await showReactionPicker(
      context,
      globalPosition: globalPosition,
      currentEmoji: message.reactions[myUid],
    );
    if (selected != null) {
      onToggleReaction(message, selected);
    }
  }
}

/// Öğün fotoğrafı baloncuğunun başındaki öğün etiketi ("Öğle"), öğünün
/// renk ve ikonuyla.
class _MealPhotoLabel extends StatelessWidget {
  final Meals? meal;

  /// Öğün çözülemezse gösterilen açıklama ("Öğün: Öğle").
  final String text;

  const _MealPhotoLabel({required this.meal, required this.text});

  @override
  Widget build(BuildContext context) {
    final Meals? meal = this.meal;
    final Color color = meal == null ? Colors.black54 : mealTypeColor(meal);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Row(
        children: [
          Icon(
            meal == null ? Icons.restaurant : mealTypeIcon(meal),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              meal?.displayLabel ?? text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baloncuğun sağ altındaki saat ("14:05"). Mesaj henüz sunucuya
/// ulaşmadıysa yanında saat ikonu görünür.
class _MessageTime extends StatelessWidget {
  final MessageData message;

  const _MessageTime({required this.message});

  static const TextStyle _style = TextStyle(fontSize: 11, color: Colors.black54);

  @override
  Widget build(BuildContext context) {
    final DateTime? sentAt = message.sentAt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(sentAt == null ? '' : DateFormatter.formatTime(sentAt),
            style: _style),
        if (message.createdAt == null) ...[
          const SizedBox(width: 3),
          const Icon(Icons.schedule, size: 12, color: Colors.black45),
        ],
      ],
    );
  }
}

/// Fotoğrafı silinmiş öğün mesajının metni: silindiği ikon ve soluk, eğik
/// yazıyla belli olur.
class _DeletedPhotoNote extends StatelessWidget {
  final String text;

  const _DeletedPhotoNote({required this.text});

  static const double _iconSize = 16;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.hide_image_outlined,
          size: _iconSize,
          color: Colors.black45,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }
}

/// En yeni mesaja dönüş düğmesi. Kullanıcı eski mesajlara kaydırınca (ya da
/// sohbet eski bir mesajda açıldıysa) görünür; bu arada gelen okunmamış
/// mesajların sayısı rozette yazar.
class _JumpToLatestButton extends StatelessWidget {
  final ValueListenable<bool> visible;
  final ValueListenable<int> unreadCount;
  final VoidCallback onPressed;

  const _JumpToLatestButton({
    required this.visible,
    required this.unreadCount,
    required this.onPressed,
  });

  static const String _tooltip = 'En yeniye git';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, isVisible, _) {
        if (!isVisible) return const SizedBox.shrink();

        return ValueListenableBuilder<int>(
          valueListenable: unreadCount,
          builder: (context, count, _) => Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: _tooltip,
              onPressed: onPressed,
              child: const Icon(Icons.keyboard_double_arrow_down),
            ),
          ),
        );
      },
    );
  }
}

/// Mesaj yazma satırı: ek menüsü ("Öğün Yükle"), mesaj kutusu ve gönder
/// düğmesi; yanıt yazılırken üstünde alıntı çubuğu.
class _ChatInputRow extends StatefulWidget {
  /// Sohbet sayfasının mesaj kutusu (bkz. [_ChatPageState._messageController]).
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  /// Öğün fotoğrafı yükleme. Admin öğün yüklemediği için onda null; ek
  /// menüsü ("+") de gösterilmez.
  final VoidCallback? onMealUpload;

  /// Yanıtlanan mesaj; null değilse kutunun üstünde alıntısı görünür.
  final ValueNotifier<MessageData?> replyTarget;

  /// Alıntıdaki mesaj sahibinin adı.
  final String Function(MessageData message) replyLabelOf;

  const _ChatInputRow({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onMealUpload,
    required this.replyTarget,
    required this.replyLabelOf,
  });

  @override
  State<_ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<_ChatInputRow> with SingleTickerProviderStateMixin {
  static const String _hintText = 'Mesaj yazın…';
  static const String _sendTooltip = 'Gönder';
  static const String _attachTooltip = 'Ekler';
  static const String _mealUploadLabel = 'Öğün Yükle';

  bool _isMenuOpen = false;
  late final AnimationController _animationController;
  late final Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Masaüstünde Enter mesajı gönderir, Shift+Enter yeni satır ekler; Esc
  /// yazılan yanıtı iptal eder. Dokunmatik klavyede Enter her zamanki gibi
  /// yeni satırdır.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_isDesktopPlatform || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        widget.replyTarget.value != null) {
      widget.replyTarget.value = null;
      return KeyEventResult.handled;
    }
    final bool isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // Harf birleştirme (IME) sürerken Enter onu tamamlar, göndermez.
    if (widget.controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }

    widget.onSend();
    return KeyEventResult.handled;
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _closeMenuAndRun(VoidCallback action) {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
        _animationController.reverse();
      });
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final VoidCallback? onMealUpload = widget.onMealUpload;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Expandable attachment menu
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _isMenuOpen && onMealUpload != null
                  ? Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _AttachmentOption(
                            icon: Icons.restaurant_rounded,
                            label: _mealUploadLabel,
                            color: Colors.orange,
                            onTap: () => _closeMenuAndRun(onMealUpload),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Yanıt yazılırken yanıtlanan mesajın alıntısı.
            ValueListenableBuilder<MessageData?>(
              valueListenable: widget.replyTarget,
              builder: (context, target, _) {
                if (target == null) return const SizedBox.shrink();
                final MessageReply reply = MessageReply.of(target);
                return MessageReplyComposerBar(
                  senderLabel: widget.replyLabelOf(target),
                  text: reply.text,
                  imageUrl: reply.imageUrl,
                  onCancel: () => widget.replyTarget.value = null,
                );
              },
            ),

            // Input row
            Row(
              children: [
                // Plus button to toggle menu (yalnızca danışanda).
                if (onMealUpload != null) ...[
                  RotationTransition(
                    turns: _rotationAnimation,
                    child: IconButton(
                      icon: Icon(
                        Icons.add_circle_rounded,
                        color: _isMenuOpen ? colorScheme.primary : null,
                        size: 28,
                      ),
                      onPressed: _toggleMenu,
                      tooltip: _attachTooltip,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // Text input field
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _hintText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Gönder: kutu boşken pasif görünür.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final bool canSend = value.text.trim().isNotEmpty;
                    return IconButton(
                      tooltip: _sendTooltip,
                      icon: Icon(
                        Icons.send_rounded,
                        color: canSend ? colorScheme.primary : null,
                      ),
                      onPressed: canSend ? widget.onSend : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual attachment option button for the expandable menu
class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
