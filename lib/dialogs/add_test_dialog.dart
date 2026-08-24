import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../models/logger.dart';
import '../models/test_model.dart';
import '../utils/dialog_utils.dart';
import '../dialogs/dialog_widgets.dart'; // Import dialog widgets

class AddTestDialog extends StatefulWidget {
  final String userId;
  final Function onTestAdded;

  const AddTestDialog({
    super.key,
    required this.userId,
    required this.onTestAdded,
  });

  @override
  createState() => _AddTestDialogState();
}

class _AddTestDialogState extends State<AddTestDialog> {
  final Logger logger = Logger.forClass(AddTestDialog);

  // Controllers and variables
  final TextEditingController _testNameController = TextEditingController();
  final TextEditingController _testDescriptionController =
      TextEditingController();
  DateTime? _selectedTestDate;
  File? _testFile;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Test'),
      content: SingleChildScrollView(
        child: ListBody(
          children: [
            TextField(
              controller: _testNameController,
              decoration: const InputDecoration(labelText: 'Test Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _testDescriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            // Use DatePickerFormField instead of custom implementation
            DatePickerFormField(
              selectedDate: _selectedTestDate,
              onDateSelected: (date) {
                setState(() {
                  _selectedTestDate = date;
                });
                logger.info('Test date selected: {}', [date]);
              },
              label: 'Test Tarihini Seçin',
              selectedLabel: 'Test Tarihi',
              lastDate: DateTime.now(), // Only allow past dates for tests
            ),
            const SizedBox(height: 16),
            // Use ImageUploadPreview instead of custom implementation
            ImageUploadPreview(
              imageFile: _testFile,
              onImagePicked: (file) {
                setState(() {
                  _testFile = file;
                });
                logger.info('Test file selected: {}', [file.path]);
              },
              buttonText: 'Upload Test File',
              noImageText: 'No test file selected',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).pop(); // Close the dialog
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : () => _addTest(),
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Add Test'),
        ),
      ],
    );
  }

  Future<void> _addTest() async {
    if (_testNameController.text.isEmpty ||
        _selectedTestDate == null ||
        _testFile == null) {
      logger.err('Please fill all required fields.');
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen tüm zorunlu alanları doldurun.',
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Upload the test file
      String testFileUrl = await _uploadTestFile();

      // Create a new test document
      final testDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('tests')
          .doc(); // Generate a new test ID

      TestModel testModel = TestModel(
        testId: testDocRef.id,
        userId: widget.userId,
        testName: _testNameController.text,
        testDescription: _testDescriptionController.text,
        testDate: _selectedTestDate!,
        testFileUrl: testFileUrl,
      );

      await testDocRef.set(testModel.toMap());
      logger.info('Test added successfully for user {}', [widget.userId]);

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Test başarıyla eklendi.',
      );
      widget.onTestAdded();
      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      logger.err('Error adding test: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Test eklenirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _uploadTestFile() async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_testFile!.path.split('/').last}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('users/${widget.userId}/tests/$fileName');
      final uploadTask = ref.putFile(_testFile!);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      logger.info('Test file uploaded: {}', [downloadUrl]);

      return downloadUrl;
    } catch (e) {
      logger.err('Error uploading test file: {}', [e]);
      throw Exception('Error uploading test file: $e');
    }
  }

  @override
  void dispose() {
    _testNameController.dispose();
    _testDescriptionController.dispose();
    super.dispose();
  }
}
