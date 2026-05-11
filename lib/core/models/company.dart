import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  final String id;
  final String name;
  final String? address;
  final String? email;
  final String? gstin;
  final String? logoUrl;
  final String adminUid;
  final String linkageCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Company({
    required this.id,
    required this.name,
    this.address,
    this.email,
    this.gstin,
    this.logoUrl,
    required this.adminUid,
    required this.linkageCode,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'address': address,
      'email': email,
      'gstin': gstin,
      'logoUrl': logoUrl,
      'adminUid': adminUid,
      'linkageCode': linkageCode,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Company.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Company(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'],
      email: data['email'],
      gstin: data['gstin'],
      logoUrl: data['logoUrl'],
      adminUid: data['adminUid'] ?? '',
      linkageCode: data['linkageCode'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }
}
