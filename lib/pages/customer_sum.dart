// customer_summary_page.dart
import 'package:flutter/material.dart';

import '../tabs/tests_tab.dart';
import '../tabs/details_tab.dart';
import '../tabs/appointments_tab.dart';
import '../tabs/payment_tab.dart';
import '../tabs/images_tab.dart';
import '../tabs/measurements_tab.dart';
import '../tabs/diet_tab.dart';
import '../dialogs/add_image_dialog.dart';
import '../dialogs/add_payment_dialog.dart';
import '../dialogs/add_appointment_dialog.dart';
import '../dialogs/add_sub_dialog.dart';
import '../dialogs/add_diet_dialog.dart';
import '../models/user_model.dart';
import '../models/logger.dart';
import '../tabs/sub_tab.dart';

final Logger logger = Logger.forClass(CustomerSummaryPage);

class CustomerSummaryPage extends StatefulWidget {
  final UserModel user;

  const CustomerSummaryPage({
    super.key,
    required this.user,
  });

  @override
  State<CustomerSummaryPage> createState() => _CustomerSummaryPageState();
}

class _CustomerSummaryPageState extends State<CustomerSummaryPage>
    with SingleTickerProviderStateMixin { // <-- fix here
  late final TabController _tabController;
  int _previousTabIndex = 0;

  // Mark tabs we’ve already shown so they can stay alive without refetching.
  late final List<bool> _tabVisited;

  // Hoisted tabs (built once when first visited); keys preserve state/scroll.
  final _keys = List.generate(8, (i) => PageStorageKey('cust_tab_$i'));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabVisited = List<bool>.filled(8, false)..[0] = true;

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index != _previousTabIndex) {
        logger.info('Tab changed: index={}', [_tabController.index]);
        _previousTabIndex = _tabController.index;
        if (!_tabVisited[_tabController.index]) {
          setState(() => _tabVisited[_tabController.index] = true);
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Tab> get _tabs => const [
    Tab(icon: Icon(Icons.person), text: 'Detay'),
    Tab(icon: Icon(Icons.calendar_today), text: 'Randevu'),
    Tab(icon: Icon(Icons.payment), text: 'Ödeme'),
    Tab(icon: Icon(Icons.image), text: 'Görsel'),
    Tab(icon: Icon(Icons.list_alt), text: 'Test'),
    Tab(icon: Icon(Icons.monitor_weight), text: 'Ölçüm'),
    Tab(icon: Icon(Icons.food_bank), text: 'Diyet'),
    Tab(icon: Icon(Icons.card_membership), text: 'Abonelik'),
  ];

  // Build a tab body only on first visit; keep it alive afterwards.
  Widget _buildTabBody(int index, String userId) {
    if (!_tabVisited[index]) {
      // Lightweight placeholder until it’s visited
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()));
    }
    switch (index) {
      case 0:
        return DetailsTab(key: _keys[index], userId: userId);
      case 1:
        return AppointmentsTab(key: _keys[index], userId: userId);
      case 2:
        return PaymentsTab(key: _keys[index], userId: userId);
      case 3:
        return ImagesTab(key: _keys[index], userId: userId);
      case 4:
        return TestsTab(key: _keys[index], userId: userId);
      case 5:
        return MeasTab(key: _keys[index], userId: userId);
      case 6:
        return DietTab(key: _keys[index], userId: userId);
      case 7:
        return SubscriptionsTab(key: _keys[index], userId: userId);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('${user.name} ${user.surname ?? ""}'.trim()),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: !isTablet,
          tabs: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        // TabBarView lazily builds the current page; we also keep state per tab with keys
        children: List.generate(
          _tabs.length,
              (i) => _buildTabBody(i, user.userId),
        ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: _onAddButtonPressed,
      //   child: const Icon(Icons.add),
      // ),
    );
  }

  // void _onAddButtonPressed() {
  //   final currentIndex = _tabController.index;
  //   logger.info('Add button pressed: tabIndex={}', [currentIndex]);
  //
  //   try {
  //     switch (currentIndex) {
  //       case 1:
  //         _showAddAppointmentDialog();
  //         break;
  //       case 2:
  //         _showAddPaymentDialog();
  //         break;
  //       case 3:
  //         _showAddImageDialog();
  //         break;
  //       case 7:
  //         _showAddSubscriptionDialog();
  //         break;
  //       case 6:
  //         DialogUtils.openInfo(
  //           context,
  //           title: 'Bilgi',
  //           message: 'Ekleme yapmak için Yeni Diyet Ekle butonunu kullanınız.',
  //         );
  //         break;
  //       default:
  //         DialogUtils.openError(
  //           context,
  //           title: 'Uyarı',
  //           message: 'Bu sekme için ekleme bu butondan yapılamaz.',
  //         );
  //     }
  //   } catch (e) {
  //     logger.err('Error while handling add button: {}', [e]);
  //   }
  // }

  void _showAddDietDialog() {
    showDialog(
      context: context,
      builder: (_) => AddDietDialog(userId: widget.user.userId),
    );
  }

  void _showAddSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AddSubscriptionDialog(
          userId: widget.user.userId,
          onSubscriptionAdded: () {
            logger.info('Subscription added and refreshed for userId={}', [widget.user.userId]);
            // Tabs keep their own state; relevant tabs will react via providers.
          },
        );
      },
    );
  }

  void _showAddAppointmentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AddAppointmentDialog(
          userId: widget.user.userId,
          onAppointmentAdded: () {
            logger.info('Appointment added for userId={}', [widget.user.userId]);
          },
        );
      },
    );
  }

  void _showAddPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AddPaymentDialog(
          userId: widget.user.userId,
          onPaymentAdded: () {
            logger.info('Payment added for userId={}', [widget.user.userId]);
          },
        );
      },
    );
  }

  void _showAddImageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AddImageDialog(
          userId: widget.user.userId,
          onImageAdded: () {
            logger.info('Image added for userId={}', [widget.user.userId]);
          },
        );
      },
    );
  }
}
