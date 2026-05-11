import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String? address;
  final String? faceEmbeddingRef;
  final int totalWeighments;
  final double totalNetWeight;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.faceEmbeddingRef,
    this.totalWeighments = 0,
    this.totalNetWeight = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'faceEmbeddingRef': faceEmbeddingRef,
      'totalWeighments': totalWeighments,
      'totalNetWeight': totalNetWeight,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Customer(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'],
      faceEmbeddingRef: data['faceEmbeddingRef'],
      totalWeighments: (data['totalWeighments'] as num?)?.toInt() ?? 0,
      totalNetWeight: (data['totalNetWeight'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Customer copyWith({
    String? name,
    String? phone,
    String? address,
    String? faceEmbeddingRef,
    int? totalWeighments,
    double? totalNetWeight,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      faceEmbeddingRef: faceEmbeddingRef ?? this.faceEmbeddingRef,
      totalWeighments: totalWeighments ?? this.totalWeighments,
      totalNetWeight: totalNetWeight ?? this.totalNetWeight,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
