// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';
import 'dart:typed_data';

import '../diagnostics/network_log.dart';
import 'lan_address_guard.dart';
import 'lan_interfaces.dart';

/// An ASCII DNS label; browsers send IDNA names even for Chinese nicknames.
String localDomainLabel(String username, String deviceId) {
  final clean = username
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s._/\\:@?#\[\]]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uffff-]'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  var label = clean;
  if (clean.runes.any((r) => r >= 128)) {
    label = 'xn--${_punycode(clean)}';
  }
  final suffix = deviceId.replaceAll(RegExp('[^a-z0-9]'), '');
  if (label.isEmpty || label.length > 54) {
    label = 'user-${suffix.substring(max(0, suffix.length - 8))}';
  }
  return label;
}

String _punycode(String value) {
  final input = value.runes.toList();
  final output = StringBuffer();
  for (final r in input.where((r) => r < 128)) {
    output.writeCharCode(r);
  }
  var h = input.where((r) => r < 128).length;
  final basic = h;
  if (basic > 0) output.write('-');
  var n = 128, delta = 0, bias = 72;
  int adapt(int d, int points, bool first) {
    d = first ? d ~/ 700 : d ~/ 2;
    d += d ~/ points;
    var k = 0;
    while (d > 455) {
      d ~/= 35;
      k += 36;
    }
    return k + (36 * d) ~/ (d + 38);
  }

  void digit(int d) => output.writeCharCode(d < 26 ? 97 + d : 22 + d);
  while (h < input.length) {
    final m = input.where((r) => r >= n).reduce(min);
    delta += (m - n) * (h + 1);
    n = m;
    for (final r in input) {
      if (r < n) delta++;
      if (r != n) continue;
      var q = delta;
      for (var k = 36; ; k += 36) {
        final t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias);
        if (q < t) break;
        digit(t + (q - t) % (36 - t));
        q = (q - t) ~/ (36 - t);
      }
      digit(q);
      bias = adapt(delta, h + 1, h == basic);
      delta = 0;
      h++;
    }
    delta++;
    n++;
  }
  return output.toString();
}

bool isLocalDomain(String host) =>
    RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.local$').hasMatch(host);

class DnsQuestion {
  const DnsQuestion(this.name, this.type, {this.unicast = false});
  final String name;
  final int type;
  final bool unicast;
}

class DnsRecord {
  const DnsRecord(this.name, this.type, this.data, {this.ttl = 120});
  final String name;
  final int type;
  final Uint8List data;
  final int ttl;
}

class DnsPacket {
  const DnsPacket({
    this.id = 0,
    this.response = false,
    this.questions = const [],
    this.answers = const [],
    this.authorities = const [],
  });
  final int id;
  final bool response;
  final List<DnsQuestion> questions;
  final List<DnsRecord> answers, authorities;

  static DnsPacket? decode(Uint8List bytes) {
    try {
      if (bytes.length < 12 || bytes.length > 9000) return null;
      final reader = _DnsReader(bytes);
      final id = reader.u16(), flags = reader.u16();
      if ((flags & 0x7800) != 0 || (flags & 15) != 0) return null;
      final q = reader.u16(),
          a = reader.u16(),
          ns = reader.u16(),
          ar = reader.u16();
      if (q + a + ns + ar > 128) return null;
      final questions = <DnsQuestion>[];
      for (var i = 0; i < q; i++) {
        final name = reader.name(), type = reader.u16(), cls = reader.u16();
        if ((cls & 0x7fff) == 1) {
          questions.add(DnsQuestion(name, type, unicast: (cls & 0x8000) != 0));
        }
      }
      List<DnsRecord> records(int count) {
        final result = <DnsRecord>[];
        for (var i = 0; i < count; i++) {
          final name = reader.name(), type = reader.u16(), cls = reader.u16();
          final ttl = reader.u32(), size = reader.u16();
          if (reader.offset + size > bytes.length) {
            throw const FormatException();
          }
          final data = Uint8List.fromList(
            bytes.sublist(reader.offset, reader.offset + size),
          );
          reader.offset += size;
          if ((cls & 0x7fff) == 1) {
            result.add(DnsRecord(name, type, data, ttl: ttl));
          }
        }
        return result;
      }

      final answers = records(a), authorities = records(ns);
      records(ar);
      return DnsPacket(
        id: id,
        response: (flags & 0x8000) != 0,
        questions: questions,
        answers: answers,
        authorities: authorities,
      );
    } on Object {
      return null;
    }
  }

  Uint8List encode({bool cacheFlush = true}) {
    final out = BytesBuilder();
    void u16(int n) => out.add([n >> 8 & 255, n & 255]);
    void u32(int n) =>
        out.add([n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255]);
    void name(String s) {
      for (final label in s.split('.')) {
        final raw = utf8.encode(label);
        if (raw.isEmpty || raw.length > 63) {
          throw const FormatException('DNS label');
        }
        out.add([raw.length]);
        out.add(raw);
      }
      out.add([0]);
    }

    void record(DnsRecord r) {
      name(r.name);
      u16(r.type);
      u16(response && cacheFlush ? 0x8001 : 1);
      u32(r.ttl);
      u16(r.data.length);
      out.add(r.data);
    }

    u16(id);
    u16(response ? 0x8400 : 0);
    u16(questions.length);
    u16(answers.length);
    u16(authorities.length);
    u16(0);
    for (final q in questions) {
      name(q.name);
      u16(q.type);
      u16(q.unicast ? 0x8001 : 1);
    }
    for (final r in answers) {
      record(r);
    }
    for (final r in authorities) {
      record(r);
    }
    return out.takeBytes();
  }
}

class _DnsReader {
  _DnsReader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  int u16() {
    final n = ByteData.sublistView(bytes).getUint16(offset);
    offset += 2;
    return n;
  }

  int u32() {
    final n = ByteData.sublistView(bytes).getUint32(offset);
    offset += 4;
    return n;
  }

  String name() {
    var cursor = offset;
    int? end;
    final labels = <String>[], seen = <int>{};
    var length = 0;
    while (true) {
      if (cursor >= bytes.length || !seen.add(cursor) || seen.length > 128) {
        throw const FormatException('DNS compression');
      }
      final size = bytes[cursor++];
      if (size == 0) {
        offset = end ?? cursor;
        break;
      }
      if ((size & 0xc0) == 0xc0) {
        if (cursor >= bytes.length) throw const FormatException();
        end ??= cursor + 1;
        cursor = ((size & 63) << 8) | bytes[cursor];
        continue;
      }
      if (size > 63 || cursor + size > bytes.length) {
        throw const FormatException();
      }
      length += size + 1;
      if (length > 255) throw const FormatException();
      labels.add(
        utf8.decode(bytes.sublist(cursor, cursor + size)).toLowerCase(),
      );
      cursor += size;
    }
    return labels.join('.');
  }
}

/// Publishes one owned .local A record. It never alters DNS settings or hosts.
class LocalDomainService {
  LocalDomainService({
    required this.username,
    required this.deviceId,
    required this.address,
    this.listenPort = 5353,
    this.multicast = true,
    this.refreshInterval = const Duration(seconds: 15),
  });
  final String Function() username;
  final String deviceId;
  final Future<String?> Function() address;
  final int listenPort;
  final bool multicast;
  final Duration refreshInterval;
  final _changes = StreamController<void>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _events;
  final List<RawDatagramSocket> _senders = [];
  final Set<int> _joined = {};
  Timer? _refreshTimer, _repeat;
  Future<void>? _updating;
  String? host, ip, error;
  String? _label;
  bool ready = false, _closed = false, _conflict = false;
  int _generation = 0, _renames = 0;
  DateTime? _lastDefense;
  Stream<void> get changes => _changes.stream;
  int? get port => _socket?.port;

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listenPort,
        reuseAddress: true,
      );
      _socket!.multicastHops = 255;
      _socket!.multicastLoopback = true;
      NetworkLog.record('mdns.bound', {
        'address': _socket!.address.address,
        'port': _socket!.port,
      });
      _events = _socket!.listen(
        _receive,
        onError: (Object e) {
          NetworkLog.record('mdns.channel_error', NetworkLog.errorFields(e));
          error = e.toString();
          ready = false;
          _notify();
        },
        onDone: () {
          NetworkLog.record('mdns.done', {'expected': _closed});
        },
      );
      await refresh();
      _refreshTimer = Timer.periodic(
        refreshInterval,
        (_) => unawaited(refresh()),
      );
    } on Object catch (e) {
      NetworkLog.record('mdns.start_error', NetworkLog.errorFields(e));
      error = '局域网域名广播不可用：$e';
      ready = false;
      _notify();
    }
  }

  Future<void> refresh() => _updating ??= _refresh().whenComplete(() {
    _updating = null;
  });
  Future<void> _refresh() async {
    if (_closed) return;
    try {
      final nextIp = await address();
      if (_closed) return;
      final label = localDomainLabel(username(), deviceId);
      final needsName = _label != label;
      if (needsName || nextIp != ip || !ready) {
        _repeat?.cancel();
        if (ready) _announce(ttl: 0);
        ready = false;
        ip = nextIp;
        _renames = needsName ? 0 : _renames;
        _label = label;
        host = '$label${_renames == 0 ? '' : _suffix()}.local';
        _notify();
        if (ip == null) {
          error = '未连接局域网';
          _notify();
          return;
        }
        LanAddressGuard.requireCleartextAllowed(ip!);
        await _joinInterfaces();
        await _claim();
      }
    } on Object catch (e) {
      NetworkLog.record('mdns.refresh_error', NetworkLog.errorFields(e));
      error = '局域网域名广播不可用：$e';
      ready = false;
      _notify();
    }
  }

  String _suffix() {
    final id = deviceId.replaceAll(RegExp('[^a-z0-9]'), '');
    return '-${id.substring(max(0, id.length - 6))}${_renames > 1 ? '-$_renames' : ''}';
  }

  Future<void> _joinInterfaces() async {
    if (!multicast) return;
    for (final s in _senders) {
      s.close();
    }
    _senders.clear();
    for (final iface in await lanInterfaces(
      await NetworkInterface.list(type: InternetAddressType.IPv4),
    )) {
      for (final a in iface.addresses) {
        if (a.isLoopback || !LanAddressGuard.allowsCleartext(a.address)) {
          continue;
        }
        try {
          if (!_joined.contains(iface.index)) {
            _socket!.joinMulticast(InternetAddress('224.0.0.251'), iface);
            _joined.add(iface.index);
            NetworkLog.record('mdns.join', {
              'interface': iface.name,
              'address': a.address,
            });
          }
          final s = await RawDatagramSocket.bind(a, 0, reuseAddress: true);
          s.multicastHops = 255;
          s.multicastLoopback = true;
          _senders.add(s);
        } on SocketException catch (e) {
          NetworkLog.record('mdns.join_error', {
            'interface': iface.name,
            'address': a.address,
            ...NetworkLog.errorFields(e),
          });
          /* Another usable interface may succeed. */
        }
      }
    }
    if (_senders.isEmpty) throw const SocketException('没有可用的组播网卡');
  }

  DnsRecord _a({int ttl = 120}) =>
      DnsRecord(host!, 1, InternetAddress(ip!).rawAddress, ttl: ttl);
  Future<void> _claim() async {
    final generation = ++_generation;
    while (!_closed && generation == _generation) {
      _conflict = false;
      await Future<void>.delayed(Duration(milliseconds: Random().nextInt(251)));
      for (var i = 0; i < 3 && !_conflict && !_closed; i++) {
        _send(
          DnsPacket(
            questions: [DnsQuestion(host!, 255)],
            authorities: [_a()],
          ).encode(cacheFlush: false),
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (_closed || generation != _generation) return;
      if (_conflict) {
        _renames++;
        if (_renames > 8) {
          throw const SocketException('局域网内有过多同名冲突，无法注册域名');
        }
        host = '${localDomainLabel(username(), deviceId)}${_suffix()}.local';
        _notify();
        continue;
      }
      if (!_announce() && multicast) {
        throw const SocketException('无法发送域名组播');
      }
      ready = true;
      error = null;
      _lastDefense = null;
      _notify();
      _repeat?.cancel();
      _repeat = Timer(const Duration(seconds: 1), () {
        if (ready) _announce();
      });
      return;
    }
  }

  void _notify() {
    NetworkLog.record('mdns.state', {
      'host': host,
      'ip': ip,
      'ready': ready,
      'hasError': error != null,
    });
    if (!_closed) _changes.add(null);
  }

  bool _send(Uint8List data) {
    if (!multicast || _closed) return false;
    var sent = false;
    // Use the listening socket for the source port, and the interface option
    // for each NIC. Ephemeral sockets are only used to identify NIC addresses.
    for (final sender in _senders) {
      try {
        _socket!.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            RawSocketOption.IPv4MulticastInterface,
            sender.address.rawAddress,
          ),
        );
        final written = _socket!.send(
          data,
          InternetAddress('224.0.0.251'),
          5353,
        );
        sent = written > 0 || sent;
        NetworkLog.record('mdns.send', {
          'interfaceAddress': sender.address.address,
          'target': '224.0.0.251',
          'port': 5353,
          'written': written,
        });
      } on Object catch (e) {
        error = e.toString();
        NetworkLog.record('mdns.send_error', {
          'interfaceAddress': sender.address.address,
          'target': '224.0.0.251',
          'port': 5353,
          ...NetworkLog.errorFields(e),
        });
      }
    }
    return sent;
  }

  bool _announce({int ttl = 120}) {
    if (host != null && ip != null) {
      return _send(DnsPacket(response: true, answers: [_a(ttl: ttl)]).encode());
    }
    return false;
  }

  void _receive(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _closed) return;
    Datagram? datagram;
    while ((datagram = _socket!.receive()) != null) {
      final d = datagram!;
      if (!LanAddressGuard.allowsCleartext(d.address.address)) continue;
      final packet = DnsPacket.decode(d.data);
      if (packet == null || host == null || ip == null) continue;
      final ours = InternetAddress(ip!).rawAddress;
      final conflicting = [...packet.answers, ...packet.authorities].where(
        (r) =>
            r.name == host &&
            r.type == 1 &&
            r.ttl > 0 &&
            r.data.length == 4 &&
            !_equal(r.data, ours),
      );
      if (conflicting.isNotEmpty) {
        if (!ready) {
          // Existing owners win. During simultaneous probes, later RDATA wins.
          if (packet.response ||
              conflicting.any((r) => _compare(r.data, ours) > 0)) {
            _conflict = true;
          }
        } else if (packet.response) {
          final now = DateTime.now();
          if (_lastDefense != null &&
              now.difference(_lastDefense!).inSeconds < 10) {
            ready = false;
            _renames++;
            host =
                '${localDomainLabel(username(), deviceId)}${_suffix()}.local';
            _notify();
            unawaited(
              _claim().catchError((Object e) {
                ready = false;
                error = '局域网域名广播不可用：$e';
                _notify();
              }),
            );
          } else {
            _lastDefense = now;
            _announce();
          }
        } else {
          _announce();
        }
      }
      if (packet.response || !ready) continue;
      final questions = packet.questions
          .where(
            (q) =>
                q.name == host &&
                (q.type == 1 || q.type == 28 || q.type == 255),
          )
          .toList();
      if (questions.isEmpty) continue;
      NetworkLog.record('mdns.query', {
        'source': d.address.address,
        'port': d.port,
        'host': host,
        'types': questions.map((q) => q.type).toList(),
      });
      final legacy = d.port != 5353;
      final unicast = legacy || questions.any((q) => q.unicast);
      final answers = <DnsRecord>[];
      if (questions.any((q) => q.type == 1 || q.type == 255)) {
        if (!legacy &&
            packet.answers.any(
              (r) =>
                  r.name == host &&
                  r.type == 1 &&
                  r.ttl >= 60 &&
                  _equal(r.data, ours),
            )) {
          continue;
        }
        answers.add(_a(ttl: legacy ? 10 : 120));
      } else {
        // NSEC says that this host has A but no AAAA record.
        final nameBytes = <int>[];
        for (final label in host!.split('.')) {
          final encoded = utf8.encode(label);
          nameBytes.add(encoded.length);
          nameBytes.addAll(encoded);
        }
        answers.add(
          DnsRecord(
            host!,
            47,
            Uint8List.fromList([...nameBytes, 0, 0, 1, 0x40]),
          ),
        );
      }
      final reply = DnsPacket(
        id: legacy ? packet.id : 0,
        response: true,
        questions: legacy ? questions : [],
        answers: answers,
      ).encode(cacheFlush: !legacy);
      if (unicast) {
        try {
          final written = _socket!.send(reply, d.address, d.port);
          NetworkLog.record('mdns.reply', {
            'target': d.address.address,
            'port': d.port,
            'written': written,
          });
        } on SocketException catch (e) {
          NetworkLog.record('mdns.reply_error', {
            'target': d.address.address,
            'port': d.port,
            ...NetworkLog.errorFields(e),
          });
          error = e.toString();
          _notify();
        }
      } else {
        _send(reply);
      }
    }
  }

  static bool _equal(List<int> a, List<int> b) => _compare(a, b) == 0;
  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < min(a.length, b.length); i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  Future<void> stop() async {
    if (_closed) return;
    _refreshTimer?.cancel();
    _repeat?.cancel();
    if (ready) _announce(ttl: 0);
    _closed = true;
    ready = false;
    _generation++;
    await _updating;
    await _events?.cancel();
    _socket?.close();
    for (final s in _senders) {
      s.close();
    }
    await _changes.close();
  }
}
