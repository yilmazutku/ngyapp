import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

/// A widget for selecting a date in dialog forms
class DatePickerFormField extends StatelessWidget {
  /// The currently selected date
  final DateTime? selectedDate;

  /// Callback when a date is selected
  final Function(DateTime) onDateSelected;

  /// Label to display when no date is selected
  final String label;

  /// Label to display with the selected date
  final String selectedLabel;

  /// Format for displaying dates
  final DateFormat? dateFormat;

  /// The earliest selectable date
  final DateTime? firstDate;

  /// The latest selectable date
  final DateTime? lastDate;

  /// Optional icon to display in the trailing position
  final Icon? trailingIcon;

  /// Creates a date picker form field for dialogs
  const DatePickerFormField({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.label,
    this.selectedLabel = 'Seçilen Tarih',
    this.dateFormat,
    this.firstDate,
    this.lastDate,
    this.trailingIcon = const Icon(Icons.calendar_today),
  });

  @override
  Widget build(BuildContext context) {
    final DateFormat format = dateFormat ?? DateFormat('dd.MM.yyyy', 'tr_TR');

    return ListTile(
      title: Text(
        selectedDate == null
            ? label
            : '$selectedLabel: ${format.format(selectedDate!)}',
        style: selectedDate != null
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ),
      trailing: trailingIcon,
      onTap: () async {
        final DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime(2030),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Colors.blue,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
              ),
              child: child!,
            );
          },
        );

        if (pickedDate != null) {
          onDateSelected(pickedDate);
        }
      },
    );
  }
}

/// A widget for uploading and previewing images in dialog forms
class ImageUploadPreview extends StatelessWidget {
  /// The current image file
  final File? imageFile;

  /// Optional URL of an existing image
  final String? existingImageUrl;

  /// Callback when an image is picked
  final Function(File) onImagePicked;

  /// Upload button text
  final String buttonText;

  /// Message to display when no image is selected
  final String noImageText;

  /// Height to display the image preview
  final double previewHeight;

  /// Creates an image upload and preview widget for dialogs
  const ImageUploadPreview({
    super.key,
    required this.imageFile,
    required this.onImagePicked,
    this.existingImageUrl,
    this.buttonText = 'Resim Yükle',
    this.noImageText = 'Resim Seçilmedi',
    this.previewHeight = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            final ImagePicker picker = ImagePicker();
            final XFile? pickedFile = await picker.pickImage(
              source: ImageSource.gallery,
            );

            if (pickedFile != null) {
              onImagePicked(File(pickedFile.path));
            }
          },
          icon: const Icon(Icons.upload_file),
          label: Text(buttonText),
        ),
        const SizedBox(height: 16),
        if (imageFile != null)
          Image.file(
            imageFile!,
            height: previewHeight,
            fit: BoxFit.cover,
          )
        else if (existingImageUrl != null && existingImageUrl!.isNotEmpty)
          Image.network(
            existingImageUrl!,
            height: previewHeight,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                height: previewHeight,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                height: previewHeight,
                child: const Center(
                  child: Text('Resim yüklenemedi'),
                ),
              );
            },
          )
        else
          Text(noImageText),
      ],
    );
  }
}

/// A widget for status selection dropdown in dialog forms
class StatusDropdown<T> extends StatelessWidget {
  /// The currently selected status
  final T selectedStatus;

  /// Callback when a status is selected
  final Function(T?) onStatusChanged;

  /// Map of status values to their display labels
  final Map<T, String> statusOptions;

  /// Label for the dropdown
  final String label;

  /// Creates a status dropdown for dialogs
  const StatusDropdown({
    super.key,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.statusOptions,
    this.label = 'Durum',
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: selectedStatus,
      items: statusOptions.entries.map((entry) {
        return DropdownMenuItem<T>(
          value: entry.key,
          child: Text(entry.value),
        );
      }).toList(),
      onChanged: onStatusChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// A widget for displaying confirmation details in dialogs
class ConfirmationDetails extends StatelessWidget {
  /// The title to display
  final String title;

  /// The list of details to display as key-value pairs
  final Map<String, String> details;

  /// Creates a confirmation details widget for dialogs
  const ConfirmationDetails({
    super.key,
    required this.title,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 16),
        ...details.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${entry.key}: ${entry.value}'),
          );
        }),
      ],
    );
  }
}
