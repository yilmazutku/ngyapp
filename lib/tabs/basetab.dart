// basetab.dart
import 'package:flutter/material.dart';
import '../models/filter_params.dart';

abstract class BaseTab<T> extends StatefulWidget {
  final String userId;
  final String allDataLabel;
  final String subscriptionDataLabel;

  const BaseTab({
    super.key,
    required this.userId,
    required this.allDataLabel,
    required this.subscriptionDataLabel,
  });

  T getProvider(BuildContext context);
  
  /// Fetches data from the provider with optional filter parameters
  /// Filters are applied on the Firebase side for better performance
  Future<List<dynamic>> getDataList(T provider, bool showAllData, {FilterParams? filterParams});

  @override
  BaseTabState<T, BaseTab<T>> createState();
}

abstract class BaseTabState<T, W extends BaseTab<T>> extends State<W>
    with AutomaticKeepAliveClientMixin<W> {
  bool showAllData = true;
  Future<List<dynamic>>? dataFuture;
  bool _dataFetched = false;
  
  // Pagination support for large data sets
  static const int _defaultPageSize = 50;
  int _currentPageSize = _defaultPageSize;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final List<dynamic> _loadedItems = [];
  final ScrollController scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Set up scroll listener for pagination
    scrollController.addListener(_scrollListener);
    // Defer first fetch to didChangeDependencies for safe provider access.
  }
  
  @override
  void dispose() {
    scrollController.removeListener(_scrollListener);
    scrollController.dispose();
    super.dispose();
  }
  
  void _scrollListener() {
    if (!_hasMoreData || _isLoadingMore) return;
    
    // Check if we're near the bottom of the scroll view
    if (scrollController.position.pixels >= 
        scrollController.position.maxScrollExtent - 500) {
      _loadMoreData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dataFetched) {
      fetchData();
      _dataFetched = true;
    }
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      // New user context => clear and refetch
      _dataFetched = false;
      fetchData();
      _dataFetched = true;
    }
  }

  // Load initial data
  void fetchData() {
    // Minimal inline guard to avoid provider errors like "Kullanıcı bulunamadı"
    // if (widget.userId.isEmpty) {
    //   if (mounted) {
    //     showDialog(
    //       context: context,
    //       builder: (_) => const AlertDialog(
    //         title: Text('Warning'),
    //         content: Text('User ID is empty. Cannot load data.'),
    //       ),
    //     );
    //   }
    //   return;
    // }

    // Reset pagination state
    _loadedItems.clear();
    _hasMoreData = true;
    _isLoadingMore = false;
    _currentPageSize = _defaultPageSize;
    
    final provider = widget.getProvider(context);
    final filterParams = buildFilterParams();
    setState(() {
      dataFuture = widget.getDataList(provider, showAllData, filterParams: filterParams)
        .then((data) {
          // Clear before adding to prevent duplicates from race conditions
          _loadedItems.clear();
          _loadedItems.addAll(data.take(_currentPageSize));
          _hasMoreData = data.length > _currentPageSize;
          return _loadedItems.toList(); // Return a copy to avoid modification issues
        });
    });
  }
  
  /// Override in subclasses to provide filter parameters for Firebase queries
  /// By default returns null (no filters)
  FilterParams? buildFilterParams() => null;
  
  // Load more data when scrolling
  void _loadMoreData() {
    if (!_hasMoreData || _isLoadingMore) return;
    
    _isLoadingMore = true;
    final provider = widget.getProvider(context);
    final filterParams = buildFilterParams();
    
    widget.getDataList(provider, showAllData, filterParams: filterParams).then((allData) {
      if (mounted) {
        setState(() {
          // Calculate next batch
          final nextBatchStart = _loadedItems.length;
          final nextBatchEnd = nextBatchStart + _currentPageSize;
          
          // Add next batch of items
          if (nextBatchStart < allData.length) {
            final newItems = allData.skip(nextBatchStart).take(_currentPageSize);
            _loadedItems.addAll(newItems);
            _hasMoreData = nextBatchEnd < allData.length;
          } else {
            _hasMoreData = false;
          }
          
          _isLoadingMore = false;
        });
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    });
  }

  void refreshData() {
    if (mounted) {
      // if (widget.userId.isEmpty) {
      //   showDialog(
      //     context: context,
      //     builder: (_) => const AlertDialog(
      //       title: Text('Warning'),
      //       content: Text('User ID is empty. Cannot refresh data.'),
      //     ),
      //   );
      //   return;
      // }

      // Force refresh by first setting dataFuture to null
      // and clearing any cached data
      setState(() {
        dataFuture = null;
        _loadedItems.clear();
        _hasMoreData = true;
        _isLoadingMore = false;
      });
      
      // Then in a separate setState call, create a new future
      // This ensures the UI shows loading state and fully refreshes
      Future.microtask(() {
        if (mounted) {
          setState(() {
            final provider = widget.getProvider(context);
            final filterParams = buildFilterParams();
            dataFuture = widget.getDataList(provider, showAllData, filterParams: filterParams)
              .then((data) {
                // Clear before adding to prevent duplicates from race conditions
                _loadedItems.clear();
                _loadedItems.addAll(data.take(_currentPageSize));
                _hasMoreData = data.length > _currentPageSize;
                return _loadedItems.toList(); // Return a copy to avoid modification issues
              });
          });
        }
      });
    }
  }

  Future<void> navigateAndRefresh(BuildContext context, Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) refreshData();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for keep-alive
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Top bar with right-aligned refresh icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: refreshData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Yenile'),
                   
                  ),
                ],
              ),
            ),

            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            'Veriyi yüklerken bir hata oluştu. Lütfen tekrar deneyiniz ya da yardım isteyiniz.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: fetchData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tekrar Dene'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    final dataList = snapshot.data ?? const <dynamic>[];
                    return Column(
                      children: [
                        Expanded(
                          child: buildList(context, dataList),
                        ),
                        if (_isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.0),
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Implemented by sub-tabs
  Widget buildList(BuildContext context, List<dynamic> dataList);
}
