import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/services/billing_service.dart';
import 'package:weighbridgemanagement/shared/services/google_sheets_service.dart';
import 'package:weighbridgemanagement/shared/services/offline_queue_service.dart';
import 'package:weighbridgemanagement/shared/services/sticker_print_service.dart';
import 'package:weighbridgemanagement/shared/services/whatsapp_service.dart';

class PostWeighmentResult {
  final bool sheetsSuccess;
  final bool whatsappSuccess;
  final bool billingSuccess;
  final bool stickerGenerated;
  final String? error;

  const PostWeighmentResult({
    this.sheetsSuccess = false,
    this.whatsappSuccess = false,
    this.billingSuccess = false,
    this.stickerGenerated = false,
    this.error,
  });
}

class PostWeighmentService {
  final GoogleSheetsService? _sheets;
  final WhatsAppService? _whatsapp;
  final BillingService? _billing;
  final StickerPrintService? _sticker;
  final OfflineQueueService _queue;

  PostWeighmentService({
    GoogleSheetsService? sheets,
    WhatsAppService? whatsapp,
    BillingService? billing,
    StickerPrintService? sticker,
    required OfflineQueueService queue,
  }) : _sheets = sheets,
       _whatsapp = whatsapp,
       _billing = billing,
       _sticker = sticker,
       _queue = queue;

  Future<PostWeighmentResult> execute(Map<String, dynamic> weighmentData) async {
    bool sheetsOk = false;
    bool whatsappOk = false;
    bool billingOk = false;
    bool stickerOk = false;

    // Google Sheets sync
    if (_sheets != null && _sheets.config.isConfigured) {
      try {
        sheetsOk = await _sheets.appendRow(weighmentData);
        if (!sheetsOk) {
          await _queue.enqueueWeighment({'_retryType': 'sheets', ...weighmentData});
        }
      } catch (e) {
        debugPrint('Sheets sync failed: $e');
        await _queue.enqueueWeighment({'_retryType': 'sheets', ...weighmentData});
      }
    }

    // WhatsApp notification
    if (_whatsapp != null && _whatsapp.config.isConfigured) {
      try {
        whatsappOk = await _whatsapp.sendWeighmentNotification(weighmentData);
      } catch (e) {
        debugPrint('WhatsApp notification failed: $e');
      }
    }

    // Billing webhook
    if (_billing != null && _billing.config.isConfigured) {
      try {
        billingOk = await _billing.postWeighment(weighmentData);
        if (!billingOk) {
          await _queue.enqueueWeighment({'_retryType': 'billing', ...weighmentData});
        }
      } catch (e) {
        debugPrint('Billing webhook failed: $e');
        await _queue.enqueueWeighment({'_retryType': 'billing', ...weighmentData});
      }
    }

    // Sticker generation
    if (_sticker != null && _sticker.config.enabled) {
      try {
        final pdf = await _sticker.generateSticker(weighmentData);
        stickerOk = pdf != null;
      } catch (e) {
        debugPrint('Sticker generation failed: $e');
      }
    }

    return PostWeighmentResult(
      sheetsSuccess: sheetsOk,
      whatsappSuccess: whatsappOk,
      billingSuccess: billingOk,
      stickerGenerated: stickerOk,
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final googleSheetsServiceProvider = Provider<GoogleSheetsService?>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final sheetsData = data['googleSheets'] as Map<String, dynamic>? ?? {};
  final config = SheetsConfig.fromMap(sheetsData);
  if (!config.isConfigured) return null;
  return GoogleSheetsService(config);
});

final whatsappServiceProvider = Provider<WhatsAppService?>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final waData = data['whatsapp'] as Map<String, dynamic>? ?? {};
  final config = WhatsAppConfig.fromMap(waData);
  if (!config.isConfigured) return null;
  return WhatsAppService(config);
});

final billingServiceProvider = Provider<BillingService?>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final billingData = data['billing'] as Map<String, dynamic>? ?? {};
  final config = BillingConfig.fromMap(billingData);
  if (!config.isConfigured) return null;
  return BillingService(config);
});

final stickerPrintServiceProvider = Provider<StickerPrintService?>((ref) {
  final configAsync = ref.watch(integrationsConfigProvider);
  final data = configAsync.valueOrNull ?? {};
  final stickerData = data['sticker'] as Map<String, dynamic>? ?? {};
  final config = StickerConfig.fromMap(stickerData);
  if (!config.enabled) return null;
  return StickerPrintService(config);
});

final postWeighmentServiceProvider = Provider<PostWeighmentService>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  final queue = OfflineQueueService(paths: paths);

  return PostWeighmentService(
    sheets: ref.watch(googleSheetsServiceProvider),
    whatsapp: ref.watch(whatsappServiceProvider),
    billing: ref.watch(billingServiceProvider),
    sticker: ref.watch(stickerPrintServiceProvider),
    queue: queue,
  );
});
