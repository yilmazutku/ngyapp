// dialogs/add_image_dialog.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/subs_model.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';

class AddImageDialog extends StatefulWidget {
  final String userId;
  final VoidCallback onImageAdded;

  const AddImageDialog({
    super.key,
    required this.userId,
    required this.onImageAdded,
  });

  @override
  createState() => _AddImageDialogState();
}

class _AddImageDialogState extends State<AddImageDialog> {
  final Logger logger = Logger.forClass(AddImageDialog);
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Meals? _selectedMeal;
  bool _isUploading = false;
  String? _errorMessage;
  
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = false;

  @override
  void initState() {
    super.initState();
    _fetchSubscriptions();
  }
  
  Future<void> _fetchSubscriptions() async {
    setState(() {
      _isLoadingSubscriptions = true;
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final List<SubscriptionModel> activeSubscriptions =
      await subProvider.fetchSubscriptions(
        userId: widget.userId,
        showAllSubscriptions: false, // Only active subscriptions
      );


      setState(() {
        _subscriptions = activeSubscriptions;
        _isLoadingSubscriptions = false;
        
        if (_subscriptions.isNotEmpty) {
          _selectedSubscription = _subscriptions.first;
        } else {
          _selectedSubscription = null;
        }
      });
      
      if (activeSubscriptions.isEmpty) {
        logger.err('No active subscriptions found for user: {}', [widget.userId]);
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Uyarı',
            message:
                'Bu kullanıcının aktif paketi bulunmamaktadır. Fotoğraf eklemek için önce bir paket eklemelisiniz.',
          );
        }
      }
    } catch (e) {
      logger.err('Error fetching subscriptions: {}', [e]);
      setState(() {
        _isLoadingSubscriptions = false;
      });
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Paketler yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mealOptions = Meals.dietValues;

    return AlertDialog(
      title: const Text('Add Meal Image'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<Meals>(
              value: _selectedMeal,
              hint: const Text('Select Meal Type'),
              onChanged: (Meals? newValue) {
                setState(() {
                  _selectedMeal = newValue;
                });
              },
              items: mealOptions.map((Meals meal) {
                return DropdownMenuItem<Meals>(
                  value: meal,
                  child: Text(meal.label),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            
            if (_isLoadingSubscriptions)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<SubscriptionModel>(
                value: _selectedSubscription,
                decoration: const InputDecoration(
                  labelText: 'Paket *',
                  border: OutlineInputBorder(),
                  hintText: 'Paket seçin',
                ),
                items: _subscriptions.map((sub) {
                  return DropdownMenuItem<SubscriptionModel>(
                    value: sub,
                    child: Text(
                      sub.packageName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSubscription = value;
                  });
                },
              ),
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text('Select Image'),
            ),
            const SizedBox(height: 16),
            _selectedImage != null
                ? Image.file( //image.dart: "Image.file is not supported on Flutter Web. Consider using either Image.asset or Image.network instead."
                    File(_selectedImage!.path),
                    height: 100,
                  )
                : const Text('No image selected'),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _uploadImage,
          child: _isUploading
              ? const CircularProgressIndicator()
              : const Text('Upload'),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = pickedFile;
        });
      }
    } catch (e) {
      logger.err('Error picking image: $e');
      setState(() {
        _errorMessage = 'Error picking image.';
      });
    }
  }

  Future<void> _uploadImage() async {
    // 1) Basic validation: we need meal type, image and subscription
    if (_selectedMeal == null) {
      setState(() {
        _errorMessage = 'Please select a meal type.';
      });
      return;
    }

    if (_selectedImage == null) {
      setState(() {
        _errorMessage = 'Please select an image.';
      });
      return;
    }

    if (_selectedSubscription == null) {
      setState(() {
        _errorMessage = 'Please select a subscription.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final mealManager = Provider.of<MealManager>(context, listen: false);

      final downloadUrl = await mealManager.uploadMealImg(
        userId: widget.userId,
        meal: _selectedMeal!,
        image: _selectedImage!,
        subscriptionId: _selectedSubscription!.subscriptionId,
        alsoPostToChat: false,
      );

      if (downloadUrl != null) {
        widget.onImageAdded();

        if (!mounted) return;

        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Resim başarıyla yüklendi.',
        );

        Navigator.of(context).pop();
      } else {
        setState(() {
          _errorMessage =
              'Yükleme başarısız. Bu öğün için en fazla ${MealModel.maxImages} görsel ekleyebilirsiniz.';
        });
      }
    } catch (e) {
      logger.err('Error in _uploadImage: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Resim yüklenirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

}
