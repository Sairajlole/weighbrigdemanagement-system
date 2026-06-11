import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:weighbridgemanagement/shared/services/digilocker_service.dart';
import 'package:weighbridgemanagement/shared/services/meon_webview.dart';
import 'package:weighbridgemanagement/shared/widgets/meon_inline_webview.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

enum _Status { idle, launching, embedding, awaitingExternal, polling, verified, failed }

/// Aadhaar identity verification via the Meon DigiLocker gateway.
///
/// Opens the DigiLocker authorization URL in an in-app webview window
/// (desktop), detects the redirect, then polls for the exported Aadhaar data
/// and renders the fetched photo + details. Falls back to an external browser
/// where no webview runtime is available.
class DigiLockerVerifyCard extends ConsumerStatefulWidget {
  final String purpose;

  /// Documents to request. Aadhaar only by default (and enforced server-side).
  final String documents;
  final String? companyId;

  /// Optional name (e.g. GST legal/trade name) to cross-check against the
  /// Aadhaar holder's name. When provided, a match indicator is shown.
  final String? expectedName;

  final ValueChanged<DigiLockerVerificationResult>? onVerified;

  /// Optional content rendered *inside* this card, below the verified identity
  /// summary, once verification succeeds. Used to fold account fields
  /// (email, phone, password…) into the same card as one continuous flow.
  /// When provided, the verified summary is shown compactly (photo + name)
  /// and the fetched Aadhaar/address details are left to the footer.
  final Widget? footer;

  /// A previously-fetched result to render as already-verified, skipping
  /// re-verification (e.g. the user navigated back and returned).
  final DigiLockerVerificationResult? initialResult;

  const DigiLockerVerifyCard({
    super.key,
    required this.purpose,
    this.documents = 'aadhaar',
    this.companyId,
    this.expectedName,
    this.onVerified,
    this.footer,
    this.initialResult,
  });

  @override
  ConsumerState<DigiLockerVerifyCard> createState() => _DigiLockerVerifyCardState();
}

class _DigiLockerVerifyCardState extends ConsumerState<DigiLockerVerifyCard> {
  _Status _status = _Status.idle;
  MeonSession? _session;
  String? _error;
  DigiLockerVerificationResult? _result;
  bool _photoEnlarged = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) {
      _result = widget.initialResult;
      _status = _Status.verified;
    }
  }

  Future<void> _start() async {
    setState(() {
      _status = _Status.launching;
      _error = null;
    });

    try {
      final service = ref.read(digilockerServiceProvider);
      final session = await service.initiate(
        purpose: widget.purpose,
        documents: widget.documents,
        companyId: widget.companyId,
      );
      _session = session;

      // Prefer an inline embedded webview (Windows/macOS) so the DigiLocker
      // page renders right inside the wizard. The webview's onRedirected
      // callback then drives polling. See [_buildEmbeddedWebview].
      final canEmbed = !kIsWeb && (Platform.isWindows || Platform.isMacOS);
      if (canEmbed) {
        if (mounted) setState(() => _status = _Status.embedding);
        return;
      }

      // Otherwise fall back to a separate webview window (e.g. Linux), then to
      // the system browser.
      bool useWebview = false;
      try {
        useWebview = await MeonWebview.isAvailable();
      } catch (_) {
        useWebview = false;
      }

      if (useWebview) {
        final outcome = await MeonWebview.open(
          url: session.url,
          redirectUrl: session.redirectUrl,
        );
        if (!mounted) return;
        if (outcome == MeonWebviewOutcome.redirected) {
          await _pollUntilVerified();
        } else {
          // Window closed — the user may still have completed; try once.
          await _pollUntilVerified(attempts: 2, cancelMessage: 'Verification was cancelled.');
        }
      } else {
        final uri = Uri.parse(session.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (mounted) setState(() => _status = _Status.awaitingExternal);
      }
    } catch (e, stack) {
      debugPrint('[DigiLockerCard] start error: $e\n$stack');
      if (mounted) {
        setState(() {
          _status = _Status.failed;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pollUntilVerified({int attempts = 6, String? cancelMessage}) async {
    final reference = _session?.reference;
    if (reference == null) return;
    setState(() {
      _status = _Status.polling;
      _error = null;
    });

    final service = ref.read(digilockerServiceProvider);
    for (var i = 0; i < attempts; i++) {
      try {
        final result = await service.fetchData(reference);
        if (!mounted) return;
        if (result.verified) {
          _result = result;
          setState(() => _status = _Status.verified);
          widget.onVerified?.call(result);
          return;
        }
      } catch (e) {
        debugPrint('[DigiLockerCard] poll error: $e');
      }
      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }

    if (!mounted) return;
    setState(() {
      _status = _Status.failed;
      _error = cancelMessage ?? 'Could not retrieve your details. Please try again.';
    });
  }

  double _nameMatch(String? a, String? b) {
    if (a == null || b == null) return 0;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    final na = norm(a), nb = norm(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    final ta = na.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    final tb = nb.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final overlap = ta.intersection(tb).length;
    return overlap / (ta.length > tb.length ? ta.length : tb.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final verified = _status == _Status.verified;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: verified
            ? AppTheme.successColor.withValues(alpha: 0.04)
            : scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: verified
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
                verified ? Icons.verified_rounded : Icons.fingerprint_rounded,
                size: 20,
                color: verified ? AppTheme.successColor : AppTheme.brandTeal,
              ),
              SizedBox(width: AppSpacing.sm),
              Text('DigiLocker Verification', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (verified)
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
          ..._buildBody(scheme, text),
        ],
      ),
    );
  }

  List<Widget> _buildBody(ColorScheme scheme, TextTheme text) {
    switch (_status) {
      case _Status.idle:
        return [
          Text(
            'Verify your Aadhaar securely through DigiLocker. Your details are fetched directly from the government issuer.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Verify with DigiLocker'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
              ),
            ),
          ),
        ];

      case _Status.launching:
        return const [
          Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))),
        ];

      case _Status.embedding:
        return _buildEmbeddedWebview(scheme, text);

      case _Status.awaitingExternal:
        return [
          Text(
            'DigiLocker opened in your browser. Complete the verification there, then tap below.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => _pollUntilVerified(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
              ),
              child: const Text("I've completed DigiLocker verification"),
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _start,
              child: Text('Reopen DigiLocker', style: TextStyle(fontSize: 12, color: scheme.primary)),
            ),
          ),
        ];

      case _Status.polling:
        return const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: 12),
                  Text('Fetching your Aadhaar details...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ];

      case _Status.verified:
        return [_buildVerifiedInfo(scheme, text)];

      case _Status.failed:
        return [
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
                  child: Text(_error ?? 'Verification failed',
                      style: text.bodySmall?.copyWith(color: scheme.error), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.md),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _start, child: const Text('Try Again'))),
        ];
    }
  }

  List<Widget> _buildEmbeddedWebview(ColorScheme scheme, TextTheme text) {
    final session = _session;
    if (session == null) return const [SizedBox.shrink()];
    return [
      Text(
        'Sign in to DigiLocker below and approve the Aadhaar request. Your details load automatically once you finish.',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
      ),
      SizedBox(height: AppSpacing.md),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: MeonInlineWebview(
          url: session.url,
          // Sizes itself to each page: compact on sign-in, taller on the
          // consent / document-selection page — clamped, width unchanged.
          minHeight: 380,
          maxHeight: (MediaQuery.of(context).size.height * 0.78).clamp(560.0, 900.0),
          redirectUrl: session.redirectUrl,
          onRedirected: () {
            if (mounted) _pollUntilVerified();
          },
          onError: (msg) {
            debugPrint('[DigiLockerCard] embedded webview error: $msg');
            // The page refused to embed (some gov pages block this) — fall back
            // to a separate window / external browser without losing the session.
            _fallbackFromEmbed();
          },
        ),
      ),
      SizedBox(height: AppSpacing.sm),
      Center(
        child: TextButton(
          onPressed: () => setState(() => _status = _Status.idle),
          child: Text('Cancel', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      ),
    ];
  }

  Future<void> _fallbackFromEmbed() async {
    final session = _session;
    if (session == null || !mounted) return;

    bool useWebview = false;
    try {
      useWebview = await MeonWebview.isAvailable();
    } catch (_) {
      useWebview = false;
    }

    if (useWebview) {
      final outcome = await MeonWebview.open(url: session.url, redirectUrl: session.redirectUrl);
      if (!mounted) return;
      if (outcome == MeonWebviewOutcome.redirected) {
        await _pollUntilVerified();
      } else {
        await _pollUntilVerified(attempts: 2, cancelMessage: 'Verification was cancelled.');
      }
      return;
    }

    final uri = Uri.parse(session.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) setState(() => _status = _Status.awaitingExternal);
  }

  Widget _buildVerifiedInfo(ColorScheme scheme, TextTheme text) {
    final r = _result!;
    final hasPhoto = r.photoUrl != null && r.photoUrl!.isNotEmpty;
    final hasFooter = widget.footer != null;

    // Aadhaar + address detail lines. When the photo is enlarged they move up
    // beside it (below the name); otherwise they sit below the identity row.
    final detailRows = <Widget>[
      _infoRow('Aadhaar', r.aadhaarLast4 != null ? 'XXXX-XXXX-${r.aadhaarLast4}' : 'Not available', scheme, showTick: false),
      if (r.address != null && r.address!.trim().isNotEmpty) ...[
        SizedBox(height: AppSpacing.xs),
        _infoRow('Address', r.address!, scheme, multiline: true, showTick: false),
      ],
    ];

    final identityRow = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: _photoEnlarged ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
        MouseRegion(
          cursor: hasPhoto ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: hasPhoto ? () => setState(() => _photoEnlarged = !_photoEnlarged) : null,
            child: Container(
              alignment: Alignment.center,
              // Enlarged: fixed width, height stretches to match the text column
              // (name → last address line) via IntrinsicHeight. Not animated here
              // (a null↔fixed height tween overflows); the outer AnimatedSize
              // smooths the overall reflow instead.
              width: _photoEnlarged ? 130 : 48,
              height: _photoEnlarged ? null : 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.surfaceContainerHighest,
                image: hasPhoto
                    ? DecorationImage(image: NetworkImage(r.photoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: hasPhoto
                  ? null
                  : Icon(Icons.person_rounded, size: _photoEnlarged ? 44 : 26, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name ?? '', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (hasFooter)
                Text(
                  'Verified via DigiLocker',
                  style: text.bodySmall?.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w600),
                )
              else if (r.dob != null || r.gender != null)
                Text(
                  [if (r.dob != null) 'DOB: ${r.dob}', if (r.gender != null) r.gender!].join('  •  '),
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              if (!hasFooter && _photoEnlarged) ...[
                SizedBox(height: AppSpacing.sm),
                ...detailRows,
              ],
            ],
          ),
        ),
      ],
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        identityRow,
        if (widget.expectedName != null && widget.expectedName!.trim().isNotEmpty) ...[
          SizedBox(height: AppSpacing.md),
          _buildNameMatch(scheme, text),
        ],
        // When a footer is supplied, the fetched Aadhaar/address are surfaced as
        // fields in the footer — so we keep the summary compact here. Otherwise
        // show the full fetched details inline.
        if (hasFooter) ...[
          SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
          SizedBox(height: AppSpacing.lg),
          widget.footer!,
        ] else if (!_photoEnlarged) ...[
          SizedBox(height: AppSpacing.md),
          ...detailRows,
        ],
      ],
      ),
    );
  }

  Widget _buildNameMatch(ColorScheme scheme, TextTheme text) {
    final score = _nameMatch(_result?.name, widget.expectedName);
    final matched = score >= 0.5;
    final color = matched ? AppTheme.successColor : Colors.orange;
    return Container(
      padding: EdgeInsets.all(10.rs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.button,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(matched ? Icons.verified_user_rounded : Icons.info_outline_rounded, size: 16, color: color),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              matched
                  ? 'Identity matches the registered business name.'
                  : 'Aadhaar name differs from the business name — please confirm ownership.',
              style: text.bodySmall?.copyWith(
                color: matched ? AppTheme.successColor : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, ColorScheme scheme, {bool multiline = false, bool showTick = true}) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        SizedBox(height: 2.rs),
        Text(
          value.replaceFirst(RegExp(r'^[\s,]+'), '').trimRight(),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
        ),
      ],
    );
    // No tick → flush-left, aligned with the name / DOB lines.
    if (!showTick) return column;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successColor),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: column),
      ],
    );
  }
}
