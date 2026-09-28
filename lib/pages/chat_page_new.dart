// lib/pages/chat_page_new.dart
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/diet_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/models/diet_model.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/meal_state_and_upload_manager.dart';
import 'package:ngy_app/widgets/chat_image_preview.dart';
import 'package:ngy_app/widgets/reaction_badge.dart';
import 'package:ngy_app/widgets/reaction_picker.dart';
import 'package:ngy_app/pages/user_media_gallery_page.dart';
import 'package:ngy_app/utils/dialog_utils.dart';
import 'package:ngy_app/utils/diet_menu_parser.dart';
import 'package:ngy_app/services/fcm_service.dart';
import 'package:ngy_app/services/meal_reminder_service.dart';

import '../constants/app_constants.dart';
import '../widgets/labeled_action_button.dart';

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

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const String _mealUploadingText = 'Öğün fotoğrafı yükleniyor...';
  static const String _imageUploadingText = 'Görsel yükleniyor...';
  static const String _uploadErrorTitle = 'Hata';
  static const String _mealUploadErrorText =
      'Öğün fotoğrafı yüklenemedi. Lütfen tekrar deneyin.';
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

  /// Odaklı açılışta hedeften eski, bağlam için bir kez okunan mesajlar.
  List<MessageData> _focusOlderMessages = const [];

  /// Mesaj yazma kutusu. Sayfaya aittir: bir sohbette yazılıp gönderilmeyen
  /// metin başka bir sohbetin kutusuna taşınmaz.
  final TextEditingController _messageController = TextEditingController();

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
    
    // Resolve chat ID once and cache it
    _chatId = widget.overrideChatId ?? _currentUid;
    
    // Determine if current user is an admin
    _isAdminUser = ChatManager.isAdminUid(_currentUid);

    _focusActive = widget.focusMessageId != null;

    if (_showsUserTitle && widget.userDisplayName == null) {
      _userFuture = Provider.of<UserProvider>(context, listen: false)
          .fetchUserDetails(userId: _chatId);
    }

    // Suppress in-app notifications for this chat while it is on top.
    FcmService().openChat(_chatId);

    if (_focusActive) {
      // Ekran eski bir mesajda açılıyor: okundu işareti en yeniye inilince.
      _markReadPending = true;
      _loadUnreadCount();
      _openFocusWindow();
    } else {
      _messagesStream = context.read<ChatManager>().messagesStreamFor(_chatId);
      _markChatAsRead();
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
    _scrollController.dispose();
    _focusHighlighted.dispose();
    _showJumpToLatest.dispose();
    _unreadCount.dispose();
    super.dispose();
  }

  /// Admin başka bir danışanın sohbetine bakıyorsa başlıkta danışanın adı
  /// görünür.
  bool get _showsUserTitle => widget.overrideChatId != null && _isAdminUser;

  /// Mark chat as read (resets unread count) based on user type.
  Future<void> _markChatAsRead() async {
    try {
      final chatManager = context.read<ChatManager>();
      if (_isAdminUser) {
        await chatManager.markChatAsRead(_chatId);
      } else {
        await chatManager.markChatAsReadForUser(_chatId);
      }
    } catch (e) {
    }
  }

  /// "En yeniye git" düğmesindeki okunmamış sayısını okur.
  Future<void> _loadUnreadCount() async {
    final ChatManager chatManager = context.read<ChatManager>();
    try {
      final int count = await chatManager.currentUserUnreadCount(_chatId);
      // Bu arada en yeniye inilip okundu işaretlendiyse sayı artık geçersiz.
      if (!mounted || !_markReadPending) return;
      _unreadCount.value = count;
    } catch (e) {
      // Sayı yalnızca bilgi amaçlı: okunamazsa düğme sayısız görünür.
    }
  }

  /// Admin-only: confirm and permanently delete this chat.
  ///
  /// Deletes all messages and every photo uploaded in the chat, then returns
  /// to the previous screen (the admin chat list).
  Future<void> _confirmAndDeleteChat() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Sohbeti Sil',
      message: 'Bu sohbet ve tüm mesajları kalıcı olarak silinecek. Sohbette '
          'gönderilen fotoğraflar da silinir; öğün fotoğrafları danışanın öğün '
          'kayıtlarında kalır. Bu işlem geri alınamaz.\n\n'
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
      FcmService().setInForeground(false);
    } else if (state == AppLifecycleState.resumed) {
      FcmService().setInForeground(true);
      // Re-mark as read when returning to foreground (unless the newest
      // messages have not been reached yet in a focused chat).
      if (!_markReadPending) {
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

  /// Pick an image from the gallery, then upload it.
  ///
  /// Currently only called from [_startMealUploadFlow], so [meal] is
  /// always non-null in practice. Kept nullable for future flexibility
  /// (e.g. re-adding a standalone gallery option to the attachment menu).
  Future<void> _pickAndSendImage({Meals? meal}) async {
    final hasPermission = await _checkPhotoPermission();
    if (!hasPermission) {
      return;
    }

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return;
    }

    await _uploadPickedImage(
      image,
      meal: meal,
      chatImageErrorText: 'Görsel gönderilemedi. Lütfen tekrar deneyin.',
    );
  }

  /// Capture an image from the camera, then upload it.
  ///
  /// Currently only called from [_startMealUploadFlow], so [meal] is
  /// always non-null in practice. Kept nullable for future flexibility
  /// (e.g. re-adding a standalone camera option to the attachment menu).
  Future<void> _captureAndSendImage({Meals? meal}) async {
    final hasPermission = await _checkCameraPermission();
    if (!hasPermission) {
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) {
      return;
    }

    await _uploadPickedImage(
      image,
      meal: meal,
      chatImageErrorText:
          'Kamera görüntüsü gönderilemedi. Lütfen tekrar deneyin.',
    );
  }

  /// Seçilen görseli yükler: [meal] verilirse öğüne kaydedip sohbete de
  /// gönderir, verilmezse doğrudan sohbete gönderir.
  ///
  /// Öğün fotoğrafı öğüne kaydedilip sohbete gönderilemezse kullanıcıya
  /// fotoğrafın kaydedildiği söylenir; tekrar yükleyip öğünü kopyayla
  /// doldurmasın.
  Future<void> _uploadPickedImage(
    XFile image, {
    Meals? meal,
    required String chatImageErrorText,
  }) async {
    // Re-checked after the await: the widget may be gone by now.
    if (!mounted) return;
    final chat = context.read<ChatManager>();
    final mealManager = Provider.of<MealManager>(context, listen: false);

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(
        context,
        message: meal != null ? _mealUploadingText : _imageUploadingText,
      );
      loadingOpen = true;
    }

    try {
      bool limitReached = false;
      if (meal != null) {
        final downloadUrl = await mealManager.uploadMealImg(
          meal: meal,
          image: image,
          userId: _currentUid,
          subscriptionId: _currentUid,
          alsoPostToChat: true,
          chatManager: chat,
        );
        // Öğün kaydı sınıra ulaşmışsa (ör. başka cihazdan yüklendi) null döner.
        limitReached = downloadUrl == null;
        if (!limitReached) _cancelMealReminder(meal);
      } else {
        await chat.sendImageTo(_chatId, image);
      }

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (limitReached && mounted) {
        await _showMealImageLimitDialog();
      } else if (mounted) {
        _showLatest();
      }
    } on MealChatPostException {
      // Fotoğraf öğüne kaydedildi, yalnızca sohbete düşmedi: öğün yüklenmiş
      // sayılır.
      if (meal != null) _cancelMealReminder(meal);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: _chatPostFailedTitle,
        message: _chatPostFailedText,
      );
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _uploadErrorTitle,
        message: meal != null ? _mealUploadErrorText : chatImageErrorText,
      );
    }
  }

  /// Start the meal upload flow.
  ///
  /// 1. User selects meal type
  /// 2. The meal's photo limit is checked (before any photo is picked)
  /// 3. User selects image source (gallery or camera)
  /// 4. Delegates to [_pickAndSendImage] or [_captureAndSendImage]
  Future<void> _startMealUploadFlow() async {
    final Meals? meal = await _chooseMeal();
    if (meal == null) {
      return;
    }

    if (!await _mealHasRoomForImage(meal)) {
      return;
    }

    final ImageSource? src = await _chooseSource();
    if (src == null) {
      return;
    }

    if (src == ImageSource.gallery) {
      await _pickAndSendImage(meal: meal);
    } else {
      await _captureAndSendImage(meal: meal);
    }
  }

  /// Öğünün bugünkü fotoğraf sınırı ([MealModel.maxImages]) dolmuşsa uyarı
  /// gösterip false döner; kullanıcı fotoğraf seçip yüklemeyi beklemeden
  /// öğrenir. Kontrol okunamazsa yüklemeye izin verilir: sınırı
  /// [MealManager.uploadMealImg] yükleme sırasında yine uygular.
  Future<bool> _mealHasRoomForImage(Meals meal) async {
    if (!mounted) return false;
    final mealManager = Provider.of<MealManager>(context, listen: false);

    final bool canAdd;
    try {
      canAdd = await mealManager.canAddMealImage(
        userId: _currentUid,
        meal: meal,
      );
    } catch (e) {
      return true;
    }
    if (canAdd) return true;

    if (!mounted) return false;
    await _showMealImageLimitDialog();
    return false;
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
  /// 
  /// Returns the selected ImageSource, or null if cancelled.
  Future<ImageSource?> _chooseSource() async {
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
    final ChatManager chat = context.read<ChatManager>();

    final FocusWindow window;
    try {
      window = await chat.openFocusWindow(_chatId, widget.focusMessageId!);
    } catch (e) {
      if (!mounted || !_focusActive) return;
      _showFocusUnavailable(_focusErrorText);
      return;
    }
    // Bu arada odaktan çıkıldıysa (ör. mesaj gönderildi) pencereye gerek yok.
    if (!mounted || !_focusActive) return;

    final Stream<List<MessageData>>? messages = window.messages;
    if (messages == null) {
      _showFocusUnavailable(window.failure == FocusWindowFailure.tooOld
          ? _focusTooOldText
          : _focusNotFoundText);
      return;
    }

    setState(() {
      _messagesStream = messages;
      _focusOlderMessages = window.olderMessages;
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

  /// Odaklı düzenden çıkar: liste son mesajlarla, en yeni mesajdan başlar.
  void _leaveFocus() {
    _showJumpToLatest.value = false;
    setState(() {
      _focusActive = false;
      _focusOlderMessages = const [];
      _messagesStream = context.read<ChatManager>().messagesStreamFor(_chatId);
    });
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
    if (atLatest && _markReadPending) {
      _markReadPending = false;
      _unreadCount.value = 0;
      _markChatAsRead();
    }
    _showJumpToLatest.value = focusLayout && !atLatest;
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

  /// "En yeniye git": odaklı düzenden çıkıp en yeni mesaja iner; liste
  /// normal düzende en yeniden başlar, okundu işareti de orada konur.
  void _jumpToLatest() => _leaveFocus();

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

  /// Liste her yenilendiğinde yeni gelen mesajlara bakar. Yalnızca odaklı
  /// düzende gerekir: orada yeni mesajlar görünür alanın altına eklenir.
  /// Kullanıcı en yeni mesajdaysa liste yeni mesajı gösterecek kadar kayar;
  /// değilse karşı taraftan gelenler "En yeniye git" rozetindeki sayıya
  /// eklenir. (Normal düzende en yeni mesaj zaten alta eklenir.)
  void _noteNewMessages(List<MessageData> items, {required bool focusLayout}) {
    final String? previous = _newestMessageId;
    _newestMessageId = items.isEmpty ? null : items.first.id;
    if (!focusLayout || previous == null) return;

    final int previousIndex =
        items.indexWhere((message) => message.id == previous);
    if (previousIndex <= 0) return;

    final int incoming = items
        .take(previousIndex)
        .where((message) => message.senderId != _currentUid)
        .length;
    final bool follow = _atLatest;

    // Liste bu karede yerleşince uygulanır: yeni mesajın yeri ancak o zaman
    // bellidir; bildirim de çizim sırasında değil sonrasında yapılmalı.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (follow) {
        _scrollToLatest();
      } else if (incoming > 0) {
        _unreadCount.value += incoming;
      }
    });
  }

  /// Yazılan metni gönderir. Kutu hemen boşalır ve mesaj yerelde hemen
  /// listeye düşer (bkz. [ChatManager.sendTextTo]); ekranda görünsün diye en
  /// yeni mesaja inilir. Sunucu reddederse metin kutuya geri konur.
  Future<void> _sendText() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;

    final ChatManager chat = context.read<ChatManager>();
    _messageController.clear();

    final Future<void> sending = chat.sendTextTo(_chatId, text);
    _showLatest();

    try {
      await sending;
    } catch (e) {
      if (!mounted) return;
      // Bu arada yeni bir şey yazılmadıysa gönderilemeyen metin geri gelir.
      if (_messageController.text.isEmpty) _messageController.text = text;
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

  /// Öğünün fotoğrafı yüklendi: o öğünün bugünkü "yüklediniz mi?"
  /// hatırlatması iptal edilir ("Planım"daki yüklemeyle aynı davranış).
  void _cancelMealReminder(Meals meal) {
    MealReminderService().cancelMealReminder(meal);
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
    } catch (e) {
      if (!mounted) return;
      DialogUtils.openError(
        context,
        title: 'İfade Bırakılamadı',
        message: 'İfade kaydedilemedi. Lütfen tekrar deneyin.',
      );
    }
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
          // Admins can permanently delete the chat (and its uploaded photos)
          if (_isAdminUser)
            LabeledActionButton(
              icon: Icons.delete_outline,
              label: 'Sohbeti Sil',
              onPressed: _confirmAndDeleteChat,
            ),
        ],
      ),
      body: Column(
        children: [
          // Upload progress indicator - only rebuilds when upload state changes
          Selector<ChatManager, ({bool isUploading, double? progress})>(
            selector: (_, chat) => (isUploading: chat.isUploading, progress: chat.uploadProgress),
            builder: (context, state, _) {
              if (!state.isUploading) return const SizedBox.shrink();
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(value: state.progress),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        context.read<ChatManager>().cancelUpload();
                      },
                      child: const Text('İptal'),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Messages list - uses cached stream, doesn't rebuild on ChatManager changes
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                StreamBuilder<List<MessageData>>(
                  stream: _messagesStream,
                  builder: (context, snap) {
                    // Akış değişince (ör. odaktan çıkınca) eldeki liste yenisi
                    // gelene kadar ekranda kalır; yalnızca hiç veri yokken
                    // yükleniyor gösterilir.
                    final List<MessageData>? data = snap.data;
                    if (data == null) {
                      if (snap.hasError) {
                        return const Center(
                          child: Text(_messagesLoadErrorText),
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<MessageData> items = _focusActive
                        ? [...data, ..._focusOlderMessages]
                        : data;

                    if (items.isEmpty) {
                      return const Center(child: Text('Henüz mesaj yok.'));
                    }

                    return _buildMessageList(items);
                  },
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

          // Input row - only rebuilds when the upload state changes
          _ChatInputRow(
            controller: _messageController,
            onSend: _sendText,
            onMealUpload: _startMealUploadFlow,
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
  Widget _buildMessageList(List<MessageData> items) {
    final String? focusMessageId = _focusActive ? widget.focusMessageId : null;
    final int targetIndex = focusMessageId == null
        ? -1
        : items.indexWhere((message) => message.id == focusMessageId);
    _noteNewMessages(items, focusLayout: targetIndex >= 0);

    if (targetIndex < 0) {
      return _trackLatest(
        ListView.builder(
          controller: _scrollController,
          reverse: true, // Newest messages at bottom
          itemCount: items.length,
          itemBuilder: (context, i) => _buildMessageBubble(items[i]),
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
          // Hedeften yeni mesajlar: sıfır noktasının altında, yeniye doğru.
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildMessageBubble(items[targetIndex - 1 - i]),
              childCount: targetIndex,
            ),
          ),
          // Hedef ve ondan eski mesajlar: sıfır noktasından yukarı doğru.
          SliverList(
            key: _focusCenterKey,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildMessageBubble(items[targetIndex + i]),
              childCount: items.length - targetIndex,
            ),
          ),
        ],
      ),
      focusLayout: true,
    );
  }

  /// Tek bir mesaj baloncuğu; listenin iki biçimi de bunu kullanır.
  Widget _buildMessageBubble(MessageData msg) {
    // Both sides can react (WhatsApp-style) to messages the *other* party
    // sent. `_chatId` equals the chat owner's (user's) UID, so
    // `senderId == _chatId` means the message came from the user; an admin UID
    // means it came from the office. Reacting to your own message stays
    // disabled on both sides.
    final bool canReact = !msg.photoDeleted &&
        (_isAdminUser
            ? msg.senderId == _chatId
            : ChatManager.isAdminUid(msg.senderId));

    // Danışan sohbetten yüklediği öğün fotoğrafını uzun basarak silebilir.
    final bool canDeletePhoto =
        !_isAdminUser && msg.senderId == _currentUid && msg.isMealPhoto;

    Widget bubble({required bool highlighted}) => _MessageBubble(
          message: msg,
          highlighted: highlighted,
          isMe: msg.senderId == _currentUid,
          myUid: _currentUid,
          canReact: canReact,
          onImageTap: (url) => _showImageDialog(context, url),
          onToggleReaction: _handleToggleReaction,
          onDeletePhoto: canDeletePhoto ? _confirmAndDeleteMealPhoto : null,
        );

    if (!_focusActive || msg.id != widget.focusMessageId) {
      return bubble(highlighted: false);
    }

    // Anahtar yalnızca hedef mesajda: ortalama bu anahtarla yapılır. Vurgu
    // yalnızca bu baloncuğu yeniden çizer.
    return ValueListenableBuilder<bool>(
      key: _focusMessageKey,
      valueListenable: _focusHighlighted,
      builder: (context, highlighted, _) => bubble(highlighted: highlighted),
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

  /// Open the gallery listing every photo uploaded by [userId].
  void _openUserMediaGallery(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserMediaGalleryPage(userId: userId),
      ),
    );
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

  /// Show a full-screen image dialog with zoom support.
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text('Görsel yüklenemedi', style: TextStyle(color: Colors.red)),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted message bubble widget - prevents parent rebuilds
class _MessageBubble extends StatelessWidget {
  final MessageData message;
  final bool isMe;

  /// UID of the person viewing the chat (used to find their own reaction).
  final String myUid;

  /// Whether a long-press on this bubble should open the reaction picker.
  final bool canReact;

  /// Mesaj şu an vurgulu mu ("Sohbette göster" ile bu mesaja gelindiğinde kısa süre
  /// arka planı yanar).
  final bool highlighted;

  final void Function(String url) onImageTap;

  /// Called with the tapped emoji when the viewer picks a reaction.
  final void Function(MessageData message, String emoji) onToggleReaction;

  /// Verilirse uzun basma bu mesajın öğün fotoğrafını silme akışını açar
  /// (danışanın kendi öğün fotoğrafları).
  final void Function(MessageData message)? onDeletePhoto;

  static const _months = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.myUid,
    required this.canReact,
    required this.highlighted,
    required this.onImageTap,
    required this.onToggleReaction,
    this.onDeletePhoto,
  });

  /// Vurgunun açılıp kapanma süresi.
  static const Duration _highlightFadeDuration = Duration(milliseconds: 300);

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dt.year, dt.month, dt.day);
    
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    
    if (messageDate == today) return time;
    if (messageDate == yesterday) return 'Dün $time';
    
    final day = dt.day;
    final month = _months[dt.month];
    
    if (dt.year != now.year) {
      return '$day $month ${dt.year} $time';
    }
    
    return '$day $month $time';
  }

  @override
  Widget build(BuildContext context) {
    final ts = message.createdAt ?? message.clientCreatedAt;
    final timeStr = ts != null ? _formatTime(ts.toDate()) : 'Gönderiliyor…';
    final bubbleColor = isMe ? Colors.blue.shade100 : Colors.grey.shade300;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // Uygulamanın yazdığı öğün açıklamaları eski mesajlarda da güncel adla
    // görünür ("Ara Öğün 2" -> "Ara").
    final String text = Meals.chatTextForDisplay(message.text ?? '');

    // The message body itself (text bubble and/or image + timestamp).
    final content = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Text message bubble
        if (text.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: align,
              children: [
                if (message.photoDeleted)
                  _DeletedPhotoNote(text: text)
                else
                  Text(text, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),

        // Image preview
        if (message.imageUrl != null)
          ChatImagePreview(
            imageUrl: message.imageUrl,
            onTap: () => onImageTap(message.imageUrl!),
            usePlaceholder: message.createdAt == null,
          ),

        // Timestamp below image
        if (message.imageUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              timeStr,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
      ],
    );

    // Long-press to react (on the other party's messages) or, on the
    // client's own meal photo, to delete it. HitTestBehavior.deferToChild
    // keeps taps on the image working (opens the full-screen viewer) while
    // still recognizing a long-press on the bubble.
    final void Function(MessageData message)? deletePhoto = onDeletePhoto;
    final Widget body;
    if (canReact) {
      body = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (details) =>
            _handleLongPress(context, details.globalPosition),
        child: content,
      );
    } else if (deletePhoto != null) {
      body = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: () => deletePhoto(message),
        child: content,
      );
    } else {
      body = content;
    }

    return AnimatedContainer(
      duration: _highlightFadeDuration,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  /// Open the reaction picker for this message and forward the chosen emoji.
  Future<void> _handleLongPress(BuildContext context, Offset globalPosition) async {
    final current = message.reactions[myUid];
    final selected = await showReactionPicker(
      context,
      globalPosition: globalPosition,
      currentEmoji: current,
    );
    if (selected != null) {
      onToggleReaction(message, selected);
    }
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

/// Odaklı açılan sohbette en yeni mesaja dönüş düğmesi. En yeni mesaj
/// ekranda değilken görünür; açılışta okunmamış mesaj varsa sayısı rozette
/// yazar.
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

/// Extracted input row widget - uses Selector for targeted rebuilds
class _ChatInputRow extends StatefulWidget {
  /// Sohbet sayfasının mesaj kutusu (bkz. [_ChatPageState._messageController]).
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMealUpload;

  const _ChatInputRow({
    required this.controller,
    required this.onSend,
    required this.onMealUpload,
  });

  @override
  State<_ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<_ChatInputRow> with SingleTickerProviderStateMixin {
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
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        // Only rebuild when the upload state changes
        child: Selector<ChatManager, bool>(
          selector: (_, chat) => chat.isUploading,
          builder: (context, isUploading, _) {
            final isDisabled = isUploading;
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Expandable attachment menu
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _isMenuOpen
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
                                label: 'Öğün Yükle',
                                color: Colors.orange,
                                onTap: isDisabled ? null : () => _closeMenuAndRun(widget.onMealUpload),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                
                // Input row
                Row(
                  children: [
                    // Plus button to toggle menu
                    RotationTransition(
                      turns: _rotationAnimation,
                      child: IconButton(
                        icon: Icon(
                          Icons.add_circle_rounded,
                          color: _isMenuOpen ? colorScheme.primary : null,
                          size: 28,
                        ),
                        onPressed: isDisabled ? null : _toggleMenu,
                        tooltip: 'Ekler',
                      ),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // Text input field
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Mesaj yazın…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // Send button
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: colorScheme.primary,
                      ),
                      onPressed: widget.onSend,
                    ),
                  ],
                ),
              ],
            );
          },
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
