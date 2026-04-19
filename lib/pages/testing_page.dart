import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/user_model.dart';
import '../providers/daily_data_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';

final Logger _logger = Logger.forClass(TestingPage);

class TestingPage extends StatefulWidget {
  const TestingPage({super.key});

  @override
  State<TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends State<TestingPage> {
  static const int _testDays = 14;
  static const int _testSteps = 5000;
  static const double _testWater = 3.0;
  static const String _testAssetPath = 'assets/utku.png';

  bool _isRunning = false;
  String _statusMessage = '';
  double _progress = 0.0;

  Future<void> _deleteNonEssentialUsers() async {
    const keepPrefixes = ['0Mvvb', '9CwKr'];

    if (!mounted) return;
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Kullanıcıları Sil',
      message:
          'Tüm kullanıcı dokümanları silinecek.\n\n'
          'Yalnızca şu ön eklere sahip dokümanlar korunacak:\n'
          '• ${keepPrefixes.join('\n• ')}\n\n'
          'Bu işlem geri alınamaz. Devam edilsin mi?',
    );
    if (!confirmed) return;

    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _statusMessage = 'Kullanıcılar sorgulanıyor...';
    });

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').get();

      final docsToDelete = snapshot.docs.where((doc) {
        return !keepPrefixes.any((prefix) => doc.id.startsWith(prefix));
      }).toList();

      if (docsToDelete.isEmpty) {
        if (mounted) {
          setState(() => _statusMessage = 'Silinecek doküman bulunamadı.');
          DialogUtils.openInfo(
            context,
            title: 'Bilgi',
            message: 'Silinecek kullanıcı dokümanı bulunamadı.',
          );
        }
        return;
      }

      if (!mounted) return;
      final doubleConfirm = await DialogUtils.openConfirm(
        context,
        title: 'Son Onay',
        message:
            '${docsToDelete.length} doküman silinecek, '
            '${snapshot.docs.length - docsToDelete.length} doküman korunacak.\n\n'
            'Emin misiniz?',
      );
      if (!doubleConfirm) {
        if (mounted) setState(() => _statusMessage = 'İptal edildi.');
        return;
      }

      int deleted = 0;
      final total = docsToDelete.length;

      for (final doc in docsToDelete) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Siliniyor: ${doc.id} (${deleted + 1}/$total)';
        });

        await doc.reference.delete();
        deleted++;

        if (mounted) {
          setState(() => _progress = deleted / total);
        }
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Tamamlandı! $deleted doküman silindi.';
          _progress = 1.0;
        });
        DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: '$deleted kullanıcı dokümanı silindi.',
        );
      }
    } catch (e) {
      _logger.err('User cleanup failed: {}', [e]);
      if (mounted) {
        setState(() => _statusMessage = 'Hata: $e');
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Silme işlemi sırasında hata oluştu:\n$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  Future<void> _startTest() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    List<UserModel> users;
    try {
      users = await userProvider.fetchUsers();
    } catch (e) {
      if (mounted) {
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Kullanıcılar yüklenemedi: $e',
        );
      }
      return;
    }

    if (users.isEmpty) {
      if (mounted) {
        DialogUtils.openInfo(
          context,
          title: 'Bilgi',
          message: 'Hiç kullanıcı bulunamadı.',
        );
      }
      return;
    }

    if (!mounted) return;
    final selectedUser = await _showUserSelectionDialog(users);
    if (selectedUser == null) return;

    if (!mounted) return;
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Test Verisi Yükle',
      message: '${selectedUser.name} ${selectedUser.surname} kullanıcısı için '
          '$_testDays günlük test verisi yüklenecek.\n\n'
          'Her gün için:\n'
          '• Tüm öğün tipleri (${Meals.dietValues.length} adet) için görsel\n'
          '• $_testSteps adım\n'
          '• $_testWater litre su\n\n'
          'Devam edilsin mi?',
    );
    if (!confirmed) return;

    await _runTestDataUpload(selectedUser.userId);
  }

  Future<UserModel?> _showUserSelectionDialog(List<UserModel> users) {
    return showDialog<UserModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kullanıcı Seç'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (_, index) {
              final user = users[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  ),
                ),
                title: Text('${user.name} ${user.surname}'),
                subtitle: Text(user.email),
                onTap: () => Navigator.pop(ctx, user),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  Future<void> _runTestDataUpload(String userId) async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _statusMessage = 'Görsel yükleniyor...';
    });

    try {
      final byteData = await rootBundle.load(_testAssetPath);
      final Uint8List imageBytes = byteData.buffer.asUint8List();

      final dailyDataProvider =
          Provider.of<DailyDataProvider>(context, listen: false);
      final df = DateFormat('yyyy-MM-dd');
      final today = DateTime.now();
      final todayNormalized =
          DateTime(today.year, today.month, today.day);

      final mealTypes = Meals.dietValues;
      // meals per day + 1 water + 1 steps
      final totalOps = _testDays * (mealTypes.length + 2);
      int completedOps = 0;

      for (int dayOffset = 0; dayOffset < _testDays; dayOffset++) {
        final date = todayNormalized.subtract(Duration(days: dayOffset));
        final dateStr = df.format(date);

        for (final meal in mealTypes) {
          if (!mounted) return;
          setState(() {
            _statusMessage = '$dateStr - ${meal.label} yükleniyor...';
          });

          final storagePath =
              'users/$userId/mealPhotos/$dateStr/${meal.name}/utku.png';
          final ref = FirebaseStorage.instance.ref(storagePath);
          await ref.putData(
            imageBytes,
            SettableMetadata(contentType: 'image/png'),
          );
          final downloadUrl = await ref.getDownloadURL();

          final mealDocRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('meals')
              .doc(dateStr)
              .collection('mealEntries')
              .doc(meal.name);

          final mealModel = MealModel(
            mealId: meal.name,
            mealType: meal,
            imageUrls: [downloadUrl],
            subscriptionId: 'test-subscription',
            timestamp: date,
            isChecked: true,
          );
          await mealDocRef.set(mealModel.toMap());

          final dayDocRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('meals')
              .doc(dateStr);
          await dayDocRef.set({
            'meals': {meal.name: true},
          }, SetOptions(merge: true));

          completedOps++;
          if (mounted) {
            setState(() => _progress = completedOps / totalOps);
          }
        }

        // Water intake
        if (!mounted) return;
        setState(() => _statusMessage = '$dateStr - su verisi...');
        await dailyDataProvider.saveWaterIntake(userId, date, _testWater);
        completedOps++;
        if (mounted) {
          setState(() => _progress = completedOps / totalOps);
        }

        // Steps
        if (!mounted) return;
        setState(() => _statusMessage = '$dateStr - adım verisi...');
        await dailyDataProvider.saveSteps(userId, date, _testSteps);
        completedOps++;
        if (mounted) {
          setState(() => _progress = completedOps / totalOps);
        }
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Tamamlandı!';
          _progress = 1.0;
        });
        DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message:
              '$_testDays günlük test verisi başarıyla yüklendi.',
        );
      }
    } catch (e) {
      _logger.err('Test data upload failed: {}', [e]);
      if (mounted) {
        setState(() => _statusMessage = 'Hata: $e');
        DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Test verisi yüklenirken hata oluştu:\n$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Testing')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
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
                            Icon(Icons.science, size: 28),
                            SizedBox(width: 12),
                            Text(
                              'Test Veri Yükleme',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Seçilen kullanıcı için son $_testDays gün boyunca '
                          'tüm öğün tipleri için test görseli, '
                          '$_testSteps adım ve $_testWater litre su verisi yükler.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isRunning ? null : _startTest,
                            icon: _isRunning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                                _isRunning ? 'Yükleniyor...' : 'Start Test'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
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
                            Icon(Icons.delete_sweep, size: 28, color: Colors.red),
                            SizedBox(width: 12),
                            Text(
                              'Kullanıcı Temizliği',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '0Mvvb ve 9CwKr ile başlayan dokümanlar hariç '
                          'tüm kullanıcı dokümanlarını siler.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isRunning ? null : _deleteNonEssentialUsers,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Kullanıcıları Temizle'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isRunning || _statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Durum',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_isRunning) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progress,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '%${(_progress * 100).toStringAsFixed(1)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _statusMessage.startsWith('Hata')
                                  ? Colors.red
                                  : _statusMessage == 'Tamamlandı!'
                                      ? Colors.green
                                      : null,
                              fontWeight:
                                  _statusMessage == 'Tamamlandı!'
                                      ? FontWeight.bold
                                      : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
