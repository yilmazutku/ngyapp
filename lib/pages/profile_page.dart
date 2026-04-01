import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ngy_app/pages/reset_password_page.dart';
import 'package:intl/intl.dart';
import 'package:ngy_app/services/meal_reminder_service.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

class ProfilePage extends StatefulWidget {
  final String userId;

  const ProfilePage({super.key, required this.userId});

  @override
  createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _ageController = TextEditingController();
  bool _isLoading = true;
  bool _mealNotificationsEnabled = false;
  bool _announcementNotificationsEnabled = true; // Default to true
  DateTime? _createDate;

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      print('Loading data for userId: ${widget.userId}');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final data = userDoc.data();
      print('User data: $data');
      if (data != null) {
        _nameController.text = data['name'] ?? '';
        _surnameController.text = data['surname'] ?? '';
        _ageController.text = data['age']?.toString() ?? '';
        _createDate = data['createDate'] != null 
          ? (data['createDate'] as Timestamp).toDate() 
          : (data['createdAt'] != null 
              ? (data['createdAt'] as Timestamp).toDate() 
              : null);
        setState(() {
          _mealNotificationsEnabled = data['mealNotificationsEnabled'] ?? false;
          _announcementNotificationsEnabled = data['announcementNotificationsEnabled'] ?? true;
        });
      } else {
        print('No data found for userId: ${widget.userId}');
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveUserData() async {
    if (_nameController.text.isEmpty ||
        _surnameController.text.isEmpty ||
        _ageController.text.isEmpty) {
      _showInfoDialog('Lütfen tüm alanları doldurun.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      int? age = int.tryParse(_ageController.text);
      if (age == null) {
        _showInfoDialog('Lütfen Yaş alanına geçerli bir sayı giriniz.');
        setState(() {
          _isLoading = false;
        });
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'name': _nameController.text,
        'surname': _surnameController.text,
        'age': age,
        'mealNotificationsEnabled': _mealNotificationsEnabled,
        'announcementNotificationsEnabled': _announcementNotificationsEnabled,
      }, SetOptions(merge: true));
      print('User data saved for userId: ${widget.userId}');
    } catch (e) {
      print('Error saving user data: $e');
    }
    setState(() {
      _isLoading = false;
    });
    _showInfoDialog('Bilgiler güncellendi!');
  }


  Future<void> _requestAccountDeletion() async {
    if (!mounted) return;

    final firstConfirm = await DialogUtils.openConfirm(
      context,
      title: 'Hesap Silme Talebi',
      message:
          'Hesabınız ve ilişkili tüm verileriniz silinmek üzere işaretlenecektir. '
          'Bu işlemden sonra hesabınıza giriş yapamayacaksınız. '
          'Devam etmek istediğinize emin misiniz?',
      confirmText: 'Evet, devam et',
      cancelText: 'Vazgeç',
    );

    if (!firstConfirm || !mounted) return;

    final secondConfirm = await DialogUtils.openConfirm(
      context,
      title: 'Son Onay',
      message:
          'Bu işlem geri alınamaz. Hesabınız kalıcı olarak silinmek üzere '
          'işaretlenecek ve bir daha giriş yapamayacaksınız. '
          'Gerçekten emin misiniz?',
      confirmText: 'Evet, hesabımı sil',
      cancelText: 'Vazgeç',
    );

    if (!secondConfirm || !mounted) return;

    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(context, message: 'İşlem yapılıyor...');
        loadingOpen = true;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({'isUserRequestedRemoval': true}, SetOptions(merge: true));

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'İşlem sırasında bir hata oluştu. Lütfen tekrar deneyiniz.',
        );
      }
    }
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonWidth = MediaQuery.of(context).size.width * 0.33;

    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Profilim',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kişisel Bilgiler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Ad'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _surnameController,
                    decoration: const InputDecoration(labelText: 'Soyad'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ageController,
                    decoration: const InputDecoration(labelText: 'Yaş'),
                    keyboardType: TextInputType.number,
                  ),
                  if (_createDate != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Hesap Oluşturma Tarihi: ${_formatTimestamp(Timestamp.fromDate(_createDate!))}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Bildirim Ayarları',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Öğün Hatırlatmaları'),
                    subtitle: const Text('Öğün zamanı geçtiğinde bildirim al'),
                    value: _mealNotificationsEnabled,
                    onChanged: (bool value) async {
                      setState(() {
                        _mealNotificationsEnabled = value;
                      });
                      
                      // Save preference immediately
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.userId)
                          .set({
                        'mealNotificationsEnabled': value,
                      }, SetOptions(merge: true));
                      
                      // Schedule or cancel meal reminders based on toggle
                      final reminderService = MealReminderService();
                      if (value) {
                        // User enabled notifications - schedule reminders
                        await reminderService.scheduleMealReminders(widget.userId);
                        if (!mounted) return;
                        _showInfoDialog('Öğün hatırlatmaları etkinleştirildi.');
                      } else {
                        // User disabled notifications - cancel all reminders
                        await reminderService.cancelAllMealReminders();
                        if (!mounted) return;
                        _showInfoDialog('Öğün hatırlatmaları devre dışı bırakıldı.');
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Duyuru Bildirimleri'),
                    subtitle: const Text('Yeni duyurular için bildirim al'),
                    value: _announcementNotificationsEnabled,
                    onChanged: (bool value) async {
                      setState(() {
                        _announcementNotificationsEnabled = value;
                      });
                      
                      // Save preference immediately
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.userId)
                          .set({
                        'announcementNotificationsEnabled': value,
                      }, SetOptions(merge: true));
                      
                      if (!mounted) return;
                      if (value) {
                        _showInfoDialog('Duyuru bildirimleri etkinleştirildi.');
                      } else {
                        _showInfoDialog('Duyuru bildirimleri devre dışı bırakıldı.');
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: buttonWidth,
                          child: ElevatedButton.icon(
                            onPressed: _saveUserData,
                            icon: const Icon(Icons.save),
                            label: const Text('Kaydet'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: buttonWidth,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResetPasswordPage(
                                    email: FirebaseAuth
                                            .instance.currentUser?.email ??
                                        '',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.lock_reset),
                            label: const Text('Şifre Sıfırla'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  const Divider(),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: _requestAccountDeletion,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text(
                        'Hesabımı ve ilişkili tüm verileri sil',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
