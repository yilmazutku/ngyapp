import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../utils/dialog_utils.dart';
import 'news_model.dart';
import 'news_provider.dart';

/// Dialog for adding or editing a news/announcement
class AddNewsDialog extends StatefulWidget {
  final NewsModel? news; // If provided, we're editing
  final VoidCallback? onSaved;

  const AddNewsDialog({
    super.key,
    this.news,
    this.onSaved,
  });

  @override
  State<AddNewsDialog> createState() => _AddNewsDialogState();
}

class _AddNewsDialogState extends State<AddNewsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _linkController = TextEditingController();

  final List<String> _links = [];
  bool _isPublished = false; // Default to draft, publish explicitly later
  bool _isSaving = false;

  // Image handling
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _existingImageUrl;

  bool get _isEditing => widget.news != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.news!.title;
      _bodyController.text = widget.news!.bodyText;
      _links.addAll(widget.news!.links);
      _isPublished = widget.news!.isPublished;
      _existingImageUrl = widget.news!.imageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      if (!mounted) return;
      setState(() {
        _selectedImageFile = File(pickedFile.path);
        _selectedImageBytes = null;
        _selectedImageName = null;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _existingImageUrl = null;
    });
  }

  void _addLink() {
    final link = _linkController.text.trim();
    if (link.isEmpty) return;

    // Basic URL validation
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı http:// veya https:// ile başlamalıdır')),
      );
      return;
    }

    setState(() {
      _links.add(link);
      _linkController.clear();
    });
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    bool loadingOpen = false;
    try {
      if (mounted) {
        DialogUtils.openLoading(
          context,
          message: _isEditing ? 'Duyuru güncelleniyor...' : 'Duyuru ekleniyor...',
        );
        loadingOpen = true;
      }

      final provider = Provider.of<NewsProvider>(context, listen: false);

      if (_isEditing) {
        await provider.updateNews(
          newsId: widget.news!.newsId,
          title: _titleController.text.trim(),
          bodyText: _bodyController.text.trim(),
          newImageFile: _selectedImageFile,
          newImageBytes: _selectedImageBytes,
          newImageName: _selectedImageName,
          existingImageUrl: _existingImageUrl,
          links: _links,
          isPublished: _isPublished,
        );
      } else {
        await provider.addNews(
          title: _titleController.text.trim(),
          bodyText: _bodyController.text.trim(),
          imageFile: _selectedImageFile,
          imageBytes: _selectedImageBytes,
          imageName: _selectedImageName,
          links: _links,
          isPublished: _isPublished,
        );
      }

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved?.call();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Duyuru güncellendi' : 'Duyuru eklendi'),
            backgroundColor: Colors.green,
          ),
        );
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
          message: _isEditing
              ? 'Duyuru güncellenirken bir hata oluştu.'
              : 'Duyuru eklenirken bir hata oluştu.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 600.0 : screenWidth * 0.95;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditing ? Icons.edit : Icons.add,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Duyuru Düzenle' : 'Yeni Duyuru',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Başlık *',
                          hintText: 'Duyuru başlığını girin',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Başlık zorunludur';
                          }
                          return null;
                        },
                        maxLength: 150,
                      ),
                      const SizedBox(height: 16),

                      // Body text field
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          labelText: 'İçerik *',
                          hintText: 'Duyuru içeriğini girin (URL\'ler otomatik olarak tıklanabilir olacaktır)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'İçerik zorunludur';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Image section
                      _buildImageSection(),
                      const SizedBox(height: 16),

                      // Links section
                      _buildLinksSection(),
                      const SizedBox(height: 16),

                      // Publish status
                      SwitchListTile(
                        title: const Text('Yayınla'),
                        subtitle: Text(
                          _isPublished
                              ? 'Duyuru kullanıcılara görünür olacak'
                              : 'Duyuru taslak olarak kaydedilecek',
                        ),
                        value: _isPublished,
                        onChanged: (value) {
                          setState(() {
                            _isPublished = value;
                          });
                        },
                        secondary: Icon(
                          _isPublished ? Icons.visibility : Icons.visibility_off,
                          color: _isPublished ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveNews,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isEditing ? Icons.save : Icons.add),
                    label: Text(_isEditing ? 'Kaydet' : 'Ekle'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Görsel',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        if (_selectedImageFile != null ||
            _selectedImageBytes != null ||
            (_existingImageUrl != null && _existingImageUrl!.isNotEmpty))
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _selectedImageBytes != null
                    ? Image.memory(
                        _selectedImageBytes!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      )
                    : _selectedImageFile != null
                        ? Image.file(
                            _selectedImageFile!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            _existingImageUrl!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                ),
                              );
                            },
                          ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blue,
                      child: IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.white),
                        onPressed: _pickImage,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.white),
                        onPressed: _removeImage,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          InkWell(
            onTap: _pickImage,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey[500]),
                    const SizedBox(height: 8),
                    Text(
                      'Görsel seçmek için tıklayın',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLinksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bağlantılar (Opsiyonel)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addLink(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).primaryColor,
              onPressed: _addLink,
              tooltip: 'Bağlantı Ekle',
            ),
          ],
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _links.asMap().entries.map((entry) {
              final index = entry.key;
              final link = entry.value;
              // Show shortened URL
              String shortLink = link;
              try {
                final uri = Uri.parse(link);
                shortLink = uri.host;
                if (shortLink.length > 25) {
                  shortLink = '${shortLink.substring(0, 25)}...';
                }
              } catch (_) {}

              return Chip(
                label: Text(shortLink, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeLink(index),
                backgroundColor: Colors.blue.withOpacity(0.1),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Not: İçerik alanındaki URL\'ler otomatik olarak tıklanabilir olur. Buraya eklenen bağlantılar ayrı bir bölümde gösterilir.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

