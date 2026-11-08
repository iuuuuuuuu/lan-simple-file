// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Opt-in, bounded JSONL journal. Callers supply metadata, never payloads.
class NetworkLog {
  NetworkLog(this.directory, {this.maxBytes = 512 * 1024});

  static NetworkLog? active;
  final Directory directory;
  final int maxBytes;
  static const maxPending = 128;
  final List<String> _pending = [];
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  int _dropped = 0;
  String? writeError;
  bool _closed = false;

  File get _current => File('${directory.path}/network.jsonl');
  File _archive(int i) => File('${directory.path}/network.$i.jsonl');

  static void record(String event, [Map<String, Object?> fields = const {}]) =>
      active?.add(event, fields);

  /// Deliberately avoids arbitrary exception.toString(): it can contain tokens,
  /// request paths, or file contents. Socket errno/address are useful evidence.
  static Map<String, Object?> errorFields(Object error) => {
    'errorType': error.runtimeType.toString(),
    if (error is SocketException) ...{
      'message': error.message,
      'errno': error.osError?.errorCode,
      'osMessage': error.osError?.message,
      'socketAddress': error.address?.address,
      'socketPort': error.port,
    },
  };

  static Object? _safe(Object? value, [int depth = 0]) {
    if (depth > 6) return '[bounded]';
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries.take(40))
          entry.key.toString():
              RegExp(
                r'token|password|secret|authorization|cookie|payload|body|filename|filepath|privatekey',
                caseSensitive: false,
              ).hasMatch(entry.key.toString())
              ? '[redacted]'
              : _safe(entry.value, depth + 1),
      };
    }
    if (value is Iterable) {
      return value.take(32).map((v) => _safe(v, depth + 1)).toList();
    }
    if (value is String) {
      final text = value
          .replaceAll(
            RegExp(r'(?:https?|lsf)://[^\s]+', caseSensitive: false),
            '[url omitted]',
          )
          .replaceAll(
            RegExp(
              r'(?:Bearer\s+\S+|(?:token|password|secret|k)=\S+)',
              caseSensitive: false,
            ),
            '[redacted]',
          );
      return text.length > 512 ? '${text.substring(0, 512)}...' : text;
    }
    return value == null || value is num || value is bool
        ? value
        : value.runtimeType.toString();
  }

  void add(String event, [Map<String, Object?> fields = const {}]) {
    if (_closed) return;
    final line =
        '${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), 'event': _safe(event), 'data': _safe(fields)})}\n';
    if (_pending.length >= maxPending ||
        utf8.encode(line).length > maxBytes ||
        utf8.encode(line).length > 8192) {
      _dropped++;
      return;
    }
    _pending.add(line);
    _timer ??= Timer(const Duration(seconds: 1), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _tail = _tail.then((_) async {
      // Drain inside the serialized writer so a slow disk cannot grow a queue
      // of detached buffers without bound.
      final lines = List<String>.of(_pending);
      _pending.clear();
      if (_dropped > 0) {
        lines.add(
          '${jsonEncode({'event': 'log.dropped', 'count': _dropped})}\n',
        );
        _dropped = 0;
      }
      if (lines.isEmpty) return;
      try {
        await directory.create(recursive: true);
        var size = await _current.exists() ? await _current.length() : 0;
        for (final line in lines) {
          final bytes = utf8.encode(line);
          if (size + bytes.length > maxBytes) {
            if (await _archive(2).exists()) await _archive(2).delete();
            if (await _archive(1).exists()) {
              await _archive(1).rename(_archive(2).path);
            }
            if (await _current.exists()) {
              await _current.rename(_archive(1).path);
            }
            size = 0;
          }
          await _current.writeAsBytes(bytes, mode: FileMode.append);
          size += bytes.length;
        }
        writeError = null;
      } on Object catch (error) {
        writeError = error.runtimeType.toString();
      }
    });
    return _tail;
  }

  Future<File> export(Directory destination) async {
    await flush();
    if (writeError != null) throw FileSystemException('日志写入失败: $writeError');
    // Serialize with rotation to avoid torn or missing archive files.
    final result = Completer<File>();
    _tail = _tail.then((_) async {
      try {
        await destination.create(recursive: true);
        final file = File('${destination.path}/lan-network-diagnostics.txt');
        // Await each operation directly: an IOSink can report open failures on
        // its done future before addStream/flush have a chance to handle them.
        await file.writeAsString(
          'Lan Simple File network diagnostics (JSONL)\n'
          'Self checks originate on this device; they do not prove LAN reachability.\n'
          'Contains local addresses/domain and system network metadata. No packet/file contents.\n',
        );
        for (final source in [_archive(2), _archive(1), _current]) {
          if (await source.exists()) {
            await file.writeAsBytes(
              await source.readAsBytes(),
              mode: FileMode.append,
            );
          }
        }
        result.complete(file);
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> close() async {
    _closed = true;
    await flush();
  }
}
