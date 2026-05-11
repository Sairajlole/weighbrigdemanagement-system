import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/core/models/weighment.dart';
import 'package:weighbridgemanagement/core/models/customer.dart';
import 'package:weighbridgemanagement/core/models/operator_model.dart';
import 'package:weighbridgemanagement/core/models/company.dart';
import 'package:weighbridgemanagement/core/models/queue_item.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collections
  CollectionReference get _weighments => _db.collection('weighments');
  CollectionReference get _customers => _db.collection('customers');
  CollectionReference get _operators => _db.collection('operators');
  CollectionReference get _companies => _db.collection('companies');
  CollectionReference get _queues => _db.collection('queues');

  // ==================== WEIGHMENTS ====================

  Future<String> createWeighment(Weighment weighment) async {
    final docRef = await _weighments.add(weighment.toFirestore());
    return docRef.id;
  }

  Future<void> updateWeighment(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.now();
    await _weighments.doc(id).update(data);
  }

  Stream<List<Weighment>> streamWeighments({int limit = 50}) {
    return _weighments
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Weighment.fromFirestore(d)).toList());
  }

  Stream<Weighment?> streamWeighment(String id) {
    return _weighments.doc(id).snapshots().map(
          (snap) => snap.exists ? Weighment.fromFirestore(snap) : null,
        );
  }

  Future<List<Weighment>> getTodaysWeighments(String companyId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final snap = await _weighments
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => Weighment.fromFirestore(d)).toList();
  }

  // ==================== CUSTOMERS ====================

  Future<String> createCustomer(Customer customer) async {
    final docRef = await _customers.add(customer.toFirestore());
    return docRef.id;
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.now();
    await _customers.doc(id).update(data);
  }

  Stream<List<Customer>> streamCustomers() {
    return _customers
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Customer.fromFirestore(d)).toList());
  }

  Future<Customer?> findCustomerByPhone(String phone) async {
    final snap = await _customers.where('phone', isEqualTo: phone).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Customer.fromFirestore(snap.docs.first);
  }

  // ==================== OPERATORS ====================

  Future<String> createOperator(Operator operator) async {
    final docRef = await _operators.add(operator.toFirestore());
    return docRef.id;
  }

  Future<Operator?> getOperatorByUid(String uid) async {
    final snap = await _operators.where('uid', isEqualTo: uid).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Operator.fromFirestore(snap.docs.first);
  }

  Stream<List<Operator>> streamOperators(String companyId) {
    return _operators
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Operator.fromFirestore(d)).toList());
  }

  // ==================== COMPANIES ====================

  Future<String> createCompany(Company company) async {
    final docRef = await _companies.add(company.toFirestore());
    return docRef.id;
  }

  Future<Company?> getCompanyByLinkageCode(String code) async {
    final snap = await _companies.where('linkageCode', isEqualTo: code).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Company.fromFirestore(snap.docs.first);
  }

  Future<Company?> getCompanyByAdmin(String adminUid) async {
    final snap = await _companies.where('adminUid', isEqualTo: adminUid).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Company.fromFirestore(snap.docs.first);
  }

  // ==================== QUEUES ====================

  Future<String> addToQueue(QueueItem item) async {
    final docRef = await _queues.add(item.toFirestore());
    return docRef.id;
  }

  Future<void> updateQueueItem(String id, Map<String, dynamic> data) async {
    await _queues.doc(id).update(data);
  }

  Stream<List<QueueItem>> streamPendingQueues() {
    return _queues
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => QueueItem.fromFirestore(d)).toList());
  }

  // ==================== RST ====================

  Future<int> getNextRstNumber(String companyId) async {
    final counterRef = _db.collection('counters').doc('rst_$companyId');
    final result = await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);
      int current = 0;
      if (snapshot.exists) {
        current = (snapshot.data() as Map<String, dynamic>)['value'] as int;
      }
      final next = current + 1;
      transaction.set(counterRef, {'value': next});
      return next;
    });
    return result;
  }
}
