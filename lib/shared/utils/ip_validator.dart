import 'package:flutter/services.dart';

final _ipv4Regex = RegExp(
  r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
);

final _hostnameRegex = RegExp(
  r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$',
);

bool isValidIpAddress(String value) => _ipv4Regex.hasMatch(value.trim());

bool isValidHostOrIp(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  return _ipv4Regex.hasMatch(v) || _hostnameRegex.hasMatch(v);
}

String? validateIpAddress(String? value) {
  if (value == null || value.trim().isEmpty) return 'IP address required';
  if (!isValidIpAddress(value)) return 'Invalid IP (e.g. 192.168.1.100)';
  return null;
}

String? validateHostOrIp(String? value) {
  if (value == null || value.trim().isEmpty) return null; // allow empty
  if (!isValidHostOrIp(value)) return 'Invalid IP or hostname';
  return null;
}

class IpInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow digits, dots, and partial input while typing
    final filtered = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    if (filtered != newValue.text) {
      return TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }
    // Don't allow consecutive dots or more than 3 dots
    if (filtered.contains('..') || '.'.allMatches(filtered).length > 3) {
      return oldValue;
    }
    return newValue;
  }
}
