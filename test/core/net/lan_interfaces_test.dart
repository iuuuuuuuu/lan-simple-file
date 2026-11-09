// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/net/lan_interfaces.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';

class TestInterface implements NetworkInterface {
  TestInterface(this.name, List<String> ips, [this.index = 1])
    : addresses = ips.map(TestAddress.new).toList();
  @override
  final String name;
  @override
  final int index;
  @override
  final List<InterfaceAddress> addresses;
}

class TestAddress implements InterfaceAddress {
  TestAddress(String ip) : value = InternetAddress(ip);
  final InternetAddress value;
  @override
  String get address => value.address;
  @override
  InternetAddressType get type => value.type;
  @override
  String get host => value.host;
  @override
  Uint8List get rawAddress => value.rawAddress;
  @override
  bool get isLoopback => value.isLoopback;
  @override
  bool get isLinkLocal => value.isLinkLocal;
  @override
  bool get isMulticast => value.isMulticast;
  @override
  int get prefixLength => 24;
  @override
  InternetAddress? get broadcast => null;
  @override
  Future<InternetAddress> reverse() => value.reverse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final phone = [
    TestInterface('rmnet_data6', ['10.204.8.120'], 1565),
    TestInterface('wlan0', ['192.168.31.22'], 23),
  ];
  Object? networks = <Object?>[];
  setUp(() {
    networks = [
      {
        'name': 'wlan0',
        'addresses': ['192.168.31.22'],
        'isDefault': true,
      },
    ];
    messenger.setMockMethodCallHandler(lanNetworkChannel, (call) async {
      expect(call.method, 'getLanInterfaces');
      return networks;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(lanNetworkChannel, null));
  Future<String?> select(List<NetworkInterface> interfaces) => pickLanAddress(
    operatingSystem: 'android',
    listInterfaces: () async => interfaces,
  );

  test(
    'phone log regression: cellular 10.x never overrides connected Wi-Fi',
    () async {
      expect(await select(phone), '192.168.31.22');
      expect(await select(phone.reversed.toList()), '192.168.31.22');
      final eligible = await lanInterfaces(phone, operatingSystem: 'android');
      expect(eligible.map((i) => i.name), ['wlan0']);
      expect(eligible.single.index, 23);
    },
  );

  test('private 10.x Wi-Fi and vendor interface names are accepted by network type', () async {
    networks = [
      {
        'name': 'vendor_wifi7',
        'addresses': ['10.0.0.9'],
        'isDefault': false,
      },
    ];
    expect(
      await select([
        TestInterface('rmnet_data6', ['10.0.0.2']),
        TestInterface('vendor_wifi7', ['10.0.0.9']),
        TestInterface('tun0', ['192.168.1.3']),
      ]),
      '10.0.0.9',
    );
  });

  test('default LAN network wins while cellular-only and stale addresses yield none', () async {
    final interfaces = [
      ...phone,
      TestInterface('eth0', ['172.16.8.9']),
    ];
    networks = [
      {
        'name': 'wlan0',
        'addresses': ['192.168.31.22'],
        'isDefault': false,
      },
      {
        'name': 'eth0',
        'addresses': ['172.16.8.9'],
        'isDefault': true,
      },
    ];
    expect(await select(interfaces), '172.16.8.9');
    networks = [];
    expect(
      await select(interfaces),
      isNull,
      reason: 'No default cellular fallback',
    );
    networks = [
      {
        'name': 'wlan0',
        'addresses': ['192.168.31.23'],
        'isDefault': true,
      },
    ];
    expect(
      await select(phone),
      isNull,
      reason: 'Stale enumeration must not be advertised',
    );
  });

  test('Wi-Fi changes are read each time, without requiring public internet validation', () async {
    expect(await select(phone), '192.168.31.22');
    networks = [
      {
        'name': 'wlan0',
        'addresses': ['172.20.5.2'],
        'isDefault': false,
      },
    ];
    expect(
      await select([
        phone.first,
        TestInterface('wlan0', ['172.20.5.2']),
      ]),
      '172.20.5.2',
    );
  });

  test(
    'bridge failure uses only known LAN names, never cellular or VPN',
    () async {
      final interfaces = [
        ...phone,
        TestInterface('ccmni0', ['10.0.0.1']),
        TestInterface('tun0', ['10.0.0.3']),
        TestInterface('unknown0', ['10.0.0.4']),
      ];
      for (final handler in <Future<Object?> Function(MethodCall)?>[
        null,
        (_) async => throw PlatformException(code: 'denied'),
        (_) async => null,
      ]) {
        messenger.setMockMethodCallHandler(lanNetworkChannel, handler);
        expect(await select(interfaces), '192.168.31.22');
        expect(
          await select([phone.first, interfaces[2], interfaces[3]]),
          isNull,
        );
      }
    },
  );

  test(
    'public IPv4, IPv6, loopback and link-local are not advertised',
    () async {
      for (final ip in ['8.8.8.8', '127.0.0.1', '169.254.1.1', 'fe80::1']) {
        networks = [
          {
            'name': 'wlan0',
            'addresses': [ip],
            'isDefault': true,
          },
        ];
        expect(
          await select([
            TestInterface('wlan0', [ip]),
          ]),
          isNull,
        );
      }
    },
  );

  test(
    'desktop interface policy remains independent of the Android bridge',
    () async {
      messenger.setMockMethodCallHandler(
        lanNetworkChannel,
        (_) async => throw StateError('unexpected call'),
      );
      final interfaces = [
        TestInterface('Ethernet', ['10.168.1.115']),
        TestInterface('vEthernet', ['10.0.0.1']),
      ];
      expect(
        await pickLanAddress(
          operatingSystem: 'windows',
          listInterfaces: () async => interfaces,
        ),
        '10.168.1.115',
      );
      expect(
        await lanInterfaces(interfaces, operatingSystem: 'windows'),
        same(interfaces),
      );
    },
  );

  test('real DNS response advertises selected Wi-Fi and stops when Wi-Fi disappears', () async {
    final service = LocalDomainService(
      username: () => 'xiaomi-15-pro',
      deviceId: 'p_testphone',
      address: () => select(phone),
      listenPort: 0,
      multicast: false,
    );
    final client = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final received = Completer<DnsPacket>();
    final events = client.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = client.receive();
      if (datagram == null) return;
      final packet = DnsPacket.decode(datagram.data);
      if (packet != null && !received.isCompleted) received.complete(packet);
    });
    try {
      await service.start();
      expect(service.ready, isTrue);
      client.send(
        DnsPacket(
          id: 123,
          questions: [DnsQuestion('xiaomi-15-pro.p-testphone.local', 1)],
        ).encode(),
        InternetAddress.loopbackIPv4,
        service.port!,
      );
      final response = await received.future.timeout(
        const Duration(seconds: 2),
      );
      expect(response.answers.single.data, [192, 168, 31, 22]);
      networks = [];
      await service.refresh();
      expect(service.ready, isFalse);
      expect(service.ip, isNull);
    } finally {
      await events.cancel();
      client.close();
      await service.stop();
    }
  });
}
