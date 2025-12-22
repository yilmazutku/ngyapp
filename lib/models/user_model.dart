import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String userId;
  final String name;
  final String email;
  final String password; // For Firebase user creation
  final String role; // 'admin' or 'customer'
  final DateTime createDate; // Renamed from createdAt
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;
  final String surname;
  final int? age;
  final String? reference;
  final String? notes;

  UserModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    DateTime? createDate, // Renamed from createdAt
    this.createUser,
    this.updateDate,
    this.updateUser,
    required this.surname,
    this.age,
    this.reference,
    this.notes,
  }) : createDate = createDate ?? DateTime.now(); // Use provided or current time

  factory UserModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      userId: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      password: '', // Password should not be stored in Firestore
      role: data['role'] ?? 'customer',
      // Handle both legacy field name and new field name
      createDate: data['createDate'] != null 
          ? (data['createDate'] as Timestamp).toDate() 
          : (data['createdAt'] != null 
              ? (data['createdAt'] as Timestamp).toDate() 
              : DateTime.now()),
      createUser: data['createUser'],
      updateDate: data['updateDate'] != null ? (data['updateDate'] as Timestamp).toDate() : null,
      updateUser: data['updateUser'],
      surname: data['surname'] ?? '',
      age: data['age'],
      reference: data['reference'],
      notes: data['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'role': role,
      'createDate': Timestamp.fromDate(createDate), // Renamed from createdAt
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
       'surname': surname,
      if (age != null) 'age': age,
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
    };
  }

  @override
  String toString() {
    return 'UserModel{userId: $userId, name: $name, email: $email, role: $role, createDate: $createDate, createUser: $createUser, updateDate: $updateDate, updateUser: $updateUser, surname: $surname, age: $age, reference: $reference, notes: $notes}';
  }
}
