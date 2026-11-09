// SPDX-License-Identifier: GPL-3.0-only

/// 设置页：QQ 风格的个人资料卡 + 分组卡片（本机信息 / 网络 / 安全 / 关于）。
///
/// 三条贯穿本页的约束：
/// 1. 每一项都**真的读写**：昵称走 store 的 profile.name，重新广播走 announce.probe，
///    失效链接走注入的 revokeAllLinks 回调——不做只改内存的假开关。
/// 2. 昵称优先使用外壳或服务中的资料，未连接服务时回落到平台默认昵称。
/// 3. 「被丢弃的包统计」必须显示真实计数与原因：没有它，用户无法区分
///    「没人广播」「验签全失败」「端口被占只发不收」这几种截然不同的故障。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/app_controls.dart';

import '../widgets/device_id_label.dart';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/assembly.dart';
import '../../app/network_diagnostics.dart';
import '../../core/discovery/announce_service_impl.dart';
import '../widgets/network_diagnostics_setting.dart';
import '../../app/branding/app_logo.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/identicon.dart';
import '../../core/contracts/contracts.dart';
import '../../core/discovery/peer_activity_tracker.dart';
import '../../core/platform/default_nickname.dart';
import '../../core/platform/device_platform.dart';
export '../../core/platform/device_platform.dart' show platformLabel;
import '../../core/platform/windows_firewall.dart';
import '../widgets/setting_row.dart';
import '../widgets/android_all_files_setting.dart';
import '../widgets/app_toast.dart';
import '../widgets/edit_name_dialog.dart';
import '../widgets/windows_startup_setting.dart';
import '../widgets/silent_startup_setting.dart';
import '../widgets/avatar_picker.dart';
import '../shell/close_behavior.dart';
import '../shell/startup_behavior.dart';

/// 昵称在 settings 表里的键。
const String kProfileNameKey = 'profile.name';

/// 分组之间的垂直间距：略大于卡片圆角，保证「一块压一块」但不散。
const double kSettingGroupGap = 18;

/// 昵称长度上限；与 profile API 的 kMaxProfileNameLength 保持一致。
const int kNicknameMaxLength = 64;

/// 应用名。
const String kAppName = '局域网简易文件';

/// 版本号（M0–M7 全部落地）。
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-beta.8',
);

/// 许可标识。
const String kAppLicense = 'GPL-3.0-only';

/// 一次渲染所需的全部数据快照。
///
/// 抽成平面值对象而不是让页面直接读 AppServices：页面只依赖快照，
/// 测试就能在不启动 UDP / HTTP 的前提下注入任意组合，
/// 同时生产侧由 [ServiceSettingsSource] 从真实服务填充。
final class SettingsSnapshot {
  /// 构造快照。
  const SettingsSnapshot({
    required this.nickname,
    required this.peerId,
    required this.port,
    required this.platform,
    required this.onlinePeers,
    required this.degradedReason,
    required this.rejectedBadSignature,
    required this.rejectedMalformed,
    required this.rejectedFromSelf,
    required this.rejectedUnknownPeerId,
    required this.recentReasons,
    this.transportErrors = 0,
    this.transportReasons = const [],
  });

  /// 当前昵称（已保存值，没有则回落登录账户名）。
  final String nickname;

  /// 本机 peerId。
  final String peerId;

  /// 实际监听端口。
  final int port;

  /// 操作系统展示名。
  final String platform;

  /// 当前在线 peer 数。
  final int onlinePeers;

  /// 降级为「只发不收」的原因；未降级为 null。
  final String? degradedReason;

  /// 验签失败计数。
  final int rejectedBadSignature;

  /// 畸形包计数。
  final int rejectedMalformed;

  /// 自己的回环包计数（正常现象，单独展示）。
  final int rejectedFromSelf;

  /// 非法 peerId 计数。
  final int rejectedUnknownPeerId;

  /// 最近若干条丢弃原因。
  final List<String> recentReasons;
  final int transportErrors;
  final List<String> transportReasons;

  /// 是否已降级为只发不收。
  bool get isSendOnly => degradedReason != null && degradedReason!.isNotEmpty;

  /// 真正的「错误丢弃」总数：不含 fromSelf（那是自己的回环，不是故障）。
  int get totalRejected =>
      rejectedBadSignature + rejectedMalformed + rejectedUnknownPeerId;

  /// 只替换昵称，其余字段保持不变。
  SettingsSnapshot copyWith({String? nickname}) => SettingsSnapshot(
    nickname: nickname ?? this.nickname,
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
    transportErrors: transportErrors,
    transportReasons: transportReasons,
  );

  /// 是否一条邻居都看不到，且确实在丢包——这正是需要提示用户的场景。
  bool get peersMissingWithDrops => onlinePeers == 0 && totalRejected > 0;
}

/// 设置页的数据源：把页面需要的读写收成一个窄接口。
///
/// 页面只认这个接口；生产实现 [ServiceSettingsSource] 直接调用 AppServices，
/// 测试实现则在内存里记账，从而断言「点击真的调用了 probe / revokeAllLinks」。
abstract interface class SettingsSource {
  /// 读出当前快照。
  Future<SettingsSnapshot> load();

  /// 保存昵称（必须真的落库）。
  Future<void> saveNickname(String name);

  /// 立即向局域网广播一次。
  Future<void> probe();

  /// 立即失效所有分享链接。
  Future<void> revokeAllLinks();
}

/// 无服务时的离线快照：静态信息（版本、许可证、默认昵称）照常可见，
/// 动态项（peerId / 端口 / 在线数 / 丢弃统计）标成「—」并置为不可用。
///
/// 存在的理由：整页替换成「未连接服务」会让用户在服务没起来时
/// 连「这是什么软件、什么许可」都看不到，那是信息缺失，不是降级。
final class OfflineSettingsSource implements SettingsSource {
  /// [userName] 是本机登录账户名，作为昵称默认值显示。
  const OfflineSettingsSource({required this.userName});

  final String userName;

  @override
  Future<SettingsSnapshot> load() async => SettingsSnapshot(
    nickname: userName,
    peerId: '—',
    port: 0,
    platform: platformLabel(''),
    onlinePeers: 0,
    degradedReason: '本机服务未启动：发现、分享与传输均不可用。',
    rejectedBadSignature: 0,
    rejectedMalformed: 0,
    rejectedFromSelf: 0,
    rejectedUnknownPeerId: 0,
    recentReasons: const <String>[],
  );

  @override
  Future<void> saveNickname(String name) async {
    throw const LanFileException(
      LanFileErrorCode.unsupported,
      '本机服务未启动，暂时无法保存昵称',
    );
  }

  @override
  Future<void> probe() async {
    throw const LanFileException(
      LanFileErrorCode.unsupported,
      '本机服务未启动，无法重新广播',
    );
  }

  @override
  Future<void> revokeAllLinks() async {
    throw const LanFileException(
      LanFileErrorCode.unsupported,
      '本机服务未启动，无法吊销链接',
    );
  }
}

/// 由真实服务支撑的数据源。
///
/// 依赖刻意收窄成它真正需要的五个端口，而不是整个 [AppServices]：
/// AppServices 里 discovery / remoteFiles / offers / messaging 全是 final 具体类，
/// 拿它当依赖就没法在不启动 UDP、不建库的前提下测「昵称真的写进 store」。
/// 窄端口让生产与测试走的是同一条代码路径。
final class ServiceSettingsSource implements SettingsSource {
  /// [revokeAllLinksFn] 由外壳注入（见报告中的接线说明）。
  const ServiceSettingsSource({
    required this.store,
    required this.announce,
    required this.selfPeerId,
    required this.serverPort,
    required this.currentUserName,
    required this.revokeAllLinksFn,
    this.renameSelfFn,
    this.tracker,
    this.rejected,
    this.platformName,
  });

  /// 持久化门面；昵称读写都走它。
  final LanFileStore store;

  /// 公告服务；提供 probe 与降级状态。
  final AnnounceService announce;

  /// 本机 peerId。
  final PeerId selfPeerId;

  /// 实际监听端口。
  final int serverPort;

  /// 本机登录账户名，作为昵称的兜底值。
  final String currentUserName;

  /// 「立即失效所有链接」的实现。
  ///
  /// 做成回调而不是页面自己 new 一个 TokenRevocationStore：
  /// 吊销表实例必须与签名校验用的是**同一个**，否则吊销了也没人认。
  final Future<void> Function() revokeAllLinksFn;

  /// 改名的完整实现（写 store + profile + peers 表三处）。
  ///
  /// 为 null 时只写 store —— 那是**降级**，会让「本地改了、别人看到的还是旧名」。
  /// 生产由 [AppServices.renameSelf] 注入。
  final Future<void> Function(String name)? renameSelfFn;

  /// 在线 peer 的来源；为 null 时视为「未知」，按 0 处理。
  final PeerActivityTracker? tracker;

  /// 丢弃计数来源；为 null 时退化为 announce.rejected。
  final RejectedDatagramCounter? rejected;

  /// 操作系统展示名；为 null 时按当前平台推断。
  final String? platformName;

  @override
  Future<SettingsSnapshot> load() async {
    final String? saved = await store.getSetting(kProfileNameKey);
    final RejectedDatagramCounter counter = rejected ?? announce.rejected;
    return SettingsSnapshot(
      nickname: (saved == null || saved.trim().isEmpty)
          ? currentUserName
          : saved.trim(),
      peerId: selfPeerId.value,
      port: serverPort,
      platform: platformName ?? platformLabel(Platform.operatingSystem),
      onlinePeers: tracker?.onlineCount ?? 0,
      degradedReason: announce.degradedReason,
      rejectedBadSignature: counter.badSignature,
      rejectedMalformed: counter.malformed,
      rejectedFromSelf: counter.fromSelf,
      rejectedUnknownPeerId: counter.unknownPeerId,
      recentReasons: counter.recentReasons,
      transportErrors: counter is MutableRejectedCounter
          ? counter.transportErrors
          : 0,
      transportReasons: counter is MutableRejectedCounter
          ? counter.transportReasons
          : const [],
    );
  }

  @override
  Future<void> saveNickname(String name) async {
    final Future<void> Function(String)? full = renameSelfFn;
    if (full != null) {
      await full(name);
      return;
    }
    // 降级：只写持久化，不同步 ping 与 peers 表。
    await store.setSetting(kProfileNameKey, name);
  }

  @override
  Future<void> probe() => announce.probe();

  @override
  Future<void> revokeAllLinks() => revokeAllLinksFn();
}

/// 设置页面本体。
class SettingsPage extends StatefulWidget {
  /// [services] 为 null 时整页显示「未连接服务」，不崩。
  ///
  /// [source] 可注入数据源；为空时从 [services] 现建。
  /// [currentUserName] 是本机登录账户名，作为昵称初始值。
  const SettingsPage({
    super.key,
    this.services,
    this.source,
    this.currentUserName,
    this.revokeAllLinks,
    this.renameSelf,
    this.allowLanAccess,
    this.avatarPicker,
    this.saveAvatar,
    this.avatarBytes,
  });

  /// 装配好的服务栈。
  final AppServices? services;

  /// 可注入的数据源。
  final SettingsSource? source;

  /// 本机昵称；未注入时使用服务资料或平台默认值。
  final String? currentUserName;

  /// 外壳注入的「立即失效所有链接」实现。
  final Future<void> Function()? revokeAllLinks;

  /// 外壳注入的改名实现（写 store + profile + peers 表三处）。
  ///
  /// 为 null 时页面退回「只写 store」的降级路径 —— 那是真的降级，
  /// 会让别的节点 ping 到的还是旧名字，不要当成正常路径。
  final Future<void> Function(String name)? renameSelf;

  /// 可注入的防火墙操作；Windows 默认使用当前程序和实际监听端口。
  final Future<String?> Function(int port)? allowLanAccess;
  final Future<Uint8List?> Function()? avatarPicker;
  final Future<void> Function(Uint8List? bytes)? saveAvatar;
  final Uint8List? avatarBytes;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSource? _source;
  SettingsSnapshot? _snapshot;
  Object? _loadError;
  bool _busy = false;
  bool _choosingNickname = false;
  Uint8List? _avatar;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? _buildSource();
    _avatar = widget.avatarBytes ?? widget.services?.avatars?.selfBytes;
    _reload();
  }

  /// 未注入 source 时，从真实服务栈组一个（依赖收窄成窄端口）。
  ///
  /// services 为 null 时**不返回 null**：返回一个离线快照源，让「关于」
  /// （版本、许可证）与默认昵称仍然可见。整页显示「未连接」会让用户在
  /// 服务未启动时连自己用的是什么软件、什么许可都看不到，那是信息缺失。
  SettingsSource? _buildSource() {
    final AppServices? services = widget.services;
    if (services == null) {
      return OfflineSettingsSource(userName: _userName);
    }
    return ServiceSettingsSource(
      store: services.store,
      announce: services.announce,
      selfPeerId: services.identity.peerId,
      serverPort: services.port,
      currentUserName: _userName,
      // 没注入回调时不假装能吊销：数据源照样可用，但按钮会明确提示不可用。
      revokeAllLinksFn: widget.revokeAllLinks ?? () async {},
      // 改名走 services.renameSelf：一次写 store + profile + peers 表三处。
      // 不走它就会出现「本地改了、别人 ping 到的还是旧名」。
      renameSelfFn: widget.renameSelf ?? services.renameSelf,
    );
  }

  /// 昵称兜底值：注入值优先，否则取登录账户名。
  String get _userName {
    final String? injected = widget.currentUserName;
    if (injected != null && injected.trim().isNotEmpty) {
      return injected.trim();
    }
    return widget.services?.profile.name ?? resolveDefaultNickname();
  }

  /// 没有注入 revokeAllLinks 时按钮不可用（不撒谎）。
  bool get _revokeAvailable =>
      widget.source != null || widget.revokeAllLinks != null;

  Future<void> _reload() async {
    final SettingsSource? source = _source;
    if (source == null) return;
    try {
      final SettingsSnapshot snapshot = await source.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (mounted) AppToast.show(context, message, isError: isError);
  }

  Future<void> _editNickname() async {
    final snapshot = _snapshot;
    if (_busy || _choosingNickname || snapshot == null) return;
    setState(() => _choosingNickname = true);
    try {
      final name = await showAppDialog<String>(
        context: context,
        builder: (_) => EditNameDialog(
          title: '修改昵称',
          label: '昵称',
          initialValue: snapshot.nickname,
          maxLength: kNicknameMaxLength,
          fieldKey: const ValueKey('nickname-field'),
        ),
      );
      if (name != null && mounted) await _saveNickname(name);
    } finally {
      if (mounted) setState(() => _choosingNickname = false);
    }
  }

  Future<void> _saveNickname(String raw) async {
    final SettingsSource? source = _source;
    if (source == null) return;
    final String name = raw.trim();
    if (name.isEmpty) {
      _notify('昵称不能为空', isError: true);
      return;
    }
    if (name.runes.length > kNicknameMaxLength) {
      _notify('昵称最多 $kNicknameMaxLength 个字符', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await source.saveNickname(name);
      final SettingsSnapshot? old = _snapshot;
      if (!mounted) return;
      setState(() {
        // 快照本地同步更新，避免改完名字界面还显示旧值。
        _snapshot = old?.copyWith(nickname: name);
        _busy = false;
      });
      _notify('昵称已保存');
    } on Object catch (error) {
      if (!mounted) return;
      // 失败必须说出来，不能静默回滚。
      setState(() {
        _busy = false;
      });
      _notify('昵称保存失败：$error', isError: true);
    }
  }

  Future<void> _changeAvatar({bool reset = false}) async {
    final Future<void> Function(Uint8List?)? save =
        widget.saveAvatar ?? widget.services?.changeAvatar;
    if (save == null || _busy) return;
    setState(() => _busy = true);
    try {
      final Uint8List? bytes = reset
          ? null
          : await (widget.avatarPicker ?? pickAvatar)();
      if (!reset && bytes == null) return;
      await save(bytes);
      if (!mounted) return;
      setState(() {
        _avatar = bytes;
      });
      _notify(reset ? '已恢复默认头像' : '头像已保存');
    } on Object catch (error) {
      _notify('头像保存失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _probe() async {
    final SettingsSource? source = _source;
    if (source == null) return;
    setState(() => _busy = true);
    try {
      await source.probe();
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify('已重新广播，正在等待邻居回应');
      await _reload();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify('重新广播失败：$error', isError: true);
    }
  }

  Future<void> _revokeAll() async {
    final SettingsSource? source = _source;
    if (source == null) return;
    setState(() => _busy = true);
    try {
      await source.revokeAllLinks();
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify('已失效所有分享链接');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify('操作失败：$error', isError: true);
    }
  }

  Future<void> _allowLanAccess() async {
    final int port = _snapshot?.port ?? 0;
    if (port == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final String? error =
          await (widget.allowLanAccess ?? allowWindowsLanAccess)(port);
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify(error ?? '已允许私人网络中的本地子网访问端口 $port', isError: error != null);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      _notify('防火墙设置失败：$error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final SettingsSnapshot? snapshot = _snapshot;
    final closeBehavior = CloseBehaviorScope.maybeOf(context);

    if (_loadError != null && snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '读取设置失败：$_loadError',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: tokens.fgDim),
          ),
        ),
      );
    }
    if (snapshot == null) {
      return const Center(child: MiuixCircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ProfileCard(
                      snapshot: snapshot,
                      busy: _busy || _choosingNickname,
                      onEditNickname: _editNickname,
                      avatarBytes: _avatar,
                      onChangeAvatar:
                          widget.saveAvatar != null ||
                              widget.services?.avatars != null
                          ? () => _changeAvatar()
                          : null,
                      onResetAvatar: _avatar == null
                          ? null
                          : () => _changeAvatar(reset: true),
                    ),
                    const SizedBox(height: kSettingGroupGap),
                    SettingGroup(
                      title: '应用 Logo',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              for (final logo in AppLogo.values)
                                Expanded(child: _LogoOption(logo: logo)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: kSettingGroupGap),
                    if (closeBehavior != null) ...[
                      SettingGroup(
                        title: '窗口与托盘',
                        children: [
                          if (Platform.isWindows) const WindowsStartupSetting(),
                          if (StartupBehaviorScope.maybeOf(context)
                              case final startup?)
                            SilentStartupSetting(behavior: startup),
                          SettingRow(
                            label: '关闭窗口时',
                            subtitle: '缩回托盘后仍可通过托盘图标打开客户端',
                            trailing: ValueListenableBuilder<CloseAction>(
                              valueListenable: closeBehavior,
                              builder: (context, action, _) =>
                                  MiuixOverlayDropdownMenu(
                                    title: action.label,
                                    enabled: !_busy,
                                    insideMargin: const EdgeInsets.all(8),
                                    entry: MiuixDropdownEntry(
                                      items: [
                                        for (final value in CloseAction.values)
                                          MiuixDropdownItem(
                                            text: value.label,
                                            selected: value == action,
                                            onClick: () async {
                                              try {
                                                await closeBehavior.setAction(
                                                  value,
                                                );
                                                if (mounted) {
                                                  _notify('关闭行为已保存');
                                                }
                                              } on Object catch (error) {
                                                if (mounted) {
                                                  _notify(
                                                    '保存失败：$error',
                                                    isError: true,
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: kSettingGroupGap),
                    ],
                    SettingGroup(
                      title: '本机信息',
                      children: <Widget>[
                        SettingRow(
                          label: '设备标识',
                          subtitle: '用于在局域网内稳定识别这台设备，与 IP 无关',
                          value: snapshot.peerId,
                        ),
                        SettingRow(
                          label: '监听端口',
                          subtitle: 'HTTP 服务实际使用的端口',
                          value: snapshot.port.toString(),
                        ),
                        SettingRow(label: '操作系统', value: snapshot.platform),
                        SettingRow(
                          label: '在线邻居',
                          subtitle: '当前收到公告且在线的设备数',
                          value: snapshot.onlinePeers.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: kSettingGroupGap),
                    SettingGroup(
                      title: '网络',
                      children: <Widget>[
                        if (snapshot.transportErrors > 0)
                          SettingRow(
                            label: '发现通道错误',
                            value: snapshot.transportErrors.toString(),
                            subtitle: snapshot.transportReasons.reversed
                                .take(3)
                                .join('\n'),
                          ),
                        if (widget.services?.localDomain != null)
                          StreamBuilder<void>(
                            stream: widget.services!.localDomain!.changes,
                            builder: (context, _) {
                              final domain = widget.services!.localDomain!;
                              final url = Uri(
                                scheme: 'http',
                                host: domain.host ?? '',
                                port: widget.services!.browserPort,
                              ).toString();
                              return SettingRow(
                                label: '本机局域网域名',
                                value: domain.host ?? '正在注册',
                                subtitle: domain.ready
                                    ? '昵称与设备 ID 绑定本机 · 点击复制访问地址'
                                    : domain.error ?? '正在检查域名是否重名',
                                onTap: domain.ready
                                    ? () => Clipboard.setData(
                                        ClipboardData(text: url),
                                      )
                                    : null,
                              );
                            },
                          ),
                        SettingRow(
                          label: '公告通道',
                          // 有降级原因时**原样显示原因**，不要一句笼统的
                          // 「端口被占用」——用户排障要的是具体原因（哪个端口、
                          // 是服务没起还是被占）。
                          subtitle: snapshot.isSendOnly
                              ? (snapshot.degradedReason ?? '当前只能发送公告、收不到别人的公告')
                              : '广播与组播正常，可以收发公告',
                          trailing: _StatusPill(
                            text: snapshot.isSendOnly ? '只发不收' : '正常',
                            warn: snapshot.isSendOnly,
                          ),
                        ),
                        SettingRow(
                          label: '重新广播',
                          subtitle: '立即向局域网发一次探测，等待所有邻居回包',
                          trailing: const Icon(LucideIcons.megaphone, size: 18),
                          onTap: _busy ? null : _probe,
                        ),
                        if (Platform.isWindows || widget.allowLanAccess != null)
                          SettingRow(
                            label: '允许局域网访问',
                            trailing: const Icon(
                              LucideIcons.shieldCheck,
                              size: 18,
                            ),
                            onTap: _busy || snapshot.port == 0
                                ? null
                                : _allowLanAccess,
                          ),
                      ],
                    ),
                    const SizedBox(height: kSettingGroupGap),
                    if (Platform.isAndroid) ...[
                      const SettingGroup(
                        title: '文件访问',
                        children: [AndroidAllFilesSetting()],
                      ),
                      const SizedBox(height: kSettingGroupGap),
                    ],
                    _SecurityGroup(
                      snapshot: snapshot,
                      busy: _busy,
                      revokeAvailable: _revokeAvailable,
                      onRevokeAll: _revokeAll,
                    ),
                    const SizedBox(height: kSettingGroupGap),
                    if (NetworkDiagnostics.active != null) ...[
                      const SettingGroup(
                        title: '帮助与诊断',
                        children: [NetworkDiagnosticsEntry()],
                      ),
                      const SizedBox(height: kSettingGroupGap),
                    ],
                    const SettingGroup(
                      title: '关于',
                      children: <Widget>[
                        SettingRow(label: '应用名', value: kAppName),
                        SettingRow(label: '版本', value: kAppVersion),
                        SettingRow(
                          label: '开源许可',
                          subtitle:
                              '本项目以 GPL-3.0-only 发布，'
                              '分发修改版必须同样开源；完整条款见随包的 LICENSE 文件',
                          value: kAppLicense,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoOption extends StatelessWidget {
  const _LogoOption({required this.logo});
  final AppLogo logo;
  @override
  Widget build(BuildContext context) {
    final controller = LogoScope.maybeOf(context);
    final selected = (controller?.value ?? AppLogo.chatFolder) == logo;
    final tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: MiuixPressable(
        key: ValueKey('logo-option-${logo.name}'),
        borderRadius: BorderRadius.circular(12),
        onPressed: controller == null
            ? null
            : () async {
                try {
                  await controller.select(logo);
                } on Object catch (error) {
                  if (context.mounted) {
                    AppToast.show(context, '切换 Logo 失败：$error', isError: true);
                  }
                }
              },
        child: MiuixCard(
          insideMargin: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          colors: MiuixCardColors(
            color: selected
                ? MiuixTheme.of(context).colors.secondaryContainer
                : tokens.surface,
            contentColor: selected ? tokens.accent : tokens.fg,
          ),
          child: Column(
            children: [
              AppLogoImage(logo: logo, size: 48),
              const SizedBox(height: 10),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(12) * 2.6,
                child: Center(
                  child: Text(
                    logo.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: selected ? tokens.accent : tokens.fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selected ? '使用中' : '点击使用',
                style: TextStyle(fontSize: 11, color: tokens.fgDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部个人资料卡：头像 + 可改昵称 + peerId 小字。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.snapshot,
    required this.busy,
    required this.onEditNickname,
    this.avatarBytes,
    this.onChangeAvatar,
    this.onResetAvatar,
  });

  final SettingsSnapshot snapshot;
  final bool busy;
  final VoidCallback onEditNickname;
  final Uint8List? avatarBytes;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onResetAvatar;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final SettingsSnapshot s = snapshot;
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 头像：未设置自定义头像时永远显示 identicon（计划 §7.2）。
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppTooltip(
                message: '修改头像',
                child: MiuixPressable(
                  key: const ValueKey<String>('change-avatar'),
                  onPressed: busy ? null : onChangeAvatar,
                  borderRadius: BorderRadius.circular(
                    LanFileMetrics.radiusCard,
                  ),
                  child: PeerAvatar(
                    peerId: s.peerId,
                    avatarBytes: avatarBytes,
                    size: LanFileMetrics.avatarLarge,
                  ),
                ),
              ),
              if (onChangeAvatar != null || onResetAvatar != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onChangeAvatar != null)
                      AppIconButton(
                        key: const ValueKey('edit-avatar-button'),
                        tooltip: '修改头像',
                        onPressed: busy ? null : onChangeAvatar,
                        icon: const Icon(LucideIcons.camera, size: 18),
                      ),
                    if (onResetAvatar != null)
                      AppIconButton(
                        key: const ValueKey('reset-avatar-button'),
                        tooltip: '恢复默认头像',
                        onPressed: busy ? null : onResetAvatar,
                        icon: const Icon(LucideIcons.rotateCcw, size: 18),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  s.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 4),
                DeviceIdLabel(id: s.peerId),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppIconButton(
            tooltip: '修改昵称',
            icon: Icon(LucideIcons.pencil, size: 18, color: tokens.fgDim),
            onPressed: busy ? null : onEditNickname,
          ),
        ],
      ),
    );
  }
}

/// 安全分组：丢弃统计 + 失效链接。
class _SecurityGroup extends StatelessWidget {
  const _SecurityGroup({
    required this.snapshot,
    required this.busy,
    required this.revokeAvailable,
    required this.onRevokeAll,
  });

  final SettingsSnapshot snapshot;
  final bool busy;
  final bool revokeAvailable;
  final Future<void> Function() onRevokeAll;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final SettingsSnapshot s = snapshot;
    final int total = s.totalRejected;
    final String dropSubtitle = total == 0
        ? '没有丢弃记录'
        : '验签失败 ${s.rejectedBadSignature} · 畸形包 ${s.rejectedMalformed} '
              '· 非法 peerId ${s.rejectedUnknownPeerId}';
    final String revokeSubtitle = revokeAvailable
        ? '把已签发的分享凭证全部加入吊销表，旧链接立刻返回 410'
        : '当前没有接入吊销通道，此项不可用';
    return SettingGroup(
      title: '安全',
      children: <Widget>[
        SettingRow(
          label: '被丢弃的数据包',
          subtitle: dropSubtitle,
          value: total.toString(),
        ),
        if (s.rejectedFromSelf > 0)
          SettingRow(
            label: '自身回环包',
            subtitle: '抓到自己发出的公告属正常现象，不计入故障',
            value: s.rejectedFromSelf.toString(),
          ),
        if (s.recentReasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LanFileMetrics.rowPaddingH,
              2,
              LanFileMetrics.rowPaddingH,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '最近丢弃原因',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.fgDim,
                  ),
                ),
                const SizedBox(height: 4),
                for (final String reason in s.recentReasons.reversed.take(5))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '· $reason',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: tokens.fgDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (s.peersMissingWithDrops)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LanFileMetrics.rowPaddingH,
              6,
              LanFileMetrics.rowPaddingH,
              10,
            ),
            child: Text(
              '一个邻居也看不到，同时有 $total 个包被丢弃。'
              '请检查：对方是否在同一网段、防火墙是否放行 UDP 47777、'
              '以及是否处于 AP 隔离环境。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: tokens.fgDim,
              ),
            ),
          ),
        SettingRow(
          label: '立即失效所有链接',
          subtitle: revokeSubtitle,
          trailing: revokeAvailable
              ? _DangerButton(onPressed: busy ? null : onRevokeAll)
              : const _StatusPill(text: '不可用', warn: true),
        ),
      ],
    );
  }
}

/// 一个小圆角状态标签；警示态用 accent 描边而不是换色相。
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return MiuixBadge(
      containerColor: warn ? tokens.accent.withValues(alpha: .12) : tokens.bg,
      contentColor: warn ? tokens.accent : tokens.fgDim,
      child: Text(text),
    );
  }
}

/// 危险操作按钮：双色约束下没有红色，用 accent 描边 + 主色文字表达。
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onPressed,

      child: const Text('失效', style: TextStyle(fontSize: 12)),
    );
  }
}
