import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/appointment_color_palette.dart';
import '../models/logger.dart';
import '../models/special_line_model.dart';
import '../providers/appointment_colors_provider.dart';
import '../providers/special_lines_provider.dart';
import '../utils/dialog_utils.dart';

final Logger _specialLinesLogger = Logger.forClass(_SpecialLinesSection);
final Logger _appointmentColorsLogger =
    Logger.forClass(_AppointmentColorsSection);

class TestingPage extends StatefulWidget {
  const TestingPage({super.key});

  @override
  State<TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends State<TestingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Ayarlar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                _SpecialLinesSection(),
                SizedBox(height: 16),
                _AppointmentColorsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Special-line types management section.
// Lets the admin CRUD the entries stored at `admininput/speciallines` so the
// docx parser and meal renderer can split additional markers (besides the
// built-in "Veya" and "Haftada X") the same way they handle the existing ones.
// ---------------------------------------------------------------------------
class _SpecialLinesSection extends StatefulWidget {
  const _SpecialLinesSection();

  @override
  State<_SpecialLinesSection> createState() => _SpecialLinesSectionState();
}

class _SpecialLinesSectionState extends State<_SpecialLinesSection> {
  bool _loading = true;
  bool _saving = false;
  List<SpecialLineConfig> _customLines = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final provider =
          Provider.of<SpecialLinesProvider>(context, listen: false);
      final lines = await provider.fetchSpecialLines(force: true);
      if (!mounted) return;
      setState(() {
        _customLines = List<SpecialLineConfig>.from(lines);
        _loading = false;
      });
    } catch (e) {
      _specialLinesLogger
          .err('Failed to load admin special lines: {}', [e.toString()]);
      if (!mounted) return;
      setState(() => _loading = false);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Özel satır türleri yüklenirken bir hata oluştu.',
      );
    }
  }

  /// Reads the latest list, applies [mutate] and persists it.
  Future<void> _persist(
    void Function(List<SpecialLineConfig> draft) mutate, {
    required String successMessage,
  }) async {
    setState(() => _saving = true);
    try {
      final draft = List<SpecialLineConfig>.from(_customLines);
      mutate(draft);
      final provider =
          Provider.of<SpecialLinesProvider>(context, listen: false);
      await provider.saveSpecialLines(draft);
      if (!mounted) return;
      setState(() {
        _customLines = draft;
        _saving = false;
      });
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: successMessage,
      );
    } catch (e) {
      _specialLinesLogger
          .err('Failed to save admin special lines: {}', [e.toString()]);
      if (!mounted) return;
      setState(() => _saving = false);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Özel satır türleri kaydedilirken bir hata oluştu.',
      );
    }
  }

  /// Validates [template] against the parser rules AND against the existing
  /// list (built-in + custom) so duplicates / shadowing entries are rejected
  /// up front.
  ///
  /// [editingIndex] is the index of the entry being edited, if any, so its
  /// own previous value does not collide with itself.
  String? _validateTemplate(String template, {int? editingIndex}) {
    final parsed = SpecialLineConfig.tryParseTemplate(template);
    if (parsed == null) {
      return 'Geçersiz şablon. Örn: "Veya", "Haftada X", "Günde X defa".';
    }

    final newKey = parsed.identityKey;

    // Only EXACT template duplicates are rejected. Markers that merely share a
    // leading word (e.g. "Haftada X" and "Haftada X Gün") are allowed — the
    // parser resolves overlaps by preferring the most specific (longest) match.
    final builtIns = [
      SpecialLinesRegistry.veya,
      SpecialLinesRegistry.haftada,
    ];
    for (final cfg in builtIns) {
      if (cfg.identityKey == newKey) {
        return 'Bu şablon sistem tarafından zaten kullanılıyor.';
      }
    }

    for (int i = 0; i < _customLines.length; i++) {
      if (editingIndex != null && i == editingIndex) continue;
      if (_customLines[i].identityKey == newKey) {
        return 'Aynı şablon zaten mevcut.';
      }
    }
    return null;
  }

  Future<void> _showAddDialog() async {
    final template = await _showEditorDialog(initial: '');
    if (template == null) return;
    final parsed = SpecialLineConfig.tryParseTemplate(template);
    if (parsed == null) return;
    await _persist(
      (draft) => draft.add(parsed),
      successMessage: '"${parsed.toTemplate()}" eklendi.',
    );
  }

  Future<void> _showEditDialog(int index) async {
    final current = _customLines[index];
    final template =
        await _showEditorDialog(initial: current.toTemplate(), editingIndex: index);
    if (template == null) return;
    final parsed = SpecialLineConfig.tryParseTemplate(template);
    if (parsed == null || parsed == current) return;
    await _persist(
      (draft) => draft[index] = parsed,
      successMessage: '"${parsed.toTemplate()}" güncellendi.',
    );
  }

  Future<void> _confirmDelete(int index) async {
    final cfg = _customLines[index];
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Özel Satırı Sil',
      message: '"${cfg.toTemplate()}" özel satırını silmek istediğinize emin misiniz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (!confirmed) return;
    await _persist(
      (draft) => draft.removeAt(index),
      successMessage: '"${cfg.toTemplate()}" silindi.',
    );
  }

  /// Shared editor used by both add and edit flows. Returns the entered
  /// template on success, or null when the admin cancels.
  Future<String?> _showEditorDialog({
    required String initial,
    int? editingIndex,
  }) async {
    final controller = TextEditingController(text: initial);
    String? errorText;

    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: Text(
                  editingIndex == null ? 'Özel Satır Ekle' : 'Özel Satır Düzenle',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Text(
                        'Bir kelime ya da kısa ifade girin (örn. "Aperatif").\n'
                        'Eğer satırın yanında bir sayı yer alacaksa, sayının '
                        'yerine büyük "X" harfini kullanın. X başta, ortada ya '
                        'da sonda olabilir:\n'
                        '  • Sonda:   "Haftada X"\n'
                        '  • Ortada:  "Günde X defa"\n'
                        '  • Başta:   "X defa"\n\n'
                        'Birden fazla X kullanabilirsiniz; örn. "Haftada X Gün" '
                        'veya "Haftada X Gün X Defa". İki X yan yana olamaz '
                        '(aralarında en az bir kelime bulunmalıdır).\n'
                        'X tek başına bir kelime gibi yazılmalıdır (boşluklarla '
                        'ayrılmış).\n'
                        'Büyük/küçük harf farketmez: "X" ya da "x", "Haftada" '
                        'ya da "haftada" fark etmeden tanınır.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Şablon',
                        hintText: 'Haftada X',
                        border: const OutlineInputBorder(),
                        errorText: errorText,
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('İptal'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final value = controller.text;
                      final err = _validateTemplate(
                        value,
                        editingIndex: editingIndex,
                      );
                      if (err != null) {
                        setDialogState(() => errorText = err);
                        return;
                      }
                      Navigator.of(dialogContext).pop(value.trim());
                    },
                    child: Text(editingIndex == null ? 'Ekle' : 'Kaydet'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.format_list_bulleted, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Özel Satır Türleri',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Yemek planlarında ayraç olarak görünen "Veya" / "Haftada X" gibi '
              'özel satırların listesini buradan yönetebilirsiniz. Eklenen '
              'şablonlar Word belgesi ayrıştırılırken ve plan kullanıcıya '
              'gösterilirken aynı şekilde tanınır.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sayı içerecek özel satırlarda, sayının olacağı yere '
                      '"X" harfini yazın. X şablonun başında, ortasında '
                      'ya da sonunda olabilir; birden fazla da kullanılabilir.\n'
                      '  • "Haftada X"          → "Haftada 2", "Haftada 5"\n'
                      '  • "Günde X defa"       → "Günde 3 defa"\n'
                      '  • "Haftada X Gün"      → "Haftada 1 Gün"\n'
                      '  • "Haftada X Gün X Defa" → "Haftada 1 Gün 2 Defa"\n'
                      '  • "X defa"             → "5 defa"\n'
                      'Büyük/küçük harf farketmez: "Haftada X Gün", '
                      '"haftada x gün" ve "HAFTADA X GÜN" aynı şekilde '
                      'çalışır; belgedeki yazım da büyük/küçük olabilir.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildBuiltInRow(),
            const Divider(height: 24),
            _buildCustomList(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: (_loading || _saving) ? null : _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('Özel Satır Ekle'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuiltInRow() {
    final builtIns = [
      SpecialLinesRegistry.veya,
      SpecialLinesRegistry.haftada,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Sistem Şablonları',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Sistem tarafından sağlanır, düzenlenemez.',
              child: Icon(Icons.lock_outline,
                  size: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: builtIns
              .map(
                (cfg) => Chip(
                  avatar: Icon(
                    cfg.hasNumber ? Icons.calendar_today : Icons.sync_alt,
                    size: 16,
                    color: Colors.grey.shade700,
                  ),
                  label: Text(cfg.toTemplate()),
                  backgroundColor: Colors.grey.shade100,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCustomList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Özel Şablonlar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_customLines.length})',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_saving) ...[
              const Spacer(),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_customLines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Henüz özel şablon eklenmemiş.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customLines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final cfg = _customLines[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  cfg.hasNumber ? Icons.calendar_today : Icons.bookmark_outline,
                  color: Colors.teal,
                ),
                title: Text(
                  cfg.toTemplate(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  cfg.hasNumber
                      ? 'Sayı içerir — örn. "${cfg.formatWithNumber(2)}", "${cfg.formatWithNumber(5)}"'
                      : 'Sabit ifade',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Düzenle',
                      onPressed:
                          _saving ? null : () => _showEditDialog(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      tooltip: 'Sil',
                      onPressed:
                          _saving ? null : () => _confirmDelete(index),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Appointment background colors management section.
// Lets the admin pick a background color (from a curated dropdown palette) for
// each appointment-card slot. Stored at `admininput/appointmentColors`.
// `AppointmentType.getBgColor` consults the registry these settings populate
// at app start, so the appointment screens reflect the admin choices.
// ---------------------------------------------------------------------------
class _AppointmentColorsSection extends StatefulWidget {
  const _AppointmentColorsSection();

  @override
  State<_AppointmentColorsSection> createState() =>
      _AppointmentColorsSectionState();
}

class _AppointmentColorsSectionState extends State<_AppointmentColorsSection> {
  bool _loading = true;
  bool _saving = false;

  /// Working copy: slot -> palette option id. A null entry means "use the
  /// built-in default" (i.e. no override saved for that slot yet).
  final Map<AppointmentColorSlot, String?> _draft = {};

  /// Snapshot of the saved overrides, used to enable/disable the Save button.
  Map<AppointmentColorSlot, String> _saved = const {};

  @override
  void initState() {
    super.initState();
    for (final slot in AppointmentColorSlot.values) {
      _draft[slot] = null;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final provider =
          Provider.of<AppointmentColorsProvider>(context, listen: false);
      final overrides = await provider.fetchColors(force: true);
      if (!mounted) return;
      setState(() {
        _saved = Map<AppointmentColorSlot, String>.from(overrides);
        for (final slot in AppointmentColorSlot.values) {
          _draft[slot] = overrides[slot];
        }
        _loading = false;
      });
    } catch (e) {
      _appointmentColorsLogger
          .err('Failed to load appointment colors: {}', [e.toString()]);
      if (!mounted) return;
      setState(() => _loading = false);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu renkleri yüklenirken bir hata oluştu.',
      );
    }
  }

  bool get _hasUnsavedChanges {
    for (final slot in AppointmentColorSlot.values) {
      final draftValue = _draft[slot];
      final savedValue = _saved[slot];
      if (draftValue != savedValue) return true;
    }
    return false;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Renkler kaydediliyor...');
      loadingOpen = true;
    }
    try {
      final overrides = <AppointmentColorSlot, String>{};
      _draft.forEach((slot, optionId) {
        if (optionId != null) overrides[slot] = optionId;
      });
      final provider =
          Provider.of<AppointmentColorsProvider>(context, listen: false);
      await provider.saveColors(overrides);
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (!mounted) return;
      setState(() {
        _saved = overrides;
      });
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevu renkleri güncellendi.',
      );
    } catch (e) {
      _appointmentColorsLogger
          .err('Failed to save appointment colors: {}', [e.toString()]);
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu renkleri kaydedilirken bir hata oluştu.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Varsayılana Döndür',
      message:
          'Tüm slotlar varsayılan renklerine döndürülecek. Devam etmek istiyor musunuz?',
      confirmText: 'Sıfırla',
      cancelText: 'İptal',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      for (final slot in AppointmentColorSlot.values) {
        _draft[slot] = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette_outlined, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Randevu Arkaplan Renkleri',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Randevu kartlarının arkaplan rengi randevu türüne göre değişir. '
              'Her tür için kullanılacak rengi aşağıdaki listeden seçebilirsiniz. '
              'Boş bırakılan slotlar uygulamanın varsayılan rengini kullanır.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Column(
                children: [
                  for (final slot in AppointmentColorSlot.values) ...[
                    _buildSlotRow(slot),
                    if (slot != AppointmentColorSlot.values.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: (_loading || _saving) ? null : _resetToDefaults,
                  icon: const Icon(Icons.restore),
                  label: const Text('Varsayılana Döndür'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_loading || _saving || !_hasUnsavedChanges)
                      ? null
                      : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotRow(AppointmentColorSlot slot) {
    final selectedId = _draft[slot];
    final selectedOption = AppointmentColorPalette.findById(selectedId);
    final effectiveColor = selectedOption?.color ?? slot.defaultOption.color;
    final isUsingDefault = selectedId == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _ColorSwatch(color: effectiveColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isUsingDefault
                      ? 'Varsayılan: ${slot.defaultOption.label}'
                      : 'Seçili: ${selectedOption?.label ?? '—'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              isExpanded: true,
              value: selectedId,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      _ColorSwatch(
                        color: slot.defaultOption.color,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Varsayılan (${slot.defaultOption.label})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final opt in AppointmentColorPalette.options)
                  DropdownMenuItem<String?>(
                    value: opt.id,
                    child: Row(
                      children: [
                        _ColorSwatch(color: opt.color, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            opt.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _draft[slot] = value;
                      });
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}
