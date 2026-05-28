import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SystemStats {
  final double cpuPercent;
  final double memPercent;
  final double? tempCelsius;

  const SystemStats({this.cpuPercent = 0, this.memPercent = 0, this.tempCelsius});

  static const zero = SystemStats();
}

final systemStatsProvider = StreamProvider<SystemStats>((ref) async* {
  yield await _fetchStats();
  await for (final _ in Stream.periodic(const Duration(seconds: 15))) {
    yield await _fetchStats();
  }
});

Future<SystemStats> _fetchStats() async {
  if (Platform.isMacOS) return _fetchMac();
  if (Platform.isWindows) return _fetchWindows();
  return SystemStats.zero;
}

Future<SystemStats> _fetchMac() async {
  final binPath = await _ensureMacHelper();
  if (binPath == null) return SystemStats.zero;

  try {
    final result = await Process.run(binPath, []);
    if (result.exitCode != 0) return SystemStats.zero;
    final parts = (result.stdout as String).trim().split(' ');
    if (parts.length < 2) return SystemStats.zero;
    final cpu = double.tryParse(parts[0]) ?? 0;
    final mem = double.tryParse(parts[1]) ?? 0;
    final temp = parts.length > 2 && parts[2] != '-' ? double.tryParse(parts[2]) : null;
    return SystemStats(cpuPercent: cpu, memPercent: mem, tempCelsius: temp);
  } catch (_) {
    return SystemStats.zero;
  }
}

const _macHelperSource = r'''
import IOKit
import Foundation
import Darwin

func getCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64)? {
    var cpuCount: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var cpuInfoCount: mach_msg_type_number_t = 0
    let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &cpuInfoCount)
    guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
    var user: UInt64 = 0, sys: UInt64 = 0, idle: UInt64 = 0
    for i in 0..<Int(cpuCount) {
        let base = Int(CPU_STATE_MAX) * i
        user += UInt64(info[base + Int(CPU_STATE_USER)]) + UInt64(info[base + Int(CPU_STATE_NICE)])
        sys += UInt64(info[base + Int(CPU_STATE_SYSTEM)])
        idle += UInt64(info[base + Int(CPU_STATE_IDLE)])
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
    return (user, sys, idle)
}

func cpuUsage() -> Double {
    guard let t1 = getCPUTicks() else { return 0 }
    usleep(100_000)
    guard let t2 = getCPUTicks() else { return 0 }
    let dUser = t2.user - t1.user
    let dSys = t2.system - t1.system
    let dIdle = t2.idle - t1.idle
    let total = dUser + dSys + dIdle
    if total == 0 { return 0 }
    return Double(dUser + dSys) / Double(total) * 100.0
}

func memUsage() -> Double {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    var totalMem: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
    if totalMem == 0 { return 0 }
    let pageSize = UInt64(vm_kernel_page_size)
    let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
    return Double(used) / Double(totalMem) * 100.0
}

typealias HIDRef = OpaquePointer
@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> HIDRef?
@_silgen_name("IOHIDEventSystemClientSetMatching")
func IOHIDEventSystemClientSetMatching(_ c: HIDRef, _ m: CFDictionary)
@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ c: HIDRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyEvent")
func IOHIDServiceClientCopyEvent(_ s: HIDRef, _ t: Int64, _ m: Int64, _ o: Int64) -> HIDRef?
@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ e: HIDRef, _ f: UInt32) -> Double

func temperature() -> Double? {
    guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
    IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
    guard let services = IOHIDEventSystemClientCopyServices(client) else { return nil }
    var mx: Double = 0
    for i in 0..<CFArrayGetCount(services) {
        let svc = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: HIDRef.self)
        guard let ev = IOHIDServiceClientCopyEvent(svc, 15, 0, 0) else { continue }
        let t = IOHIDEventGetFloatValue(ev, 15 << 16)
        if t > 10 && t < 120 && t > mx { mx = t }
    }
    return mx > 0 ? mx : nil
}

let cpu = cpuUsage()
let mem = memUsage()
let temp = temperature()
if let t = temp {
    print(String(format: "%.1f %.1f %.1f", cpu, mem, t))
} else {
    print(String(format: "%.1f %.1f -", cpu, mem))
}
''';

String? _macHelperBinPath;

Future<String?> _ensureMacHelper() async {
  if (_macHelperBinPath != null && File(_macHelperBinPath!).existsSync()) {
    return _macHelperBinPath;
  }

  final home = Platform.environment['HOME'] ?? '/tmp';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final binPath = '${dir.path}/sysstats';
  _macHelperBinPath = binPath;

  if (File(binPath).existsSync()) return binPath;

  final srcPath = '${dir.path}/sysstats.swift';
  File(srcPath).writeAsStringSync(_macHelperSource);
  final compile = await Process.run('swiftc', [
    srcPath, '-o', binPath, '-framework', 'IOKit', '-framework', 'Foundation', '-O',
  ]);
  if (compile.exitCode != 0) return null;
  return binPath;
}

Process? _winPsProcess;
Completer<void>? _winPsReady;

const _winStatsCmd = r"$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue; $os = Get-CimInstance Win32_OperatingSystem; $mem = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1); Write-Output ('STATS:{0} {1}' -f [math]::Round($cpu,1), $mem)";

Future<SystemStats> _fetchWindows() async {
  try {
    if (_winPsProcess == null) {
      _winPsProcess = await Process.start('powershell', ['-NoProfile', '-NoLogo', '-Command', '-']);
      _winPsReady = Completer<void>();
      _winPsReady!.complete();
    }
    await _winPsReady!.future;

    final completer = Completer<String>();
    final buffer = StringBuffer();
    late final StreamSubscription sub;
    sub = _winPsProcess!.stdout.transform(systemEncoding.decoder).listen((data) {
      buffer.write(data);
      final content = buffer.toString();
      if (content.contains('STATS:')) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete(content);
      }
    });

    _winPsProcess!.stdin.writeln(_winStatsCmd);

    final output = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      sub.cancel();
      return '';
    });

    final match = RegExp(r'STATS:([\d.]+)\s+([\d.]+)').firstMatch(output);
    if (match != null) {
      final cpu = double.tryParse(match.group(1)!) ?? 0;
      final mem = double.tryParse(match.group(2)!) ?? 0;
      return SystemStats(cpuPercent: cpu, memPercent: mem);
    }
  } catch (_) {
    _winPsProcess?.kill();
    _winPsProcess = null;
  }

  return SystemStats.zero;
}
