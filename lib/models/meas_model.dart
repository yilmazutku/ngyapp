import 'package:cloud_firestore/cloud_firestore.dart';

/// Enum to track the state of measurement changes
enum MeasurementChangeState {
  unchanged,
  added,
  modified,
  deleted,
}

class MeasurementModel {
  String measurementId;
  DateTime measDate;
  double? chest;
  double? back;
  double? waist;
  double? hips;
  double? leg;
  double? arm;
  double? weight;
  double? fatKg;
  String? hungerStatus;
  String? constipation;
  String? other;
  int? calorie;
  MeasurementChangeState changeState;
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  MeasurementModel({
    required this.measurementId,
    required this.measDate,
    this.chest,
    this.back,
    this.waist,
    this.hips,
    this.leg,
    this.arm,
    this.weight,
    this.fatKg,
    this.hungerStatus,
    this.constipation,
    this.other,
    this.calorie,
    this.changeState = MeasurementChangeState.unchanged,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
  }) : createDate = createDate ?? DateTime.now();

  // Convert MeasurementModel to a Firestore-compatible map
  Map<String, dynamic> toMap() {
    return {
      'measurementId': measurementId,
      'date': Timestamp.fromDate(measDate),
      if (chest != null) 'chest': chest,
      if (back != null) 'back': back,
      if (waist != null) 'waist': waist,
      if (hips != null) 'hips': hips,
      if (leg != null) 'leg': leg,
      if (arm != null) 'arm': arm,
      if (weight != null) 'weight': weight,
      if (fatKg != null) 'fatKg': fatKg,
      if (hungerStatus != null) 'hungerStatus': hungerStatus,
      if (constipation != null) 'constipation': constipation,
      if (other != null) 'other': other,
      if (calorie != null) 'calorie': calorie,
      'createDate': Timestamp.fromDate(createDate),
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
    };
  }

  // Create a MeasurementModel from a Firestore document
  factory MeasurementModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MeasurementModel(
      measurementId: doc.id,
      measDate: (data['date'] as Timestamp).toDate(),
      chest: data['chest']?.toDouble(),
      back: data['back']?.toDouble(),
      waist: data['waist']?.toDouble(),
      hips: data['hips']?.toDouble(),
      leg: data['leg']?.toDouble(),
      arm: data['arm']?.toDouble(),
      weight: data['weight']?.toDouble(),
      fatKg: data['fatKg']?.toDouble(),
      hungerStatus: data['hungerStatus'],
      constipation: data['constipation'],
      other: data['other'],
      calorie: data['calorie']?.toInt(),
      createDate: data['createDate'] != null
          ? (data['createDate'] as Timestamp).toDate()
          : null,
      createUser: data['createUser'],
      updateDate: data['updateDate'] != null
          ? (data['updateDate'] as Timestamp).toDate()
          : null,
      updateUser: data['updateUser'],
    );
  }

  @override
  String toString() {
    return '''MeasurementModel {
  date: $measDate (${measDate.toIso8601String()}),
  documentId: $measurementId,
  changeState: $changeState,
  weight: $weight,
  chest: $chest,
  back: $back,
  waist: $waist,
  hips: $hips,
  leg: $leg,
  arm: $arm,
  fatKg: $fatKg,
  calorie: $calorie,
  hungerStatus: $hungerStatus,
  constipation: $constipation,
  other: $other,
  createDate: $createDate,
  createUser: $createUser,
  updateDate: $updateDate,
  updateUser: $updateUser
}''';
  }
}
