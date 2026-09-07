// lib/pages/admin_mock_meal_photos_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/diet_model.dart';
import '../models/diet_section.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';
import '../providers/chat_manager_new.dart';
import '../providers/diet_provider.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/storage_upload.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/status_note.dart';

final Logger logger = Logger.forClass(AdminMockMealPhotosPage);

/// TEST ARACI: seçilen danışanlar adına sahte öğün fotoğrafı yükler.
///
/// Amaç, "Öğün Fotoğrafları" sayfasını gerçek danışan beklemeden
/// deneyebilmek. Akış, danışanın kendi yüklemesiyle **birebir aynı** yoldan
/// geçer ([MealManager.uploadMealImg]), yani veri gerçek yüklemeyle aynı
/// şekilde `users/{uid}/meals/{gün}/mealEntries` altına yazılır.
///
/// Kurallar:
/// - Yalnızca aktif paketi olan danışanlar listelenir (Öğün Fotoğrafları
///   sayfasıyla aynı koşul).
/// - Her danışan için **kendi diyetinde tanımlı** öğünler kullanılır; diyeti
///   olmayan danışan atlanır ve sonuç listesinde belirtilir.
/// - Her öğün için [_photosPerMeal] fotoğraf yüklenir; saatler öğünün
///   varsayılan saatinden başlar, fotoğraf ve danışan başına kaydırılır ki
///   sayfada farklı saatler görünsün.
class AdminMockMealPhotosPage extends StatefulWidget {
  const AdminMockMealPhotosPage({super.key});

  @override
  State<AdminMockMealPhotosPage> createState() =>
      _AdminMockMealPhotosPageState();
}

class _AdminMockMealPhotosPageState extends State<AdminMockMealPhotosPage> {
  static const String _pageTitle = 'Test Öğün Fotoğrafı Yükle';
  static const String _refreshLabel = 'Yenile';
  static const String _searchHint = 'Danışan ara (ad soyad / e-posta / uid)';
  static const String _loadingText = 'Danışanlar yükleniyor...';
  static const String _loadErrorText =
      'Danışanlar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _noCustomerText =
      'Aktif paketi olan danışan bulunamadı.';
  static const String _noSearchResultText =
      'Aramanıza uyan danışan bulunamadı.';
  static const String _pickPhotoLabel = 'Mock Fotoğraf Seç';
  static const String _uploadLabel = 'Fotoğrafları Yükle';

  /// Her öğün için yüklenecek fotoğraf sayısı. [MealModel.maxImages] üstüne
  /// çıkılamaz: fazlası yüklenmez.
  static const int _photosPerMeal = 2;

  /// Aynı öğünün fotoğrafları arasındaki dakika farkı.
  static const int _minutesBetweenPhotos = 5;

  /// Danışanlar arasındaki dakika kayması: iki danışanın saatleri birebir aynı
  /// görünmesin diye sıradaki her danışan bu kadar dakika ötelenir.
  static const int _minutesBetweenClients = 3;

  /// Danışan kaymasının tekrara düşmeden gidebileceği en büyük değer.
  static const int _clientShiftLimit = 5;

  static const double _panelMinWidth = 300.0;
  static const double _panelMaxWidth = 420.0;
  static const double _panelWidthRatio = 0.34;
  static const double _previewSize = 132.0;

  final ScrollController _listScrollController = ScrollController();
  final ScrollController _panelScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// Yükleme sırasında ilerlemeyi canlı gösteren dialog mesajı.
  final ValueNotifier<String> _progressMessage = ValueNotifier<String>('');

  bool _isLoading = true;
  bool _isRunning = false;
  String? _errorText;

  /// Aktif paketi olan danışanlar, ada göre sıralı.
  List<_MockClient> _clients = const [];

  final Set<String> _selectedUserIds = <String>{};

  String _searchQuery = '';

  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoMimeType;

  bool _clearBeforeUpload = true;
  bool _alsoPostToChat = false;

  /// Son çalıştırmanın danışan bazlı sonucu.
  List<_MockResult> _results = const [];

  static DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    logger.info('AdminMockMealPhotosPage initialized');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadClients();
    });
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _panelScrollController.dispose();
    _searchController.dispose();
    _progressMessage.dispose();
    super.dispose();
  }

  /// Aktif paketi olan danışanları çeker (Öğün Fotoğrafları sayfasıyla aynı
  /// koşul), paket id'siyle birlikte: yükleme sırasında öğün kaydına o paketin
  /// id'si yazılır.
  Future<void> _loadClients() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final subProvider = Provider.of<SubProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final List<UserModel> customers = await userProvider.fetchAllCustomers();
      final Map<String, SubscriptionModel> activeSubs =
          await subProvider.fetchActiveSubscriptionsOfUsers(
        customers.map((user) => user.userId).toList(),
      );

      final List<_MockClient> clients = [];
      for (final UserModel customer in customers) {
        final SubscriptionModel? sub = activeSubs[customer.userId];
        if (sub == null) continue;
        clients.add(_MockClient(user: customer, subscription: sub));
      }
      clients.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _selectedUserIds
            .removeWhere((id) => !clients.any((c) => c.user.userId == id));
        _isLoading = false;
      });
      logger.info('Mock page loaded {} active customer(s)', [clients.length]);
    } catch (e) {
      logger.err('Error loading clients for mock page: {}', [e]);
      if (!mounted) return;
      setState(() {
        _errorText = _loadErrorText;
        _isLoading = false;
      });
    }
  }

  List<_MockClient> get _visibleClients {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _clients;
    return _clients.where((client) => client.matchesQuery(query)).toList();
  }

  bool get _canRun =>
      !_isRunning && _photoBytes != null && _selectedUserIds.isNotEmpty;

  /// Mock fotoğrafı seçtirir. Dosya belleğe alınır (`withData`) ki her yükleme
  /// için aynı baytlar farklı adlarla tekrar tekrar kullanılabilsin.
  Future<void> _pickPhoto() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.single;
      if (file.bytes == null) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Seçilen dosya okunamadı.',
        );
        return;
      }
      if (file.size > kMaxUploadBytes) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Dosya Çok Büyük',
          message: 'Fotoğraf en fazla $kMaxUploadSizeLabel olabilir.',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _photoBytes = file.bytes;
        _photoName = file.name;
        _photoMimeType = _mimeTypeOf(file.extension);
      });
      logger.info('Mock photo selected: {} ({} bytes)', [file.name, file.size]);
    } catch (e) {
      logger.err('Error picking mock photo: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Fotoğraf seçilemedi: $e',
      );
    }
  }

  static String _mimeTypeOf(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Danışanın diyetinde tanımlı öğünler. Bugün hafta sonuysa ve diyette ayrı
  /// bir hafta sonu menüsü varsa o menü kullanılır. Sıra [Meals.dietValues]
  /// sırasıdır, yani gün içindeki doğal öğün sırası.
  List<Meals> _mealsOfDiet(DietDocument diet, DateTime day) {
    final Map<String, dynamic> section =
        (isWeekendDate(day) && diet.hasWeekend)
            ? diet.weekendSubtitles!
            : diet.subtitles;

    return Meals.dietValues
        .where((meal) => section.containsKey(meal.name))
        .toList();
  }

  /// Öğünün varsayılan saatinden (ör. Sabah 09:00) türetilen yükleme zamanı.
  /// Fotoğraf ve danışan sırasına göre kaydırılır ki sayfada hep farklı
  /// saatler görünsün.
  DateTime _uploadTimeFor(
    DateTime day,
    Meals meal,
    int photoIndex,
    int clientIndex,
  ) {
    final List<String> parts = meal.defaultTime.split(':');
    final int hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 12) : 12;
    final int minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final int shift = photoIndex * _minutesBetweenPhotos +
        (clientIndex % _clientShiftLimit) * _minutesBetweenClients;

    return DateTime(day.year, day.month, day.day, hour, minute)
        .add(Duration(minutes: shift));
  }

  /// Seçili danışanlar için sahte fotoğrafları yükler.
  ///
  /// Bir danışanda çıkan hata diğerlerini durdurmaz; her danışanın sonucu
  /// sayfanın altındaki listede raporlanır.
  Future<void> _runMockUpload() async {
    final Uint8List? bytes = _photoBytes;
    if (bytes == null || _selectedUserIds.isEmpty) return;

    final List<_MockClient> selected = _clients
        .where((client) => _selectedUserIds.contains(client.user.userId))
        .toList();
    final DateTime day = _todayStart();

    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Verisi Yüklensin mi?',
      message: '${selected.length} danışan seçildi.\n\n'
          'Her danışanın diyetinde tanımlı her öğün için $_photosPerMeal '
          'fotoğraf ${DateFormat('d MMMM y', 'tr_TR').format(day)} tarihine '
          'yüklenecek.\n'
          '${_clearBeforeUpload ? '\nUYARI: Bu danışanların bugüne ait mevcut öğün fotoğrafları önce SİLİNECEK.' : ''}'
          '${_alsoPostToChat ? '\nFotoğraflar sohbete de gönderilecek.' : ''}',
      confirmText: 'Yükle',
      cancelText: 'Vazgeç',
    );
    if (!confirmed || !mounted) return;

    // Context'e bağlı nesneler await'lerden önce alınır.
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final mealManager = Provider.of<MealManager>(context, listen: false);
    final dietProvider = Provider.of<DietProvider>(context, listen: false);
    // Sohbete gönderilmeyecekse ChatManager'a hiç bakılmaz.
    final ChatManager? chatManager =
        _alsoPostToChat ? Provider.of<ChatManager>(context, listen: false) : null;

    setState(() {
      _isRunning = true;
      _results = const [];
    });

    // Yükleme dialogu await edilmez; kullanıcı geri tuşuyla kapatırsa
    // whenComplete bayrağı düşürür, böylece aşağıdaki pop yanlışlıkla sayfayı
    // kapatmaz.
    bool loadingOpen = true;
    _progressMessage.value = 'Hazırlanıyor...';
    DialogUtils.openLoadingProgress(context,
            messageListenable: _progressMessage)
        .whenComplete(() => loadingOpen = false);

    final List<_MockResult> results = [];

    try {
      for (int clientIndex = 0; clientIndex < selected.length; clientIndex++) {
        final _MockClient client = selected[clientIndex];
        final String progressPrefix =
            '${client.displayName} (${clientIndex + 1}/${selected.length})';
        _progressMessage.value = '$progressPrefix - diyet okunuyor...';

        try {
          final DietDocument? diet =
              await dietProvider.fetchLatestDietDocument(client.user.userId);
          if (diet == null) {
            results.add(_MockResult.skipped(
                client.displayName, 'Diyet bulunamadı, atlandı.'));
            continue;
          }

          final List<Meals> meals = _mealsOfDiet(diet, day);
          if (meals.isEmpty) {
            results.add(_MockResult.skipped(client.displayName,
                'Diyetinde tanımlı öğün yok, atlandı.'));
            continue;
          }

          if (_clearBeforeUpload) {
            _progressMessage.value = '$progressPrefix - eski fotoğraflar '
                'siliniyor...';
            await mealManager.deleteMealsForDate(
              userId: client.user.userId,
              date: day,
            );
          }

          int uploaded = 0;
          for (final Meals meal in meals) {
            for (int photoIndex = 0;
                photoIndex < _photosPerMeal;
                photoIndex++) {
              _progressMessage.value =
                  '$progressPrefix - ${meal.label} (${photoIndex + 1}/'
                  '$_photosPerMeal)';

              final String fileName =
                  'mock_${meal.name}_$photoIndex${_extensionOfSelectedPhoto()}';
              final String? url = await mealManager.uploadMealImg(
                userId: client.user.userId,
                meal: meal,
                image: XFile.fromData(
                  bytes,
                  path: fileName,
                  name: fileName,
                  mimeType: _photoMimeType,
                ),
                subscriptionId: client.subscription.subscriptionId,
                overrideDate:
                    _uploadTimeFor(day, meal, photoIndex, clientIndex),
                alsoPostToChat: _alsoPostToChat,
                chatManager: chatManager,
              );
              if (url != null) uploaded++;
            }
          }

          results.add(_MockResult.done(
            client.displayName,
            '${meals.length} öğün · $uploaded fotoğraf yüklendi '
            '(${meals.map((meal) => meal.label).join(', ')})',
          ));
        } catch (e) {
          logger.err('Mock upload failed for user {}: {}',
              [client.user.userId, e]);
          results.add(_MockResult.failed(client.displayName, 'Hata: $e'));
        }
      }

      if (loadingOpen && navigator.mounted) {
        navigator.pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      setState(() => _results = results);

      final int okCount = results.where((result) => result.isDone).length;
      await DialogUtils.openInfo(
        context,
        title: 'Test Verisi Yüklendi',
        message: '$okCount/${selected.length} danışan için fotoğraf '
            'yüklendi. Ayrıntılar sayfanın sağ alt bölümünde.',
      );
    } catch (e) {
      logger.err('Mock upload run failed: {}', [e]);
      if (loadingOpen && navigator.mounted) {
        navigator.pop();
        loadingOpen = false;
      }
      if (!mounted) return;
      setState(() => _results = results);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Test verisi yüklenemedi: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  String _extensionOfSelectedPhoto() {
    final String name = _photoName ?? '';
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '.jpg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWithBack(
        title: _pageTitle,
        actions: [
          LabeledActionButton(
            icon: Icons.refresh,
            label: _refreshLabel,
            onPressed: _isLoading || _isRunning ? null : _loadClients,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const StatusNote(text: _loadingText, showProgress: true);
    }

    if (_errorText != null) {
      return StatusNote(
        icon: Icons.error_outline,
        text: _errorText!,
        isError: true,
        action: LabeledActionButton(
          icon: Icons.refresh,
          label: _refreshLabel,
          onPressed: _loadClients,
        ),
      );
    }

    if (_clients.isEmpty) {
      return const StatusNote(
        icon: Icons.people_outline,
        text: _noCustomerText,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double panelWidth = (constraints.maxWidth * _panelWidthRatio)
            .clamp(_panelMinWidth, _panelMaxWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildClientPanel(context)),
            const VerticalDivider(width: 1),
            SizedBox(width: panelWidth, child: _buildSettingsPanel(context)),
          ],
        );
      },
    );
  }

  /// Sol panel: danışan arama + çoklu seçim listesi.
  Widget _buildClientPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_MockClient> visible = _visibleClients;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Aramayı temizle',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Görünenleri Seç'),
                onPressed: _isRunning
                    ? null
                    : () => setState(() => _selectedUserIds.addAll(
                        visible.map((client) => client.user.userId))),
              ),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Seçimi Temizle'),
                onPressed: _isRunning || _selectedUserIds.isEmpty
                    ? null
                    : () => setState(_selectedUserIds.clear),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visible.length} aktif danışan · ${_selectedUserIds.length} seçili',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? const StatusNote(
                  icon: Icons.search_off,
                  text: _noSearchResultText,
                )
              : Scrollbar(
                  controller: _listScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final _MockClient client = visible[index];
                      final bool selected =
                          _selectedUserIds.contains(client.user.userId);

                      return CheckboxListTile(
                        value: selected,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _isRunning
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selectedUserIds.add(client.user.userId);
                                  } else {
                                    _selectedUserIds.remove(client.user.userId);
                                  }
                                }),
                        title: Text(
                          client.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${client.user.email}\n${client.user.userId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        isThreeLine: true,
                        secondary: Tooltip(
                          message: client.subscription.status.displayName,
                          child: Icon(
                            Icons.card_membership,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Sağ panel: mock fotoğraf seçimi, ayarlar, çalıştırma ve sonuçlar.
  Widget _buildSettingsPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scrollbar(
      controller: _panelScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _panelScrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelCard(
              title: 'Mock Fotoğraf',
              icon: Icons.image_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: _previewSize,
                      height: _previewSize,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _photoBytes == null
                          ? Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : Image.memory(
                              _photoBytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                Icons.broken_image_outlined,
                                size: 40,
                                color: theme.colorScheme.error,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _photoName ?? 'Henüz fotoğraf seçilmedi.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  LabeledActionButton(
                    icon: Icons.folder_open,
                    label: _pickPhotoLabel,
                    onPressed: _isRunning ? null : _pickPhoto,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PanelCard(
              title: 'Ayarlar',
              icon: Icons.tune,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Seçilen her danışanın kendi diyetinde tanımlı her öğün '
                    'için $_photosPerMeal fotoğraf yüklenir. Saatler öğünün '
                    'varsayılan saatinden başlar (Sabah ${Meals.br.defaultTime}, '
                    'Öğle ${Meals.lunch.defaultTime}, Akşam '
                    '${Meals.dinner.defaultTime}); fotoğraflar '
                    '$_minutesBetweenPhotos dk, danışanlar '
                    '$_minutesBetweenClients dk arayla kaydırılır.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _clearBeforeUpload,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Önce bugünkü fotoğrafları sil'),
                    subtitle: const Text(
                      'Bir öğüne en fazla 3 fotoğraf yüklenebildiği için '
                      'tekrar denemelerde gerekir.',
                    ),
                    onChanged: _isRunning
                        ? null
                        : (value) =>
                            setState(() => _clearBeforeUpload = value ?? false),
                  ),
                  CheckboxListTile(
                    value: _alsoPostToChat,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Sohbete de gönder'),
                    subtitle: const Text(
                      'Danışan fotoğrafı sohbetten yüklemiş gibi davranır.',
                    ),
                    onChanged: _isRunning
                        ? null
                        : (value) =>
                            setState(() => _alsoPostToChat = value ?? false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LabeledActionButton(
              icon: Icons.cloud_upload,
              label: _uploadLabel,
              onPressed: _canRun ? _runMockUpload : null,
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              _PanelCard(
                title: 'Sonuçlar',
                icon: Icons.fact_check_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final _MockResult result in _results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(result.icon, size: 16, color: result.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result.clientName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    result.message,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Listede gösterilen danışan: kullanıcı kaydı + aktif paketi.
class _MockClient {
  final UserModel user;
  final SubscriptionModel subscription;

  const _MockClient({required this.user, required this.subscription});

  String get displayName => user.fullName.isEmpty ? user.email : user.fullName;

  /// Zaten küçük harfe çevrilmiş [query] ada, e-postaya veya uid'ye uyuyor mu.
  bool matchesQuery(String query) =>
      user.fullName.toLowerCase().contains(query) ||
      user.email.toLowerCase().contains(query) ||
      user.userId.toLowerCase().contains(query);
}

/// Bir danışan için çalıştırma sonucu.
class _MockResult {
  final String clientName;
  final String message;
  final _MockOutcome outcome;

  const _MockResult._(this.clientName, this.message, this.outcome);

  factory _MockResult.done(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.done);

  factory _MockResult.skipped(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.skipped);

  factory _MockResult.failed(String clientName, String message) =>
      _MockResult._(clientName, message, _MockOutcome.failed);

  bool get isDone => outcome == _MockOutcome.done;

  IconData get icon {
    switch (outcome) {
      case _MockOutcome.done:
        return Icons.check_circle;
      case _MockOutcome.skipped:
        return Icons.info_outline;
      case _MockOutcome.failed:
        return Icons.error_outline;
    }
  }

  Color get color {
    switch (outcome) {
      case _MockOutcome.done:
        return Colors.green.shade700;
      case _MockOutcome.skipped:
        return Colors.orange.shade800;
      case _MockOutcome.failed:
        return Colors.red.shade700;
    }
  }
}

enum _MockOutcome { done, skipped, failed }

/// Sağ paneldeki başlıklı kart.
class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PanelCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
