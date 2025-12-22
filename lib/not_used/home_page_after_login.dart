// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:untitled/models/subs_model.dart';
// import 'package:untitled/pages/reset_password_page.dart';
// import 'package:untitled/pages/user_past_appointments_page.dart';
// import '../models/logger.dart';
// import '../pages/admin_appointments_page.dart';
// import '../pages/admin_images_page.dart';
// import '../pages/appointments_page.dart';
// import '../file_handlers/file_handler_page.dart';
// import '../pages/meal_upload_page.dart';
// import 'admin_create_user_page.dart';
// import 'admin_timeslots_page.dart';
//
// final Logger logger = Logger.forClass(HomePageAfterLogin);
//
// class HomePageAfterLogin extends StatelessWidget {
//   final String userId;
//
//   const HomePageAfterLogin({super.key, required this.userId});
//
//   Future<String?> getCurrentSubscriptionId(String userId) async {
//     final subscriptionsCollection = FirebaseFirestore.instance
//         .collection('users')
//         .doc(userId)
//         .collection('subscriptions');
//
//     final querySnapshot = await subscriptionsCollection
//         .where('status', isEqualTo: SubActiveStatus.active.label)
//         .orderBy('startDate', descending: true)
//         .limit(1)
//         .get();
//
//     if (querySnapshot.docs.isNotEmpty) {
//       final doc = querySnapshot.docs.first;
//       return doc.id;
//     } else {
//       return null;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     logger.info('Building HomePageAfterLogin...');
//     return Scaffold(
//       appBar: AppBar(title: const Text('Ana Sayfa')),
//       body: ListView(
//         padding: EdgeInsets.zero,
//         children: <Widget>[
//           ListTile(
//             leading: const Icon(Icons.food_bank),
//             title: const Text('Planım'),
//             onTap: () async {
//               final subscriptionId = await getCurrentSubscriptionId(userId);
//
//               if (subscriptionId == null) {
//                 if (!context.mounted) return;
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   const SnackBar(content: Text('No active subscription found')),
//                 );
//                 return;
//               }
//               if (!context.mounted) return;
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => MealUploadPage(
//                     userId: userId,
//                     subscriptionId: subscriptionId,
//                   ),
//                 ),
//               );
//             },
//           ),
//           // ListTile for "Randevu"
//           ListTile(
//             leading: const Icon(Icons.calendar_today),
//             title: const Text('Randevu'),
//             onTap: () async {
//               final subscriptionId = await getCurrentSubscriptionId(userId);
//
//               if (subscriptionId == null) {
//                 if (!context.mounted) return;
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   const SnackBar(content: Text('No active subscription found')),
//                 );
//                 return;
//               }
//               if (!context.mounted) return;
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => AppointmentsPage(
//                     userId: userId,
//                     subscriptionId: subscriptionId,
//                   ),
//                 ),
//               );
//             },
//           ),
//           ListTile(
//             leading: const Icon(Icons.calendar_today),
//             title: const Text('Geçmiş Randevularım'),
//             onTap: () async {
//               // final subscriptionId = await getCurrentSubscriptionId(userId);
//               //
//               // if (subscriptionId == null) {
//               //   if (!context.mounted) return;
//               //   ScaffoldMessenger.of(context).showSnackBar(
//               //     const SnackBar(content: Text('No active subscription found')),
//               //   );
//               //   return;
//               // }
//               // if (!context.mounted) return;
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => PastAppointmentsPage(
//                     userId: userId,
//                   ),
//                 ),
//               );
//             },
//           ),
//           ListTile(
//             leading: const Icon(Icons.calendar_today),
//             title: const Text('Admin timeslots'),
//             onTap: () async {
//               // final subscriptionId = await getCurrentSubscriptionId(userId);
//               //
//               // if (subscriptionId == null) {
//               //   if (!context.mounted) return;
//               //   ScaffoldMessenger.of(context).showSnackBar(
//               //     const SnackBar(content: Text('No active subscription found')),
//               //   );
//               //   return;
//               // }
//               // if (!context.mounted) return;
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => const AdminTimeSlotsPage(
//
//                   ),
//                 ),
//               );
//             },
//           ),
//
//           // ListTile for "Şifre Sıfırla"
//           ListTile(
//             leading: const Icon(Icons.lock),
//             title: const Text('Şifre Sıfırla'),
//             onTap: () => Navigator.push(
//               context,
//               MaterialPageRoute(
//                 builder: (context) => ResetPasswordPage(
//                   email: FirebaseAuth.instance.currentUser?.email ?? '',
//                 ),
//               ),
//             ),
//           ),
//           // Admin-specific options
//           // Check if the user is an admin
//           if (userId == 'ADMIN_USER_ID') ...[ //TODO admin anlamak
//             ListTile(
//               leading: const Icon(Icons.assignment),
//               title: const Text('Admin Appointments'),
//               onTap: () => Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => const AdminAppointmentsPage()),
//               ),
//             ),
//             ListTile(
//               leading: const Icon(Icons.image),
//               title: const Text('Admin Images'),
//               onTap: () => Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => const AdminImages()),
//               ),
//             ),
//             ListTile(
//               leading: const Icon(Icons.list),
//               title: const Text('Admin Liste'),
//               onTap: () => Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => const FileHandlerPage()),
//               ),
//             ),
//             ListTile(
//               leading: const Icon(Icons.person_add),
//               title: const Text('Admin Kullanıcı oluştur'),
//               onTap: () => Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => const CreateUserPage()),
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
// }
