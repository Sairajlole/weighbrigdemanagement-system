import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class QueueItem {
  final String id;
  final QueueType type;
  final QueueItemStatus status;
  final String weighmentId;
  final String sessionId;
  final int retryCount;
  final int maxRetries;
  final DateTime? lastRetryTime;
  final String? errorMessage;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  QueueItem({
    required this.id,
    required this.type,
    required this.status,
    required this.weighmentId,
    required this.sessionId,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.lastRetryTime,
    this.errorMessage,
    this.payload,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'status': status.name,
      'weighmentId': weighmentId,
      'sessionId': sessionId,
      'retryCount': retryCount,
      'maxRetries': maxRetries,
      'lastRetryTime': lastRetryTime != null ? Timestamp.fromDate(lastRetryTime!) : null,
      'errorMessage': errorMessage,
      'payload': payload,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory QueueItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QueueItem(
      id: doc.id,
      type: QueueType.values.byName(data['type'] ?? 'print'),
      status: QueueItemStatus.values.byName(data['status'] ?? 'pending'),
      weighmentId: data['weighmentId'] ?? '',
      sessionId: data['sessionId'] ?? '',
      retryCount: (data['retryCount'] as num?)?.toInt() ?? 0,
      maxRetries: (data['maxRetries'] as num?)?.toInt() ?? 3,
      lastRetryTime: (data['lastRetryTime'] as Timestamp?)?.toDate(),
      errorMessage: data['errorMessage'],
      payload: data['payload'] as Map<String, dynamic>?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  QueueItem copyWith({
    QueueItemStatus? status,
    int? retryCount,
    DateTime? lastRetryTime,
    String? errorMessage,
  }) {
    return QueueItem(
      id: id,
      type: type,
      status: status ?? this.status,
      weighmentId: weighmentId,
      sessionId: sessionId,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries,
      lastRetryTime: lastRetryTime ?? this.lastRetryTime,
      errorMessage: errorMessage ?? this.errorMessage,
      payload: payload,
      createdAt: createdAt,
    );
  }
}
