import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:weighbridgemanagement/shared/services/digilocker_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

enum DigiLockerStatus { idle, loading, awaitingConsent, processing, verified, failed }

class DigiLockerVerifyCard extends ConsumerStatefulWidget {
  final String purpose;
  final String? gstin;
  final String? companyId;
  final ValueChanged<DigiLockerVerificationResult>? onVerified;
  final ValueChanged<StakeholderResult>? onStakeholderResult;

  const DigiLockerVerifyCard({
    super.key,
    required this.purpose,
    this.gstin,
    this.companyId,
    this.onVerified,
    this.onStakeholderResult,
  });

  @override
  ConsumerState<DigiLockerVerifyCard> createState() => _DigiLockerVerifyCardState();
}

class _DigiLockerVerifyCardState extends ConsumerState<DigiLockerVerifyCard> {
  DigiLockerStatus _status = DigiLockerStatus.idle;
  String? _consentId;
  String? _error;
  DigiLockerVerificationResult? _result;
  StakeholderResult? _stakeholderResult;

  Future<void> _startVerification() async {
    setState(() { _status = DigiLockerStatus.loading; _error = null; });

    try {
      final service = ref.read(digilockerServiceProvider);
      final consent = await service.initiateConsent(
        purpose: widget.purpose,
        redirectUrl: 'https://tulanam.com/digilocker/callback',
        companyId: widget.companyId,
      );
      _consentId = consent.consentId;

      // Test mode: URL contains test=true, skip browser and auto-process
      if (consent.url.contains('test=true')) {
        await _checkStatus();
        return;
      }

      setState(() => _status = DigiLockerStatus.awaitingConsent);

      final uri = Uri.parse(consent.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      setState(() { _status = DigiLockerStatus.failed; _error = e.toString(); });
    }
  }

  Future<void> _checkStatus() async {
    if (_consentId == null) return;
    setState(() { _status = DigiLockerStatus.processing; _error = null; });

    try {
      final service = ref.read(digilockerServiceProvider);
      final result = await service.processConsent(_consentId!);
      _result = result;

      if (result.verified) {
        widget.onVerified?.call(result);

        if (widget.gstin != null) {
          final stakeholder = await service.verifyStakeholder(
            consentId: _consentId!,
            gstin: widget.gstin!,
            companyId: widget.companyId,
          );
          _stakeholderResult = stakeholder;
          widget.onStakeholderResult?.call(stakeholder);
        }

        setState(() => _status = DigiLockerStatus.verified);
      } else {
        setState(() { _status = DigiLockerStatus.failed; _error = result.reason ?? 'Verification incomplete'; });
      }
    } catch (e) {
      setState(() { _status = DigiLockerStatus.failed; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: _status == DigiLockerStatus.verified
            ? AppTheme.successColor.withValues(alpha: 0.04)
            : scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: _status == DigiLockerStatus.verified
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _status == DigiLockerStatus.verified ? Icons.verified_rounded : Icons.fingerprint_rounded,
                size: 20,
                color: _status == DigiLockerStatus.verified ? AppTheme.successColor : AppTheme.brandTeal,
              ),
              SizedBox(width: AppSpacing.sm),
              Text(
                'DigiLocker Verification',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_status == DigiLockerStatus.verified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.1),
                    borderRadius: AppRadius.chip,
                  ),
                  child: Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                ),
            ],
          ),
          SizedBox(height: AppSpacing.md),

          if (_status == DigiLockerStatus.idle) ...[
            Text(
              'Verify your identity securely through DigiLocker. Documents are fetched directly from government issuers.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startVerification,
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Verify with DigiLocker'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
                ),
              ),
            ),
          ],

          if (_status == DigiLockerStatus.loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            )),

          if (_status == DigiLockerStatus.awaitingConsent) ...[
            Text(
              'DigiLocker consent page opened in your browser. Complete the verification there, then tap the button below.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _checkStatus,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
                ),
                child: const Text('I\'ve completed DigiLocker verification'),
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton(
                onPressed: _startVerification,
                child: Text('Reopen DigiLocker', style: TextStyle(fontSize: 12, color: scheme.primary)),
              ),
            ),
          ],

          if (_status == DigiLockerStatus.processing)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: 12),
                  Text('Fetching verified documents...', style: TextStyle(fontSize: 12)),
                ],
              ),
            )),

          if (_status == DigiLockerStatus.verified && _result != null) ...[
            _buildVerifiedInfo(scheme, text),
          ],

          if (_status == DigiLockerStatus.failed && _error != null) ...[
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.2),
                borderRadius: AppRadius.button,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _startVerification,
                child: const Text('Try Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerifiedInfo(ColorScheme scheme, TextTheme text) {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.photo != null && r.photo!.isNotEmpty)
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: MemoryImage(base64Decode(r.photo!)),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name ?? '', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (r.dob != null)
                      Text('DOB: ${r.dob}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          )
        else if (r.name != null)
          Text(r.name!, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),

        SizedBox(height: AppSpacing.md),
        _infoRow('PAN', r.pan != null ? '${r.pan!.substring(0, 4)}****${r.pan!.substring(8)}' : 'Not available', Icons.check_circle_rounded, scheme),
        SizedBox(height: AppSpacing.xs),
        _infoRow('Aadhaar', r.aadhaarLast4 != null ? '****-****-${r.aadhaarLast4}' : 'Not available', Icons.check_circle_rounded, scheme),

        if (_stakeholderResult != null) ...[
          SizedBox(height: AppSpacing.md),
          Container(
            padding: EdgeInsets.all(10.rs),
            decoration: BoxDecoration(
              color: _stakeholderResult!.isStakeholder
                  ? AppTheme.successColor.withValues(alpha: 0.06)
                  : Colors.orange.withValues(alpha: 0.06),
              borderRadius: AppRadius.button,
              border: Border.all(
                color: _stakeholderResult!.isStakeholder
                    ? AppTheme.successColor.withValues(alpha: 0.2)
                    : Colors.orange.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _stakeholderResult!.isStakeholder ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: _stakeholderResult!.isStakeholder ? AppTheme.successColor : Colors.orange,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _stakeholderResult!.isStakeholder
                        ? 'Confirmed: ${_stakeholderResult!.matchType?.replaceAll('_', ' ') ?? 'stakeholder verified'}'
                        : _stakeholderResult!.details ?? 'Could not verify stakeholder status',
                    style: text.bodySmall?.copyWith(
                      color: _stakeholderResult!.isStakeholder ? AppTheme.successColor : Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value, IconData icon, ColorScheme scheme) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.successColor),
        SizedBox(width: AppSpacing.sm),
        Text('$label: ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
