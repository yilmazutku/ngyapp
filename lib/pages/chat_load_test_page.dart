import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_load_test_run.dart';
import '../providers/chat_load_test_provider.dart';
import '../providers/user_provider.dart';
import '../services/frame_stats_monitor.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../utils/storage_upload.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/frame_stats_badge.dart';
import '../widgets/inline_note.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/status_note.dart';
import 'admin_chat_page.dart';

class ChatLoadTestPage extends StatefulWidget {
  const ChatLoadTestPage({super.key});

  static const String title = 'Sohbet Yük Testi';

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<ChatLoadTestProvider>(
          create: (_) => ChatLoadTestProvider(),
          child: const ChatLoadTestPage(),
        ),
      );

  @override
  State<ChatLoadTestPage> createState() => _ChatLoadTestPageState();
}

String _formatTime(DateTime? time) =>
    time == null ? '-' : DateFormat('HH:mm:ss', 'tr_TR').format(time);

String _formatDuration(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes % 60;
  final int seconds = duration.inSeconds % 60;
  if (hours > 0) return '$hours sa $minutes dk';
  if (minutes > 0) return '$minutes dk $seconds sn';
  return '$seconds sn';
}

String _formatSeconds(double value) {
  final String text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$text sn';
}

class _ChatLoadTestPageState extends State<ChatLoadTestPage> {
  static const String _stepsText =
      '1. Gönderilecek fotoğrafları seçin ve ayarları girin.\n'
      '2. İsterseniz kare süresi göstergesini açın.\n'
      '3. "Testi Başlat"a basın: test kullanıcıları sunucuda oluşturulur, '
      'mesajlar sunucudan, ayrı cihazlardan geliyormuş gibi gönderilir.\n'
      '4. "Sohbetler\'i Aç" ile listeye geçin; bu sayfadan çıkmak testi '
      'durdurmaz. Listeyi kaydırın, sohbet açın, göstergeyi izleyin.\n'
      '5. Bitince bu sayfaya dönüp "Temizle"ye basın.';
  static const String _customerNote =
      'Test kullanıcıları danışan olarak oluşturulur (soyadları "Test 01", '
      '"Test 02"...); temizlenene kadar danışan listelerinde de görünürler. '
      'Her test mesajı gerçek bir mesaj gibi bildirim de gönderir: Nilay\'ın '
      'oturum açık olduğu bütün cihazlarına mesaj başına bir bildirim gider.';
  static const String _officeOnlyNote =
      'Sohbetler listesi yalnızca sohbet ofisinin (Nilay) hesabında görünür. '
      'Mesajları izlemek için o hesapla girilmiş bir cihaz kullanın.';
  static const String _cleanupNote =
      'Temizlik, test kullanıcılarını uygulamadaki "kullanıcıyı sil" işleviyle '
      'siler: hesabı, kayıtları, Storage\'daki öğün fotoğrafları ve sohbeti '
      'gider. Sohbetleri Sohbetler sayfasından elle silmek isterseniz '
      'temizlikten önce silin. Seçtiğiniz test fotoğrafları ve test kayıtları '
      'da silinir; gerçek danışanlara dokunulmaz.';
  static const String _photosEmptyText =
      'Henüz fotoğraf seçilmedi. Her test kullanıcısı bu fotoğrafları sırayla '
      'öğün fotoğrafı olarak gönderir.';
  static const String _frameMeterText =
      'Açıkken ekranın sol altında, uygulamanın her sayfasında kare süreleri '
      'görünür. Takılan: süresi kare bütçesini aşan kare (60 Hz\'de 16,7 ms); '
      'ağır: bütçenin 4 katını aşan, gözle görülen takılma. Göstergeye '
      'dokununca sayaçlar sıfırlanır.';
  static const String _numbersError = 'Sayıları kontrol edin.';
  static const String _noRunsText = 'Henüz yük testi çalıştırılmadı.';
  static const String _runsErrorText = 'Testler yüklenemedi.';
  static const String _pickPhotosLabel = 'Fotoğraf Seç';
  static const String _startLabel = 'Testi Başlat';
  static const String _openChatsLabel = 'Sohbetler\'i Aç';
  static const String _cleanupAllLabel = 'Tümünü Temizle';
  static const String _resetLabel = 'Sıfırla';
  static const String _cancelLabel = 'Vazgeç';
  static const String _errorTitle = 'Hata';

  static const int _defaultUsers = 30;
  static const int _defaultPhotosPerUser = 3;
  static const String _defaultGap = '2';
  static const int _defaultStartDelay = 15;
  static const double _maxContentWidth = 760;
  static const double _photoPreviewSize = 88;
  static const double _fieldMinWidth = 220;
  static const double _fieldSpacing = 12;
  static const Duration _clockInterval = Duration(seconds: 15);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _usersController =
      TextEditingController(text: '$_defaultUsers');
  final TextEditingController _photosPerUserController =
      TextEditingController(text: '$_defaultPhotosPerUser');
  final TextEditingController _gapController =
      TextEditingController(text: _defaultGap);
  final TextEditingController _startDelayController =
      TextEditingController(text: '$_defaultStartDelay');
  final ValueNotifier<String> _progress = ValueNotifier<String>('');

  late final Stream<List<ChatLoadTestRun>> _runsStream;
  late final bool _isChatOffice;
  late final Listenable _configFields;
  Timer? _clock;

  List<ChatLoadTestPhoto> _photos = const [];
  ChatLoadTestOrder _order = ChatLoadTestOrder.roundRobin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final ChatLoadTestProvider provider =
        Provider.of<ChatLoadTestProvider>(context, listen: false);
    _runsStream = provider.runsStream();
    _isChatOffice = provider.isChatOffice;
    _configFields = Listenable.merge([
      _usersController,
      _photosPerUserController,
      _gapController,
      _startDelayController,
    ]);
    _clock = Timer.periodic(_clockInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scrollController.dispose();
    _usersController.dispose();
    _photosPerUserController.dispose();
    _gapController.dispose();
    _startDelayController.dispose();
    _progress.dispose();
    super.dispose();
  }

  ChatLoadTestConfig? _readConfig() {
    final int? users = int.tryParse(_usersController.text.trim());
    final int? perUser = int.tryParse(_photosPerUserController.text.trim());
    final double? gap =
        double.tryParse(_gapController.text.trim().replaceAll(',', '.'));
    final int? delay = int.tryParse(_startDelayController.text.trim());
    if (users == null || perUser == null || gap == null || delay == null) {
      return null;
    }
    return ChatLoadTestConfig(
      userCount: users,
      photosPerUser: perUser,
      gapSeconds: gap,
      startDelaySeconds: delay,
      order: _order,
    );
  }

  String? _configError(ChatLoadTestConfig? config) =>
      config == null ? _numbersError : config.validate(_photos.length);

  void _setProgress(String message) {
    if (mounted) _progress.value = message;
  }

  Future<void> _pickPhotos() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final List<ChatLoadTestPhoto> picked = [];
      int unreadable = 0;
      for (final PlatformFile file in result.files) {
        final Uint8List? bytes = file.bytes;
        if (bytes == null || bytes.isEmpty || file.size > kMaxUploadBytes) {
          unreadable++;
          continue;
        }
        picked.add(ChatLoadTestPhoto(bytes: bytes, name: file.name));
      }
      final List<ChatLoadTestPhoto> all = [..._photos, ...picked];
      final int dropped = all.length > ChatLoadTestLimits.maxSourcePhotos
          ? all.length - ChatLoadTestLimits.maxSourcePhotos
          : 0;
      setState(() => _photos =
          all.take(ChatLoadTestLimits.maxSourcePhotos).toList());

      if (unreadable == 0 && dropped == 0) return;
      await DialogUtils.openInfo(
        context,
        title: 'Bazı Fotoğraflar Eklenmedi',
        message: [
          if (unreadable > 0)
            '$unreadable dosya okunamadı ya da $kMaxUploadSizeLabel '
                'sınırını aşıyor.',
          if (dropped > 0)
            'En fazla ${ChatLoadTestLimits.maxSourcePhotos} fotoğraf '
                'seçilebilir; $dropped fotoğraf eklenmedi.',
        ].join('\n'),
      );
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message:
            'Fotoğraf seçilemedi: ${ChatLoadTestProvider.errorMessage(e)}',
      );
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos = [..._photos]..removeAt(index));
  }

  Future<void> _start() async {
    final ChatLoadTestConfig? config = _readConfig();
    final String? error = _configError(config);
    if (config == null || error != null) {
      await DialogUtils.openError(
        context,
        title: 'Ayarlar Eksik',
        message: error ?? _numbersError,
      );
      return;
    }

    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Başlatılsın mı?',
      message: '${config.userCount} test kullanıcısı oluşturulacak ve her biri '
          '${config.photosPerUser} öğün fotoğrafı gönderecek '
          '(toplam ${config.totalMessages} mesaj, '
          '${_formatSeconds(config.gapSeconds)} arayla, '
          '${config.order.label.toLowerCase()}).\n\n'
          'İlk mesaj ${config.startDelaySeconds} sn sonra gelir; gönderim '
          'yaklaşık ${_formatDuration(config.sendDuration)} sürer.\n\n'
          'Nilay\'ın cihazlarına toplam ${config.totalMessages} bildirim gider.',
      confirmText: 'Başlat',
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;

    final ChatLoadTestProvider provider =
        Provider.of<ChatLoadTestProvider>(context, listen: false);
    final UserProvider userProvider =
        Provider.of<UserProvider>(context, listen: false);

    setState(() => _busy = true);
    _progress.value = 'Hazırlanıyor...';
    LoadingDialog? loading;
    if (mounted) {
      loading = DialogUtils.openLoadingProgress(
        context,
        messageListenable: _progress,
      );
    }

    try {
      final ChatLoadTestStartResult result = await provider.startRun(
        config: config,
        photos: _photos,
        onProgress: _setProgress,
      );
      userProvider.invalidateCustomers();
      loading?.close();
      if (!mounted) return;
      await _showStarted(result);
    } catch (e) {
      loading?.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Test Başlatılamadı',
        message: ChatLoadTestProvider.errorMessage(e),
      );
    } finally {
      loading?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showStarted(ChatLoadTestStartResult result) async {
    final DateTime? startAt = result.startAt;
    final int remaining =
        startAt == null ? 0 : startAt.difference(DateTime.now()).inSeconds;
    final String message =
        '${result.userCount} test kullanıcısı oluşturuldu; '
        '${result.totalSteps} mesaj sunucudan gönderilecek. İlk mesaj '
        '${remaining > 0 ? 'yaklaşık $remaining sn sonra' : 'hemen'} '
        'gelir.\n\nBu sayfadan çıkabilirsiniz; test sunucuda sürer. Durdurmak '
        've temizlemek için bu sayfaya dönün.';

    if (!_isChatOffice) {
      await DialogUtils.openInfo(
        context,
        title: 'Test Başladı',
        message: '$message\n\n$_officeOnlyNote',
      );
      return;
    }

    final bool open = await DialogUtils.openConfirm(
      context,
      title: 'Test Başladı',
      message: message,
      confirmText: _openChatsLabel,
      cancelText: 'Burada Kal',
    );
    if (open && mounted) _openChats();
  }

  void _openChats() {
    Navigator.of(context).push(AdminChatListPage.route());
  }

  Future<void> _stopRun(ChatLoadTestRun run) async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Durdurulsun mu?',
      message: 'Kalan mesajlar gönderilmez. Gönderilen mesajlar ve test '
          'kullanıcıları siz temizleyene kadar kalır.',
      confirmText: 'Durdur',
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;
    final ChatLoadTestProvider provider =
        Provider.of<ChatLoadTestProvider>(context, listen: false);

    setState(() => _busy = true);
    LoadingDialog? loading;
    if (mounted) {
      loading = DialogUtils.openLoading(context, message: 'Test durduruluyor...');
    }
    try {
      final bool stopped = await provider.stopRun(run.id);
      loading?.close();
      if (!stopped && mounted) {
        await DialogUtils.openInfo(
          context,
          title: 'Bilgi',
          message: 'Test zaten bitmiş ya da durdurulmuş.',
        );
      }
    } catch (e) {
      loading?.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message: 'Test durdurulamadı: ${ChatLoadTestProvider.errorMessage(e)}',
      );
    } finally {
      loading?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeRun(ChatLoadTestRun run) async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Sürdürülsün mü?',
      message: 'Sunucudaki gönderim zinciri yeniden başlatılır. Zamanı geçmiş '
          've gönderilmemiş mesajlar hemen, kalanlar zamanında gönderilir; '
          'gönderilmiş mesajlar yinelenmez.',
      confirmText: 'Sürdür',
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;
    final ChatLoadTestProvider provider =
        Provider.of<ChatLoadTestProvider>(context, listen: false);

    setState(() => _busy = true);
    LoadingDialog? loading;
    if (mounted) {
      loading =
          DialogUtils.openLoading(context, message: 'Test sürdürülüyor...');
    }
    try {
      await provider.resumeRun(run.id);
      loading?.close();
    } catch (e) {
      loading?.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message: 'Test sürdürülemedi: ${ChatLoadTestProvider.errorMessage(e)}',
      );
    } finally {
      loading?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cleanup({ChatLoadTestRun? run}) async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: run == null ? 'Bütün Test Verisi Silinsin mi?' : 'Test Silinsin mi?',
      message: '${run == null ? 'Süren testler durdurulur. ' : ''}'
          '$_cleanupNote',
      confirmText: 'Sil',
      cancelText: _cancelLabel,
    );
    if (!confirmed || !mounted) return;
    final ChatLoadTestProvider provider =
        Provider.of<ChatLoadTestProvider>(context, listen: false);
    final UserProvider userProvider =
        Provider.of<UserProvider>(context, listen: false);

    setState(() => _busy = true);
    _progress.value = 'Hazırlanıyor...';
    LoadingDialog? loading;
    if (mounted) {
      loading = DialogUtils.openLoadingProgress(
        context,
        messageListenable: _progress,
      );
    }
    try {
      final ChatLoadTestCleanupResult result = await provider.cleanup(
        runId: run?.id,
        deleteUser: (userId) => userProvider.deleteUserAccount(userId: userId),
        onProgress: _setProgress,
      );
      loading?.close();
      if (!mounted) return;
      if (result.isComplete) {
        await DialogUtils.openInfo(
          context,
          title: 'Temizlendi',
          message: '${result.deletedUsers} test kullanıcısı silindi; '
              '${result.deletedRuns} testin fotoğrafları ve kayıtları '
              'silindi.',
        );
      } else {
        await DialogUtils.openError(
          context,
          title: 'Kısmen Temizlendi',
          message: result.failedUsers > 0
              ? '${result.deletedUsers} test kullanıcısı silindi, '
                  '${result.failedUsers} kullanıcı silinemedi. Test kayıtları '
                  'kalanları bulabilmek için silinmedi; tekrar "Temizle"ye '
                  'basın.'
              : '${result.deletedUsers} test kullanıcısı silindi ama test '
                  'fotoğrafları ve kayıtları silinemedi: ${result.error} '
                  'Tekrar "Temizle"ye basın.',
        );
      }
    } catch (e) {
      loading?.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message:
            'Test verisi silinemedi: ${ChatLoadTestProvider.errorMessage(e)}',
      );
    } finally {
      loading?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setFrameMeter(bool visible) {
    if (!visible) {
      FrameStatsOverlay.hide();
      return;
    }
    final OverlayState? overlay =
        Navigator.of(context, rootNavigator: true).overlay;
    if (overlay != null) FrameStatsOverlay.show(overlay);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(
        title: ChatLoadTestPage.title,
        showHomeButton: true,
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildIntro(context),
                  const SizedBox(height: 16),
                  _buildPhotosCard(context),
                  const SizedBox(height: 16),
                  _buildSettingsCard(context),
                  const SizedBox(height: 16),
                  _buildFrameMeterCard(context),
                  const SizedBox(height: 16),
                  _buildRunsCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNote(
          icon: Icons.info_outline,
          text: _stepsText,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 8),
        InlineNote(
          icon: Icons.warning_amber_rounded,
          text: _isChatOffice
              ? _customerNote
              : '$_customerNote\n\n$_officeOnlyNote',
          color: Colors.orange.shade800,
        ),
      ],
    );
  }

  Widget _buildPhotosCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canAdd =
        !_busy && _photos.length < ChatLoadTestLimits.maxSourcePhotos;
    return _SectionCard(
      title: 'Fotoğraflar (${_photos.length}/'
          '${ChatLoadTestLimits.maxSourcePhotos})',
      icon: Icons.photo_library_outlined,
      trailing: LabeledActionButton(
        icon: Icons.add_photo_alternate_outlined,
        label: _pickPhotosLabel,
        dense: true,
        onPressed: canAdd ? _pickPhotos : null,
      ),
      child: _photos.isEmpty
          ? Text(
              _photosEmptyText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _photos.length; i++)
                  _PhotoPreview(
                    bytes: _photos[i].bytes,
                    size: _photoPreviewSize,
                    onRemove: _busy ? null : () => _removePhoto(i),
                  ),
              ],
            ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _SectionCard(
      title: 'Ayarlar',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final bool twoColumns =
                  constraints.maxWidth >= _fieldMinWidth * 2 + _fieldSpacing;
              final double width = twoColumns
                  ? (constraints.maxWidth - _fieldSpacing) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: _fieldSpacing,
                runSpacing: _fieldSpacing,
                children: [
                  _NumberField(
                    width: width,
                    controller: _usersController,
                    label: 'Test kullanıcısı sayısı',
                    helper: '1-${ChatLoadTestLimits.maxUsers}',
                    enabled: !_busy,
                  ),
                  _NumberField(
                    width: width,
                    controller: _photosPerUserController,
                    label: 'Kişi başı fotoğraf',
                    helper: '1-${ChatLoadTestLimits.maxPhotosPerUser}; '
                        'seçilen fotoğraflar sırayla kullanılır',
                    enabled: !_busy,
                  ),
                  _NumberField(
                    width: width,
                    controller: _gapController,
                    label: 'Mesajlar arası süre (sn)',
                    helper: '0 = hepsi aynı anda; 0,5 gibi kesirli olabilir',
                    decimal: true,
                    enabled: !_busy,
                  ),
                  _NumberField(
                    width: width,
                    controller: _startDelayController,
                    label: 'İlk mesajdan önce bekleme (sn)',
                    helper: 'Sohbetler\'i açmaya vakit kalsın',
                    enabled: !_busy,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Gönderim sırası', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<ChatLoadTestOrder>(
            segments: [
              for (final ChatLoadTestOrder order in ChatLoadTestOrder.values)
                ButtonSegment<ChatLoadTestOrder>(
                  value: order,
                  label: Text(order.label),
                ),
            ],
            selected: {_order},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _order = selection.first),
          ),
          const SizedBox(height: 4),
          Text(
            _order.description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 24),
          ListenableBuilder(
            listenable: _configFields,
            builder: (context, _) => _buildSummary(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatLoadTestConfig? config = _readConfig();
    final String? error = _configError(config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (config != null && error == null)
          Text(
            'Toplam ${config.totalMessages} mesaj · gönderim yaklaşık '
            '${_formatDuration(config.sendDuration)} sürer · ilk mesaj '
            'başlatıldıktan ${config.startDelaySeconds} sn sonra',
            style: theme.textTheme.bodyMedium,
          )
        else
          Text(
            error ?? _numbersError,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
        const SizedBox(height: 12),
        LabeledActionButton(
          icon: Icons.play_arrow_rounded,
          label: _startLabel,
          onPressed: _busy || error != null ? null : _start,
        ),
      ],
    );
  }

  Widget _buildFrameMeterCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FrameStatsMonitor monitor = FrameStatsMonitor.instance;
    return _SectionCard(
      title: 'Kare Süresi Göstergesi',
      icon: Icons.speed,
      child: ValueListenableBuilder<FrameStats?>(
        valueListenable: monitor.stats,
        builder: (context, stats, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: stats != null,
              title: const Text('Göstergeyi göster'),
              onChanged: _setFrameMeter,
            ),
            Text(
              _frameMeterText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (stats != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: LabeledActionButton(
                  icon: Icons.restart_alt,
                  label: _resetLabel,
                  dense: true,
                  onPressed: monitor.reset,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRunsCard(BuildContext context) {
    return _SectionCard(
      title: 'Testler',
      icon: Icons.history,
      trailing: LabeledActionButton(
        icon: Icons.delete_sweep_outlined,
        label: _cleanupAllLabel,
        dense: true,
        foregroundColor: Colors.red.shade700,
        onPressed: _busy ? null : () => _cleanup(),
      ),
      child: StreamBuilder<List<ChatLoadTestRun>>(
        stream: _runsStream,
        builder: (context, snapshot) {
          final List<ChatLoadTestRun>? runs = snapshot.data;
          if (runs == null) {
            return snapshot.hasError
                ? const StatusNote(
                    icon: Icons.error_outline,
                    text: _runsErrorText,
                    isError: true,
                  )
                : const StatusNote(showProgress: true, text: 'Yükleniyor...');
          }
          if (runs.isEmpty) {
            return const StatusNote(
              icon: Icons.inbox_outlined,
              text: _noRunsText,
            );
          }
          final DateTime now = DateTime.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < runs.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _RunTile(
                  run: runs[i],
                  now: now,
                  busy: _busy,
                  canOpenChats: _isChatOffice,
                  onOpenChats: _openChats,
                  onStop: () => _stopRun(runs[i]),
                  onResume: () => _resumeRun(runs[i]),
                  onCleanup: () => _cleanup(run: runs[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget? action = trailing;
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
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (action != null) action,
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

class _NumberField extends StatelessWidget {
  final double width;
  final TextEditingController controller;
  final String label;
  final String helper;
  final bool decimal;
  final bool enabled;

  const _NumberField({
    required this.width,
    required this.controller,
    required this.label,
    required this.helper,
    required this.enabled,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final Uint8List bytes;
  final double size;
  final VoidCallback? onRemove;

  const _PhotoPreview({
    required this.bytes,
    required this.size,
    required this.onRemove,
  });

  static const double _decodeScale = 2;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int decodeWidth =
        (size * MediaQuery.devicePixelRatioOf(context) * _decodeScale).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final ChatLoadTestRun run;
  final DateTime now;
  final bool busy;
  final bool canOpenChats;
  final VoidCallback onOpenChats;
  final VoidCallback onStop;
  final VoidCallback onResume;
  final VoidCallback onCleanup;

  const _RunTile({
    required this.run,
    required this.now,
    required this.busy,
    required this.canOpenChats,
    required this.onOpenChats,
    required this.onStop,
    required this.onResume,
    required this.onCleanup,
  });

  static const String _openChatsLabel = 'Sohbetler\'i Aç';

  Color _statusColor(ColorScheme colors) {
    switch (run.status) {
      case ChatLoadTestStatus.completed:
        return Colors.green.shade700;
      case ChatLoadTestStatus.failed:
        return colors.error;
      case ChatLoadTestStatus.cancelled:
      case ChatLoadTestStatus.unknown:
        return Colors.blueGrey.shade600;
      case ChatLoadTestStatus.preparing:
      case ChatLoadTestStatus.creatingUsers:
      case ChatLoadTestStatus.running:
        return colors.primary;
    }
  }

  String _timeline() {
    final DateTime? startAt = run.startAt;
    if (startAt == null) return 'Oluşturulma: ${_formatTime(run.createdAt)}';
    final String start = startAt.isAfter(now)
        ? 'İlk mesaj ${_formatTime(startAt)} '
            '(${_formatDuration(startAt.difference(now))} sonra)'
        : 'Başlangıç ${_formatTime(startAt)}';
    final DateTime? finishedAt = run.finishedAt;
    if (finishedAt != null) return '$start · bitiş ${_formatTime(finishedAt)}';
    if (!run.status.isActive) return start;
    return '$start · tahmini bitiş ${_formatTime(run.estimatedEndAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _statusColor(theme.colorScheme);
    final bool active = run.status.isActive;
    final bool stalled = run.isStalled(now);
    final String? lastError = run.lastError;
    final DateTime? createdAt = run.createdAt;
    final TextStyle? muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                run.status.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                createdAt == null
                    ? run.id
                    : DateFormatter.formatNumericDateTime(createdAt),
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${run.displayUserCount} kişi × ${run.photosPerUser} fotoğraf = '
          '${run.totalSteps} mesaj · ${_formatSeconds(run.gapSeconds)} arayla '
          '· ${run.order.label}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: run.progress,
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gönderilen ${run.sentCount}/${run.totalSteps}'
          '${run.failedCount > 0 ? ' · başarısız ${run.failedCount}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        Text(_timeline(), style: muted),
        if (lastError != null) ...[
          const SizedBox(height: 4),
          Text(
            lastError,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (stalled) ...[
          const SizedBox(height: 8),
          InlineNote(
            icon: Icons.hourglass_disabled,
            text: 'Test ${ChatLoadTestLimits.stalledAfter.inMinutes} '
                'dakikadır ilerlemiyor; sunucudaki gönderim zinciri durmuş '
                'olabilir. "Sürdür" kalan mesajları gönderir.',
            color: Colors.orange.shade800,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (active && canOpenChats)
              LabeledActionButton(
                icon: Icons.forum_outlined,
                label: _openChatsLabel,
                dense: true,
                onPressed: onOpenChats,
              ),
            if (stalled)
              LabeledActionButton(
                icon: Icons.play_circle_outline,
                label: 'Sürdür',
                dense: true,
                onPressed: busy ? null : onResume,
              ),
            if (active)
              LabeledActionButton(
                icon: Icons.stop_circle_outlined,
                label: 'Durdur',
                dense: true,
                foregroundColor: Colors.orange.shade800,
                onPressed: busy ? null : onStop,
              )
            else
              LabeledActionButton(
                icon: Icons.delete_outline,
                label: 'Temizle',
                dense: true,
                foregroundColor: Colors.red.shade700,
                onPressed: busy ? null : onCleanup,
              ),
          ],
        ),
      ],
    );
  }
}
