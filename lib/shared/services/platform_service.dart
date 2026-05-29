import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformService {
  PlatformService._();

  // ─── File Operations ────────────────────────────────────────────────────────

  static Future<void> openFile(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }

  static Future<void> revealInExplorer(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  // ─── Audio ──────────────────────────────────────────────────────────────────

  static Future<void> playSound(SoundType type) async {
    try {
      if (Platform.isMacOS) {
        final file = switch (type) {
          SoundType.capture => '/System/Library/Sounds/Pop.aiff',
          SoundType.complete => '/System/Library/Sounds/Glass.aiff',
          SoundType.error => '/System/Library/Sounds/Basso.aiff',
          SoundType.notification => '/System/Library/Sounds/Ping.aiff',
        };
        await Process.run('afplay', [file]);
      } else if (Platform.isWindows) {
        final file = switch (type) {
          SoundType.capture => r'C:\Windows\Media\Windows Navigation Start.wav',
          SoundType.complete => r'C:\Windows\Media\Windows Print complete.wav',
          SoundType.error => r'C:\Windows\Media\Windows Critical Stop.wav',
          SoundType.notification => r'C:\Windows\Media\Windows Notify Email.wav',
        };
        await Process.run('powershell', ['-c', '(New-Object Media.SoundPlayer "$file").PlaySync()']);
      }
    } catch (_) {}
  }

  // ─── Serial Port Classification ────────────────────────────────────────────

  static Future<String> classifyPort(String port) async {
    if (Platform.isMacOS) {
      if (port.contains('usbserial') || port.contains('usbmodem')) return 'usb';
      return 'physical';
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query', r'HKLM\SYSTEM\CurrentControlSet\Enum', '/s', '/f',
          port.replaceAll(RegExp(r'^\\\\\.\\.\\'), ''),
        ]);
        final output = result.stdout.toString().toLowerCase();
        if (output.contains('com0com') || output.contains('virtual')) return 'virtual';
        if (output.contains('usb')) return 'usb';
      } catch (_) {}
      return 'physical';
    } else {
      if (port.contains('ttyUSB') || port.contains('ttyACM')) return 'usb';
      return 'physical';
    }
  }

  // ─── Serial Port Configuration ─────────────────────────────────────────────

  static Future<void> configureSerialPort(String port, int baudRate) async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('stty', ['-f', port, '$baudRate', 'cs8', '-parenb', '-cstopb']);
      } else if (Platform.isWindows) {
        await Process.run('mode', ['$port:', 'baud=$baudRate', 'parity=n', 'data=8', 'stop=1']);
      }
    } catch (_) {}
  }

  // ─── Printing ───────────────────────────────────────────────────────────────

  static Future<bool> printRaw(String printerName, List<int> data, {int copies = 1}) async {
    final tmpFile = File('${Directory.systemTemp.path}/wb_print_${DateTime.now().millisecondsSinceEpoch}.prn');
    await tmpFile.writeAsBytes(data);

    try {
      if (Platform.isWindows) {
        for (var i = 0; i < copies; i++) {
          final result = await Process.run('powershell', [
            '-NoProfile', '-Command',
            'Get-Content -Encoding Byte -ReadCount 0 "${tmpFile.path}" | Out-Printer -Name "$printerName"',
          ]);
          if (result.exitCode != 0) return false;
        }
        return true;
      } else {
        final args = <String>['-#', '$copies', '-o', 'raw'];
        if (printerName.isNotEmpty && printerName != 'default') {
          args.addAll(['-P', printerName]);
        }
        args.add(tmpFile.path);
        final result = await Process.run('lpr', args);
        return result.exitCode == 0;
      }
    } finally {
      tmpFile.delete().catchError((_) => tmpFile);
    }
  }

  static Future<bool> printPdf(String printerName, List<int> data, {int copies = 1}) async {
    final tmpFile = File('${Directory.systemTemp.path}/wb_print_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await tmpFile.writeAsBytes(data);

    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Start-Process -FilePath "${tmpFile.path}" -Verb PrintTo -ArgumentList "$printerName" -Wait -WindowStyle Hidden',
        ]);
        return result.exitCode == 0;
      } else {
        final args = <String>['-#', '$copies'];
        if (printerName.isNotEmpty && printerName != 'default') {
          args.addAll(['-P', printerName]);
        }
        args.add(tmpFile.path);
        final result = await Process.run('lpr', args);
        return result.exitCode == 0;
      }
    } finally {
      tmpFile.delete().catchError((_) => tmpFile);
    }
  }

  // ─── System Stats ──────────────────────────────────────────────────────────

  static Future<({double cpu, double mem, double? temp})> getSystemStats() async {
    if (Platform.isMacOS) return _getStatsMac();
    if (Platform.isWindows) return _getStatsWindows();
    return (cpu: 0.0, mem: 0.0, temp: null);
  }

  static Future<({double cpu, double mem, double? temp})> _getStatsWindows() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command',
        r'$c = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue; $cpu = if($c){[math]::Round($c.CounterSamples[0].CookedValue,1)}else{(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average}; $os = Get-CimInstance Win32_OperatingSystem; $mem = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1); $t = (Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction SilentlyContinue | Select -First 1).CurrentTemperature; Write-Output "$cpu $mem $t"',
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
        final cpu = double.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
        final mem = double.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
        double? temp;
        final tempVal = int.tryParse(parts.elementAtOrNull(2) ?? '');
        if (tempVal != null && tempVal > 0) temp = (tempVal - 2732) / 10.0;
        return (cpu: cpu, mem: mem, temp: temp);
      }
    } catch (_) {}
    return (cpu: 0.0, mem: 0.0, temp: null);
  }

  static Future<({double cpu, double mem, double? temp})> _getStatsMac() async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final binPath = '$home/.weighbridge/sysstats';
      if (!File(binPath).existsSync()) return (cpu: 0.0, mem: 0.0, temp: null);
      final result = await Process.run(binPath, []);
      if (result.exitCode != 0) return (cpu: 0.0, mem: 0.0, temp: null);
      final parts = (result.stdout as String).trim().split(' ');
      final cpu = double.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
      final mem = double.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
      double? temp;
      if (parts.length > 2 && parts[2] != '-') temp = double.tryParse(parts[2]);
      return (cpu: cpu, mem: mem, temp: temp);
    } catch (_) {
      return (cpu: 0.0, mem: 0.0, temp: null);
    }
  }

  // ─── Process Control (kill remote apps like AnyDesk) ───────────────────────

  static Future<void> killProcess(String processName) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('osascript', ['-e', 'tell application "$processName" to quit']);
      } else if (Platform.isWindows) {
        await Process.run('taskkill', ['/IM', '$processName.exe', '/F']);
      } else {
        await Process.run('pkill', [processName]);
      }
    } catch (_) {}
  }

  // ─── Printer Discovery ─────────────────────────────────────────────────────

  static Future<List<String>> listPrinters() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('lpstat', ['-a']);
        if (result.exitCode == 0) {
          return (result.stdout as String)
              .split('\n')
              .where((l) => l.isNotEmpty)
              .map((l) => l.split(' ').first)
              .toList();
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile', '-Command', 'Get-Printer | Select-Object -ExpandProperty Name',
        ]);
        if (result.exitCode == 0) {
          return (result.stdout as String)
              .split(RegExp(r'[\r\n]+'))
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // ─── Home Directory ────────────────────────────────────────────────────────

  static String get homeDir =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

  static String get appDataDir {
    final dir = Directory('$homeDir/.weighbridge');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  // ─── Audio Output Driver ───────────────────────────────────────────────────

  static String get audioDriver {
    if (Platform.isWindows) return 'wasapi';
    if (Platform.isMacOS) return 'coreaudio';
    return 'pulse';
  }

  static String get hwDecoder {
    if (Platform.isWindows) return 'd3d11va';
    if (Platform.isMacOS) return 'videotoolbox';
    return 'vaapi';
  }
}

enum SoundType { capture, complete, error, notification }
