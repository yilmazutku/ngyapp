import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/event_model.dart';
import '../models/logger.dart';
import '../providers/event_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/loading_overlay.dart';

class EditEventDialog extends StatefulWidget {
  final EventModel event;
  final Function onEventUpdated;
  final Function? onEventDeleted;

  const EditEventDialog({
    super.key,
    required this.event,
    required this.onEventUpdated,
    this.onEventDeleted,
  });

  @override
  State<EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<EditEventDialog>
    with LoadingStateMixin {
  static final Logger _logger = Logger.forClass(EditEventDialog);

  final _nameController = TextEditingController();
  final DateFormat _dateFmt = DateFormat('d MMMM yyyy', 'tr_TR');
  final DateFormat _fullFmt = DateFormat('d MMMM yyyy, HH:mm', 'tr_TR');

  late DateTime _startDateTime;
  late DateTime _endDateTime;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.event.name;
    _startDateTime = widget.event.startDateTime;
    _endDateTime = widget.event.endDateTime;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;

    setState(() {
      _startDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _startDateTime.hour,
        _startDateTime.minute,
      );
      _endDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _endDateTime.hour,
        _endDateTime.minute,
      );
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startDateTime),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _startDateTime = DateTime(
        _startDateTime.year,
        _startDateTime.month,
        _startDateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endDateTime),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _endDateTime = DateTime(
        _endDateTime.year,
        _endDateTime.month,
        _endDateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _updateEvent() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen etkinlik adı giriniz.',
      );
      return;
    }

    if (!_endDateTime.isAfter(_startDateTime)) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bitiş saati başlangıçtan sonra olmalıdır.',
      );
      return;
    }

    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Etkinlik Güncelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Aşağıdaki değişiklikleri yapmak istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Text('Etkinlik Adı: $name'),
              Text('Başlangıç: ${_fullFmt.format(_startDateTime)}'),
              Text('Bitiş: ${_fullFmt.format(_endDateTime)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );

    if (shouldUpdate != true) return;

    startLoading();
    try {
      final eventProvider =
          Provider.of<EventProvider>(context, listen: false);
      final updated = EventModel(
        eventId: widget.event.eventId,
        name: name,
        startDateTime: _startDateTime,
        endDateTime: _endDateTime,
        createDate: widget.event.createDate,
      );
      await eventProvider.updateEvent(updated);

      widget.onEventUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Etkinlik başarıyla güncellendi.',
      );
    } catch (e) {
      _logger.err('Error updating event: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Etkinlik güncellenirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  Future<void> _deleteEvent() async {
    final confirm = await DialogUtils.openConfirm(
      context,
      title: 'Etkinliği Sil',
      message: '"${widget.event.name}" etkinliğini silmek istiyor musunuz?',
      confirmText: 'Evet, Sil',
      cancelText: 'Hayır',
    );
    if (!confirm) return;

    startLoading();
    try {
      final eventProvider =
          Provider.of<EventProvider>(context, listen: false);
      await eventProvider.deleteEvent(widget.event.eventId);

      if (widget.onEventDeleted != null) {
        widget.onEventDeleted!();
      } else {
        widget.onEventUpdated();
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Etkinlik başarıyla silindi.',
      );
    } catch (e) {
      _logger.err('Error deleting event: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Etkinlik silinirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Etkinlik Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Etkinlik Adı',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tarih'),
                  subtitle: Text(
                    _dateFmt.format(_startDateTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Başlangıç Saati'),
                  subtitle: Text(
                    DateFormat('HH:mm').format(_startDateTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: _pickStartTime,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bitiş Saati'),
                  subtitle: Text(
                    DateFormat('HH:mm').format(_endDateTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: _pickEndTime,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : _deleteEvent,
                    icon: const Icon(Icons.delete),
                    label: const Text('Etkinliği Sil'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : _updateEvent,
              child: const Text('Kaydet'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'İşlem yapılıyor...'),
      ],
    );
  }
}
