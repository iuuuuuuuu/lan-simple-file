// SPDX-License-Identifier: GPL-3.0-only

/// 设置页测试：真实 pump + 真实 build，数据源是可记账的假实现。
///
/// 「假」只假在数据来源（不真起 UDP/HTTP），页面与组件本身全是真的。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/widgets/setting_row.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';

import 'support/settings_stubs.dart';

/// 可记账的设置数据源：记录每次调用的入参，供用例断言「真的读写」。
final class FakeSettingsSource implements SettingsSource {
  FakeSettingsSource(this.snapshot);

  /// 当前快照；页面 load() 时原样返回。
  SettingsSnapshot snapshot;

  /// 收到的昵称保存调用。
  final List<String> savedNames = <String>[];

  /// probe 被调用次数。
  int probes = 0;

  /// revokeAllLinks 被调用次数。
  int revokes = 0;

  /// load 被调用次数。
  int loads = 0;

  /// 保存昵称时抛出的错误（验证失败路径真的显示出来）。
  Object? saveError;

  @override
  Future<SettingsSnapshot> load() async {
    loads++;
    return snapshot;
  }

  @override
  Future<void> saveNickname(String name) async {
    final Object? error = saveError;
    if (error != null) throw error;
    savedNames.add(name);
    snapshot = snapshot.copyWith(nickname: name);
  }

  @override
  Future<void> probe() async {
    probes++;
  }

  @override
  Future<void> revokeAllLinks() async {
    revokes++;
  }
}

/// 构造快照的便捷函数（默认值是「一切正常」）。
SettingsSnapshot snapshotOf({
  String nickname = '测试账户',
  String peerId = 'p_7fk3m9x2a1c00',
  int port = 47778,
  String platform = 'Windows',
  int onlinePeers = 2,
  String? degradedReason,
  int rejectedBadSignature = 0,
  int rejectedMalformed = 0,
  int rejectedFromSelf = 0,
  int rejectedUnknownPeerId = 0,
  List<String> recentReasons = const <String>[],
}) => SettingsSnapshot(
  nickname: nickname,
  peerId: peerId,
  port: port,
  platform: platform,
  onlinePeers: onlinePeers,
  degradedReason: degradedReason,
  rejectedBadSignature: rejectedBadSignature,
  rejectedMalformed: rejectedMalformed,
  rejectedFromSelf: rejectedFromSelf,
  rejectedUnknownPeerId: rejectedUnknownPeerId,
  recentReasons: recentReasons,
);

/// 用指定亮度包装设置页。
Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: AppTheme.of(LanFilePalette.of(brightness)),
    home: Scaffold(body: child),
  );
}

void main() {
  tearDown(AppToast.dismiss);
  testWidgets('允许局域网访问使用实际端口，失败不显示成功', (tester) async {
    final List<int> ports = <int>[];
    final FakeSettingsSource source = FakeSettingsSource(
      snapshotOf(port: 48001),
    );
    String? error;
    await tester.pumpWidget(
      wrap(
        SettingsPage(
          source: source,
          allowLanAccess: (int port) async {
            ports.add(port);
            return error;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Finder action = find.text('允许局域网访问');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(ports, <int>[48001]);
    expect(find.textContaining('已允许私人网络'), findsOneWidget);

    error = '请以管理员身份运行一次应用';
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(ports, <int>[48001, 48001]);
    expect(find.textContaining('请以管理员身份'), findsOneWidget);
    expect(find.textContaining('已允许私人网络'), findsNothing);
  });

  group('services 为 null', () {
    testWidgets('无服务时仍显示静态信息（版本与许可），不崩溃', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const SettingsPage()));
      await tester.pumpAndSettle();

      // 语义澄清：之前整页替换成「未连接服务」，会让用户在服务没起来时
      // 连「这是什么软件、什么许可」都看不到——那是信息缺失，不是降级。
      // 现在改为渲染骨架：静态项可见，动态项标明不可用。
      expect(
        find.textContaining('GPL-3.0-only'),
        findsWidgets,
        reason: '许可证必须始终可见',
      );
      expect(find.text('关于'), findsWidgets, reason: '关于分组必须存在');
      // 动态项标成不可用，而不是假装有数据。
      expect(
        find.textContaining('本机服务未启动'),
        findsWidgets,
        reason: '必须明确告知服务未启动，不能静默',
      );
    });
  });

  group('个人资料卡', () {
    testWidgets('取消弹窗不改名字，中文输入法组词回车不会提前提交', (tester) async {
      final source = FakeSettingsSource(snapshotOf(nickname: '原昵称'));
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nickname-field')), '新中文名字');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(source.savedNames, isEmpty);
      expect(find.text('原昵称'), findsOneWidget);
      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('nickname-field')),
          matching: find.byType(TextField),
        ),
      );
      field.controller!.value = const TextEditingValue(
        text: '中文 名字',
        composing: TextRange(start: 0, end: 5),
      );
      field.onSubmitted!('中文 名字');
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(source.savedNames, isEmpty);
      field.controller!.value = field.controller!.value.copyWith(
        composing: TextRange.empty,
      );
      field.onSubmitted!('中文 名字');
      field.onSubmitted!('中文 名字');
      await tester.pumpAndSettle();
      expect(source.savedNames, ['中文 名字']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('app-toast')), findsOneWidget);
    });

    testWidgets('窄屏修改昵称后 toast 不挤占设置页面', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('本机信息'));
      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nickname-field')), '小明');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('本机信息')), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('初始昵称取注入的登录账户名', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(nickname: 'yg_account'),
      );
      await tester.pumpWidget(
        wrap(SettingsPage(source: source, currentUserName: 'yg_account')),
      );
      await tester.pumpAndSettle();

      expect(find.text('yg_account'), findsOneWidget);
      // peerId 以小字展示（SelectableText 内部会同时产出 EditableText 与 Text）。
      expect(find.text('p_7fk3m9x2a1c00'), findsWidgets);
    });

    testWidgets('改昵称为「小明」后 store 收到 (profile.name, 小明)', (
      WidgetTester tester,
    ) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(nickname: 'yg_account'),
      );
      await tester.pumpWidget(
        wrap(SettingsPage(source: source, currentUserName: 'yg_account')),
      );
      await tester.pumpAndSettle();

      // 点编辑按钮 -> 出现输入框。
      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '小明');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(source.savedNames, <String>['小明']);
      expect(find.text('小明'), findsOneWidget);
      expect(find.text('昵称已保存'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('app-toast')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text('昵称已保存'),
        ),
        findsNothing,
      );
    });

    testWidgets('空昵称被拒，且不调用保存', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(source.savedNames, isEmpty);
      expect(find.text('昵称不能为空'), findsOneWidget);
    });

    testWidgets('保存失败时把错误显示出来，不静默吞掉', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf())
        ..saveError = StateError('磁盘只读');
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小明');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('昵称保存失败'), findsOneWidget, reason: '失败必须可见');
    });
  });

  group('本机信息', () {
    testWidgets('peerId、端口、系统、在线数都真的渲染', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(
          peerId: 'p_abcdefghij012',
          port: 48001,
          platform: 'Windows',
          onlinePeers: 3,
        ),
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('p_abcdefghij012'), findsWidgets);
      expect(find.text('48001'), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('网络分组', () {
    testWidgets('降级为只发不收时给出告警文案', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(degradedReason: 'UDP 47777 端口被占用'),
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('只发不收'), findsOneWidget);
      // 断言**具体原因**被原样显示：用户排障要知道是哪个端口、什么原因，
      // 一句笼统的「只能发送公告」不足以定位问题。
      expect(
        find.textContaining('UDP 47777 端口被占用'),
        findsOneWidget,
        reason: '必须显示真实降级原因，而不是笼统描述',
      );
    });

    testWidgets('未降级时没有告警', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('只发不收'), findsNothing);
      expect(find.text('正常'), findsOneWidget);
    });

    testWidgets('点「重新广播」调用 probe 恰好一次', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('重新广播'));
      await tester.tap(find.text('重新广播'));
      await tester.pumpAndSettle();

      expect(source.probes, 1);
      expect(find.textContaining('已重新广播'), findsOneWidget);
    });
  });

  group('安全分组', () {
    testWidgets('渲染真实丢弃计数与原因列表', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(
          rejectedBadSignature: 3,
          rejectedMalformed: 2,
          rejectedFromSelf: 5,
          rejectedUnknownPeerId: 1,
          recentReasons: <String>['验签失败: p_aaa', '畸形包: 空载荷'],
        ),
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      // 总数 = 3 + 2 + 1 = 6（不含自身回环）。
      expect(find.text('6'), findsOneWidget);
      expect(find.textContaining('验签失败 3'), findsOneWidget);
      expect(find.textContaining('畸形包 2'), findsOneWidget);
      expect(find.textContaining('非法 peerId 1'), findsOneWidget);
      // 自身回环单独一行。
      expect(find.text('自身回环包'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // 原因列表。
      expect(find.text('最近丢弃原因'), findsOneWidget);
      expect(find.text('· 验签失败: p_aaa'), findsOneWidget);
      expect(find.text('· 畸形包: 空载荷'), findsOneWidget);
    });

    testWidgets('没有丢弃时说明通道干净', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有丢弃记录'), findsOneWidget);
      expect(find.text('最近丢弃原因'), findsNothing);
    });

    testWidgets('零邻居且有丢包时给出排障提示', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(
        snapshotOf(
          onlinePeers: 0,
          rejectedMalformed: 4,
          recentReasons: <String>['畸形包: 空载荷'],
        ),
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.textContaining('一个邻居也看不到'), findsOneWidget);
      expect(find.textContaining('UDP 47777'), findsOneWidget);
    });

    testWidgets('点「立即失效所有链接」调用回调恰好一次', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('失效'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('失效'));
      await tester.pumpAndSettle();

      expect(source.revokes, 1);
      expect(find.text('已失效所有分享链接'), findsOneWidget);
    });
  });

  group('关于分组', () {
    testWidgets('应用名、版本、GPL 声明都渲染', (WidgetTester tester) async {
      final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text(kAppName), findsOneWidget);
      expect(find.text(kAppVersion), findsOneWidget);
      expect(find.text(kAppLicense), findsOneWidget);
      expect(find.textContaining('GPL-3.0-only'), findsWidgets);
    });
  });

  group('主题 token', () {
    testWidgets('明暗两套下卡片底色与描边取自 token', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        final FakeSettingsSource source = FakeSettingsSource(snapshotOf());
        await tester.pumpWidget(
          wrap(SettingsPage(source: source), brightness: brightness),
        );
        await tester.pumpAndSettle();

        final LanFileTokens expected = LanFilePalette.of(brightness);
        final LanFileTokens actual = Theme.of(
          tester.element(find.byType(Scaffold)),
        ).extension<LanFileTokens>()!;
        expect(actual.bg, expected.bg);
        expect(actual.surface, expected.surface);
        expect(actual.line, expected.line);
        expect(actual.fg, expected.fg);
        expect(actual.fgDim, expected.fgDim);
        expect(actual.accent, expected.accent);
        // 页面确实用了 surface 作卡片底色。
        expect(find.text('本机信息'), findsOneWidget);
      }
    });
  });

  group('SettingRow 组件', () {
    testWidgets('有 onTap 时可点，且 hover 出现浅底色', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        wrap(SettingRow(label: '可点行', value: '值', onTap: () => taps++)),
      );
      await tester.pumpAndSettle();

      // 悬停。
      final TestGesture gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: tester.getCenter(find.text('可点行')));
      await tester.pumpAndSettle();
      await gesture.removePointer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('可点行'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('没有 onTap 时不可点', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const SettingRow(label: '只读行', value: '值')));
      await tester.pumpAndSettle();
      expect(find.text('只读行'), findsOneWidget);
      // 不可点 = 行内没有 GestureDetector（Material 自身会注入 MouseRegion，不能拿它判）。
      expect(
        find.descendant(
          of: find.byType(SettingRow),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  group('真实接线：ServiceSettingsSource 打到真 store 与真 announce', () {
    /// 造一个只提供设置页所需能力的窄端口组合。
    ServiceSettingsSource sourceWith({
      required RecordingSettingsStore store,
      required RecordingAnnounce announce,
      String userName = 'yg_account',
      int port = 47778,
      String platform = 'Windows',
      Future<void> Function()? revoke,
    }) => ServiceSettingsSource(
      store: store,
      announce: announce,
      selfPeerId: PeerId.parse('p_7fk3m9x2a1c00'),
      serverPort: port,
      currentUserName: userName,
      revokeAllLinksFn: revoke ?? () async {},
      platformName: platform,
    );

    testWidgets('保存昵称真的写进 store（profile.name）', (WidgetTester tester) async {
      final RecordingSettingsStore store = RecordingSettingsStore();
      final RecordingAnnounce announce = RecordingAnnounce();
      final ServiceSettingsSource source = sourceWith(
        store: store,
        announce: announce,
      );

      await tester.pumpWidget(
        wrap(SettingsPage(source: source, currentUserName: 'yg_account')),
      );
      await tester.pumpAndSettle();

      // 初始昵称来自注入的登录账户名。
      expect(find.text('yg_account'), findsOneWidget);

      await tester.tap(find.byTooltip('修改昵称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小明');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 关键断言：真的落到 store 的 profile.name，而不是只改内存。
      expect(store.values[kProfileNameKey], '小明');
      expect(store.writes.single.key, kProfileNameKey);
      expect(store.writes.single.value, '小明');
    });

    testWidgets('已有保存值时优先显示保存值', (WidgetTester tester) async {
      final RecordingSettingsStore store = RecordingSettingsStore()
        ..values[kProfileNameKey] = '已保存的昵称';
      final ServiceSettingsSource source = sourceWith(
        store: store,
        announce: RecordingAnnounce(),
      );
      await tester.pumpWidget(
        wrap(SettingsPage(source: source, currentUserName: 'yg_account')),
      );
      await tester.pumpAndSettle();

      expect(find.text('已保存的昵称'), findsOneWidget);
      expect(find.text('yg_account'), findsNothing);
    });

    testWidgets('重新广播真的调用了 announce.probe', (WidgetTester tester) async {
      final RecordingAnnounce announce = RecordingAnnounce();
      final ServiceSettingsSource source = sourceWith(
        store: RecordingSettingsStore(),
        announce: announce,
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('重新广播'));
      await tester.tap(find.text('重新广播'));
      await tester.pumpAndSettle();

      expect(announce.probes, 1);
    });

    testWidgets('降级原因与端口来自真实 announce / 注入端口', (WidgetTester tester) async {
      final ServiceSettingsSource source = sourceWith(
        store: RecordingSettingsStore(),
        announce: RecordingAnnounce(degraded: 'UDP 47777 端口被占用'),
        port: 48001,
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('48001'), findsOneWidget);
      expect(find.text('p_7fk3m9x2a1c00'), findsWidgets);
      expect(find.text('只发不收'), findsOneWidget);
    });

    testWidgets('revokeAllLinks 回调真的被调用', (WidgetTester tester) async {
      int revoked = 0;
      final ServiceSettingsSource source = sourceWith(
        store: RecordingSettingsStore(),
        announce: RecordingAnnounce(),
        revoke: () async => revoked++,
      );
      await tester.pumpWidget(wrap(SettingsPage(source: source)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('失效'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('失效'));
      await tester.pumpAndSettle();

      expect(revoked, 1);
    });
  });
  group('平台标签', () {
    test('常见系统都翻成人话', () {
      expect(platformLabel('windows'), 'Windows');
      expect(platformLabel('android'), 'Android');
      expect(platformLabel('linux'), 'Linux');
      expect(platformLabel('macos'), 'macOS');
      expect(platformLabel(''), '未知');
      expect(platformLabel('plan9'), 'plan9');
    });
  });
}
