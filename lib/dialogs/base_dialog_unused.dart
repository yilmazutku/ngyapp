// import 'package:flutter/material.dart';
// import '../models/logger.dart';
// import '../utils/logger.dart';
// import '../utils/dialog_utils.dart';
//
// /// A base dialog class that defines common functionality for all dialogs in the app.
// /// Other dialogs should extend this class for consistent behavior and styling.
// abstract class BaseDialog extends StatefulWidget {
//   /// Dialog title to display
//   final String title;
//
//   /// Logger instance for tracking dialog operations
//   final Logger logger;
//
//   /// Creates a base dialog with standard behavior
//   BaseDialog({
//     super.key,
//     required this.title,
//     Logger? logger,
//   })  : logger = logger ?? Logger.forClass(BaseDialog);
//
//   @override
//   BaseDialogState createState();
// }
//
// /// Base state class for dialog state management
// abstract class BaseDialogState<T extends BaseDialog> extends State<T> {
//   /// Whether the dialog is currently loading
//   bool _isLoading = false;
//
//   /// Sets the loading state of the dialog
//   void setLoading(bool isLoading) {
//     if (mounted) {
//       setState(() {
//         _isLoading = isLoading;
//       });
//     }
//   }
//
//   /// Executes the given future and shows loading indicator
//   /// Shows error dialog if an error occurs
//   Future<T?> withLoading<T>(Future<T> Function() future) async {
//     try {
//       setLoading(true);
//       final result = await future();
//       setLoading(false);
//       return result;
//     } catch (e) {
//       widget.logger.err('Error in dialog: $e');
//       setLoading(false);
//       if (mounted) {
//         await DialogUtils.openError(
//           context,
//           title: 'Hata',
//           message: e.toString(),
//         );
//       }
//       return null;
//     }
//   }
//
//   /// Submit the dialog form
//   /// This should be implemented by child classes
//   Future<void> submit();
//
//   /// Cancel button handler
//   void cancel() {
//     Navigator.of(context).pop();
//   }
//
//   /// Build the content of the dialog
//   /// This should be implemented by child classes
//   Widget buildContent(BuildContext context);
//
//   /// Builds the dialog actions
//   List<Widget> buildDialogActions();
//
//   /// Validates the dialog input
//   /// Returns true if validation passes, false otherwise
//   bool validateInput();
//
//   /// Handles the submission of the dialog
//   Future<void> handleSubmit();
//
//   /// Helper method to close the dialog
//   void closeDialog() {
//     Navigator.of(context).pop();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: Text(widget.title),
//       content: SizedBox(
//         width: double.maxFinite,
//         child: Stack(
//           children: [
//             buildContent(context),
//             if (_isLoading)
//               const Center(
//                 child: CircularProgressIndicator(),
//               ),
//           ],
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: _isLoading ? null : cancel,
//           child: const Text('İptal'),
//         ),
//         ElevatedButton(
//           onPressed: _isLoading ? null : submit,
//           child: const Text('Kaydet'),
//         ),
//       ],
//     );
//   }
// }
//
// /// A dialog with a single scrollable content area
// abstract class ScrollableDialogState<T extends BaseDialog>
//     extends BaseDialogState<T> {
//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: Text(widget.title),
//       content: SingleChildScrollView(
//         child: buildContent(context),
//       ),
//       actions: buildDialogActions(),
//     );
//   }
// }
//
// /// Utility functions for managing form fields in dialogs
// mixin DialogFormValidation<T extends BaseDialog> on BaseDialogState<T> {
//   /// Validate that a text controller's value is not empty
//   bool validateRequired(TextEditingController controller, String fieldName) {
//     if (controller.text.isEmpty) {
//       DialogUtils.openError(
//         context,
//         title: 'Hata',
//         message: 'Lütfen $fieldName alanını doldurunuz.',
//       );
//       return false;
//     }
//     return true;
//   }
//
//   /// Validate that a nullable date is not null
//   bool validateDate(DateTime? date, String fieldName) {
//     if (date == null) {
//       DialogUtils.openError(
//         context,
//         title: 'Hata',
//         message: 'Lütfen $fieldName seçiniz.',
//       );
//       return false;
//     }
//     return true;
//   }
//
//   /// Validate that a numeric value is valid
//   bool validateNumeric(TextEditingController controller, String fieldName) {
//     if (controller.text.isEmpty) {
//       DialogUtils.openError(
//         context,
//         title: 'Hata',
//         message: 'Lütfen $fieldName alanını doldurunuz.',
//       );
//       return false;
//     }
//
//     final value = double.tryParse(controller.text);
//     if (value == null || value <= 0) {
//       DialogUtils.openError(
//         context,
//         title: 'Hata',
//         message: 'Lütfen geçerli bir $fieldName giriniz.',
//       );
//       return false;
//     }
//
//     return true;
//   }
// }
