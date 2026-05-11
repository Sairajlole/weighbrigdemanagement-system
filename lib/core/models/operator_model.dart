import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class Operator {
  final String id;
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final String companyId;
  final String? photoUrl;
  final bool isVerified;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  Operator({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.companyId,
    this.photoUrl,
    this.isVerified = false,
    this.isActive = true,
    required this.createdAt,
    this.lastLoginAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.name,
      'companyId': companyId,
      'photoUrl': photoUrl,
      'isVerified': isVerified,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
    };
  }

  factory Operator.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Operator(
      id: doc.id,
      uid: data['uid'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'],
      role: UserRole.values.byName(data['role'] ?? 'operator'),
      companyId: data['companyId'] ?? '',
      photoUrl: data['photoUrl'],
      isVerified: data['isVerified'] ?? false,
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
    );
  }
}
