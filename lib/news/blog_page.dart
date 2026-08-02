import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'news_card.dart';
import 'news_detail_page.dart';
import 'news_model.dart';
import 'news_provider.dart';

/// Public blog page listing published news items marked with showInBlog.
/// Accessible without login (reachable from the login page).
class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  static const String _pageTitle = 'Blog';
  static const String _errorText = 'Blog yazıları yüklenirken bir hata oluştu.';
  static const String _emptyText = 'Henüz blog yazısı bulunmuyor.';
  static const String _retryText = 'Tekrar Dene';

  List<NewsModel> _blogList = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Defer loading until after the build phase to avoid "setState during build" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBlogNews();
    });
  }

  Future<void> _loadBlogNews() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = Provider.of<NewsProvider>(context, listen: false);
      final news = await provider.fetchBlogNews();
      if (!mounted) return;
      setState(() {
        _blogList = news;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _errorText;
        _isLoading = false;
      });
    }
  }

  void _openNewsDetail(NewsModel news) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(news: news),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_pageTitle),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadBlogNews,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBlogNews,
              child: const Text(_retryText),
            ),
          ],
        ),
      );
    }

    if (_blogList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _emptyText,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _blogList.length,
      itemBuilder: (context, index) {
        return NewsCard(
          news: _blogList[index],
          onTap: () => _openNewsDetail(_blogList[index]),
        );
      },
    );
  }
}
