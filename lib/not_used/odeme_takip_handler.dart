// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:excel/excel.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
//
// import '../models/logger.dart';
// import '../models/user_model.dart';
// import '../models/appointment_model.dart';
// import '../models/payment_model.dart';
// import '../providers/appointment_manager.dart';
// import '../providers/payment_provider.dart';
// import '../utils/dialog_utils.dart';
// import '../widgets/app_bar_with_back.dart';
//
// final Logger log = Logger.forClass(OdemeTakipFileHandlerPage);
//
// class OdemeTakipFileHandlerPage extends StatefulWidget {
//   const OdemeTakipFileHandlerPage({super.key});
//
//   @override
//   State<OdemeTakipFileHandlerPage> createState() =>
//       _OdemeTakipFileHandlerPageState();
// }
//
// class _OdemeTakipFileHandlerPageState extends State<OdemeTakipFileHandlerPage> {
//   Map<String, String> _userMap = {};
//   String? _selectedUser;
//   String _parseLog = 'No file parsed yet.';
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchUserList();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBarWithBack(
//         title: 'Ödeme Takip Sistemi',
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _loadData,
//             tooltip: 'Yenile',
//           ),
//         ],
//       ),
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             DropdownButton<String>(
//               value: _selectedUser,
//               hint: const Text('Select a User'),
//               onChanged: (String? newValue) {
//                 setState(() {
//                   _selectedUser = newValue;
//                 });
//               },
//               items: _userMap.entries.map((entry) {
//                 return DropdownMenuItem<String>(
//                   value: entry.key,
//                   child: Text(entry.value),
//                 );
//               }).toList(),
//             ),
//             ElevatedButton(
//               onPressed: _pickAndParseXlsxFile,
//               child: const Text('Pick XLSX and Parse'),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               _parseLog,
//               textAlign: TextAlign.center,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Future<void> _loadData() async {
//     setState(() {
//       _parseLog = 'Veriler yenileniyor...';
//     });
//
//     await _fetchUserList();
//
//     setState(() {
//       _parseLog = 'Veriler yenilendi.';
//     });
//   }
//
//   Future<void> _fetchUserList() async {
//     try {
//       final snapshot =
//           await FirebaseFirestore.instance.collection('users').get();
//       setState(() {
//         _userMap = {
//           for (var doc in snapshot.docs)
//             doc.id: UserModel.fromDocument(doc).name
//         };
//       });
//     } catch (e) {
//       log.err('Error fetching user list: {}', [e]);
//       _showSnackbar('Error fetching user list.');
//     }
//   }
//
//   Future<void> _pickAndParseXlsxFile() async {
//     if (_selectedUser == null) {
//       _showSnackbar('Please select a user first.');
//       return;
//     }
//
//     FilePickerResult? result = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['xlsx'],
//     );
//
//     if (result == null) {
//       log.info("No file selected");
//       _showSnackbar('No file selected.');
//       return;
//     }
//
//     try {
//       File file = File(result.files.single.path!);
//       var bytes = await file.readAsBytes();
//       var excel = Excel.decodeBytes(bytes);
//
//       // Take the first sheet
//       var sheetName = excel.tables.keys.first;
//       var table = excel.tables[sheetName];
//
//       // We will accumulate a small text log to show on screen
//       StringBuffer sb = StringBuffer('Parsing results:\n');
//
//       // Use Providers for Payment and Appointment
//       final paymentProvider =
//           Provider.of<PaymentProvider>(context, listen: false);
//       final appointmentManager =
//           Provider.of<AppointmentManager>(context, listen: false);
//
//       // Go through each row, skipping header row if needed
//       setState(() {
//         _parseLog = 'İşlem sürüyor, lütfen bekleyin.';
//       });
//       for (int i = 0; i < table!.rows.length; i++) {
//         var row = table.rows[i];
//         // If row is too short, skip
//         if (row.length < 5) continue;
//
//         // Column0 might have "ÜCRET:" ...
//         var firstCell = row[0]?.value?.toString().trim() ?? '';
//         if (firstCell.isEmpty) continue;
//
//         // Attempt to parse a number from "ÜCRET:XYZ"
//         double? parsedPrice;
//         if (firstCell.contains('ÜCRET:')) {
//           String pricePart =
//               firstCell.replaceRange(0, 'ÜCRET:'.length, '').trim();
//           // Attempt to parse double
//           parsedPrice = double.tryParse(pricePart);
//         }
//
//         // Gather up to 4 appointment date columns
//         // row[1] => dateOfAppt1, row[2], row[3], row[4]
//         List<String> dateStrings = [];
//         for (int d = 1; d < 5; d++)
//           dateStrings.add(row[d]?.value?.toString().trim() ?? '');
//         print('**********');
//         print(dateStrings);
//         // For each date, create an appointment if we can parse it as a date
//         List<DateTime> validDates = [];
//         for (var ds in dateStrings) {
//           // If the cell is empty or not parseable, skip
//           if (ds.isEmpty) continue;
//           DateTime? dt = _tryParseDate(ds);
//           if (dt != null) {
//             validDates.add(dt);
//           }
//           // else
//           //   throw Exception('Tarihlerde hata var. Formatı kontrol ediniz.');
//         }
//
//         // If we have validDates, create appointments
//         for (var dt in validDates) {
//           // Create the appointment
//           AppointmentModel appt = AppointmentModel(
//             appointmentId: FirebaseFirestore.instance
//                 .collection('users')
//                 .doc(_selectedUser!)
//                 .collection('appointments')
//                 .doc()
//                 .id,
//             userId: _selectedUser!,
//             subscriptionId: null,
//             meetingType: MeetingType.f2f, // or MeetingType.online if you prefer
//             appointmentDateTime: dt,
//             status: AppointmentStatus.scheduled,
//             notes: 'xlsx',
//             createDate: DateTime.now(),
//             createUser: 'admin',
//           );
//           await appointmentManager.addAppointment(appt);
//
//           sb.writeln('Appointment created for ${dt.toString()}');
//         }
//
//         // If we have a parsedPrice and there's at least one valid date,
//         // then we create a payment on the dateOfAppt1
//         // (the first date) as per your description
//         if (parsedPrice != null && validDates.isNotEmpty) {
//           // Payment date = the first valid date
//           DateTime paymentDate = validDates.first;
//
//           await paymentProvider.addPayment(
//               userId: _selectedUser!,
//               amount: parsedPrice,
//               paymentDate: paymentDate,
//               status: PaymentStatus.completed,
//               notes: 'xlsx');
//
//           sb.writeln(
//               'Payment of $parsedPrice created on ${paymentDate.toString()}');
//         }
//       }
//       print(sb.toString());
//       setState(() {
//         _parseLog = 'İşlem başarıyla tamamlandı.';
//       });
//       _showSnackbar('XLSX parsed and data uploaded successfully.');
//     } catch (e) {
//       setState(() {
//         _parseLog = 'Error: $e';
//       });
//       log.err('Error parsing XLSX: {}', [e]);
//       _showSnackbar('Error parsing XLSX: $e');
//     }
//   }
//
//   DateTime? _tryParseDate(String input) {
//     print(' tried parsing:$input');
//
//     // Check if input is a numeric string (Excel date serial number)
//     if (RegExp(r'^\d+(\.\d+)?$').hasMatch(input)) {
//       double? numericValue = double.tryParse(input);
//       if (numericValue != null && numericValue > 10000) {
//         try {
//           // Excel dates: Days since December 30, 1899 (Excel's epoch)
//           // But Excel has a leap year bug, thinking 1900 was a leap year
//           final excelEpoch = DateTime(1899, 12, 30);
//           return excelEpoch.add(Duration(days: numericValue.toInt()));
//         } catch (e) {
//           print('Error parsing Excel numeric date: $e');
//         }
//       }
//     }
//
//     // Attempt standard date formats
//     // Adjust or expand as needed (dd.MM.yyyy, dd/MM/yyyy, yyyy-MM-dd, etc.)
//     List<String> formats = ['dd.MM.yyyy', 'yyyy.MM.dd', 'd.M.yyyy'];
//     for (var fmt in formats) {
//       try {
//         return DateTime.parse(input);
//       } catch (_) {
//         // ignore
//       }
//     }
//
//     // If none of these formats work, return null
//     return null;
//   }
//
//   Future<void> _showSnackbar(String message) async { //TODO
//     await DialogUtils.openInfo(
//       context,
//       title: 'Bilgi',
//       message: message,
//     );
//   }
// }
