// details_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';

/// DetailsTab doesn't use filtering so it doesn't extend BaseTab
/// It's a standalone StatefulWidget
class DetailsTab extends StatefulWidget {
  final String userId;
  const DetailsTab({super.key, required this.userId});

  @override
  State<DetailsTab> createState() => _DetailsTabState();
}

class _DetailsTabState extends State<DetailsTab>
    with AutomaticKeepAliveClientMixin<DetailsTab> {
  late Future<UserModel?> _userFuture;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _surnameController = TextEditingController();
  final _ageController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  final _dosyaNoController = TextEditingController();

  final _scrollCtrl = ScrollController();

  bool _isEditing = false;
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _userFuture = userProvider.fetchUserDetails(userId: widget.userId);
  }

  @override
  void didUpdateWidget(covariant DetailsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      setState(() {
        _isEditing = false;
        _userFuture = userProvider.fetchUserDetails(userId: widget.userId);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _dosyaNoController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _populateFields(UserModel user) {
    _nameController.text = user.name;
    _emailController.text = user.email;
    _surnameController.text = user.surname;
    _ageController.text = user.age?.toString() ?? '';
    _referenceController.text = user.reference ?? '';
    _notesController.text = user.notes ?? '';
    _dosyaNoController.text = user.dosyaNo ?? '';
  }

  Future<void> _saveChanges(UserModel user) async {
    final newEmail = _emailController.text.trim();

    if (_nameController.text.trim().isEmpty) {
      DialogUtils.openError(context, title: 'Hata', message: 'Ad alanı boş bırakılamaz.');
      return;
    }
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      DialogUtils.openError(context, title: 'Hata', message: 'Geçerli bir e-posta adresi giriniz.');
      return;
    }

    // Changing the email also changes the account the user signs in with, so
    // confirm with the admin before touching Firebase Authentication.
    final emailChanged = newEmail.toLowerCase() != user.email.trim().toLowerCase();
    if (emailChanged) {
      final confirmed = await DialogUtils.openConfirm(
        context,
        title: 'E-posta Değişikliği',
        message: 'Giriş e-postası "${user.email}" adresinden "$newEmail" adresine '
            'değiştirilecek.\n\nKullanıcı bundan sonra yeni e-postası ve mevcut '
            'şifresiyle giriş yapacak; eski e-posta ile giriş yapılamayacak.\n\n'
            'Devam etmek istiyor musunuz?',
        confirmText: 'Evet, Değiştir',
        cancelText: 'Vazgeç',
      );
      if (!confirmed) return;
    }

    if (!mounted) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    final updatedUser = UserModel(
      userId: user.userId,
      name: _nameController.text,
      email: newEmail,
      password: user.password,
      role: user.role,
      createDate: user.createDate,
      createUser: user.createUser,
      updateDate: DateTime.now(),
      updateUser: 'admin',
      surname: _surnameController.text,
      age: _ageController.text.isEmpty ? null : int.tryParse(_ageController.text),
      reference: _referenceController.text.isEmpty ? null : _referenceController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      dosyaNo: _dosyaNoController.text.trim().isEmpty ? null : _dosyaNoController.text.trim(),
    );

    setState(() => _isLoading = true);

    bool loadingOpen = false;
    if (emailChanged && mounted) {
      DialogUtils.openLoading(context, message: 'E-posta güncelleniyor...');
      loadingOpen = true;
    }

    try {
      // Update the sign-in email first (Auth + Firestore via Cloud Function) so
      // we never persist a Firestore email the user cannot log in with.
      if (emailChanged) {
        await userProvider.updateUserEmail(userId: user.userId, newEmail: newEmail);
      }

      await userProvider.updateUserDetails(updatedUser);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _userFuture = userProvider.fetchUserDetails(userId: user.userId);
      });

      DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: emailChanged
            ? 'Kullanıcı bilgileri güncellendi. Kullanıcı artık yeni e-postası '
                've mevcut şifresiyle giriş yapabilir.'
            : 'Kullanıcı bilgileri başarıyla güncellendi.',
      );
    } catch (e) {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Kullanıcı bilgileri güncellenirken bir hata oluştu: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    return FutureBuilder<UserModel?>(
      future: _userFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Kullanıcı detayları alınırken hata oluştu: ${snapshot.error}'));
        } else if (snapshot.data == null) {
          return const Center(child: Text('Kullanıcı bilgisi bulunamadı.'));
        }

        final user = snapshot.data!;
        if (!_isEditing) _populateFields(user);

        return Scrollbar(
          controller: _scrollCtrl,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEditing) ...[
                  _buildUserCard(user),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        const Text('Kullanıcı Detayları',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _isEditing = true),
                          icon: const Icon(Icons.edit),
                          label: const Text('Düzenle'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.blue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildReadOnlyField('Dosya NO', user.dosyaNo ?? ''),
                          _buildReadOnlyField('Ad', user.name),
                          _buildReadOnlyField('Soyisim', user.surname),
                          _buildReadOnlyField('E-posta', user.email),
                          _buildReadOnlyField('Yaş', user.age?.toString() ?? ''),
                          _buildReadOnlyField('Referans', user.reference ?? ''),
                          Text('Notlar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.grey[700],
                              )),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            constraints: const BoxConstraints(minHeight: 100),
                            child: Text(
                              user.notes?.isEmpty ?? true ? 'Not bulunmamaktadır' : user.notes!,
                              style: TextStyle(
                                fontSize: 16,
                                color: user.notes?.isEmpty ?? true ? Colors.grey[500] : Colors.grey[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Text('Kullanıcı Bilgilerini Düzenle',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        onPressed: () => setState(() => _isEditing = false),
                        icon: const Icon(Icons.close),
                        tooltip: 'Düzenlemeyi İptal Et',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEditableField('Dosya NO', _dosyaNoController),
                          _buildEditableField('Ad', _nameController, required: true),
                          _buildEditableField('Soyisim', _surnameController),
                          _buildEditableField('E-posta', _emailController,
                              keyboardType: TextInputType.emailAddress, required: true),
                          _buildEditableField('Yaş', _ageController, keyboardType: TextInputType.number),
                          _buildEditableField('Referans', _referenceController),
                          _buildEditableField('Notlar', _notesController, maxLines: 5),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => setState(() => _isEditing = false),
                                icon: const Icon(Icons.cancel),
                                label: const Text('İptal'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _isLoading ? null : () => _saveChanges(user),
                                icon: _isLoading
                                    ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.save),
                                label: Text(_isLoading ? 'Kaydediliyor...' : 'Kaydet'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UI helpers (unchanged semantics, small cosmetics) ---

  Widget _buildUserCard(UserModel user) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blue.shade100,
              child: Text(
                _getInitials(user.name, user.surname),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${user.name} ${user.surname}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(user.email, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration:
              BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
              child: Text(
                _getRoleLabel(user.role),
                style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
              ),
            ),
            if (user.age != null || user.reference != null) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (user.age != null) _buildInfoChip(Icons.cake, 'Yaş: ${user.age}'),
                  if (user.reference != null) _buildInfoChip(Icons.person, 'Referans: ${user.reference}'),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  String _getInitials(String name, String? surname) {
    final a = name.isNotEmpty ? name[0].toUpperCase() : '';
    final b = (surname != null && surname.isNotEmpty) ? surname[0].toUpperCase() : '';
    return '$a$b';
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Yönetici';
      case 'customer':
        return 'Müşteri';
      default:
        return role;
    }
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.blue.shade700),
      label: Text(label),
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              value.isEmpty ? '---' : value,
              style: TextStyle(fontSize: 16, color: value.isEmpty ? Colors.grey[500] : Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
      String label,
      TextEditingController controller, {
        TextInputType keyboardType = TextInputType.text,
        int maxLines = 1,
        bool required = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          required
              ? RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: label,
                  style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[700])),
              const TextSpan(text: ' *', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            ]),
          )
              : Text(label,
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[700])),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: label,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
