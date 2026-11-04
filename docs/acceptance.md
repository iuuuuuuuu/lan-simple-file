# M0 验收台

本文件是 M0 阶段结束时的验收清单与**真实执行记录**。
原则：**每条都必须真跑**，编译过、单测绿、SHA 对上都不算。

## 1. 契约层（Lead 执行）

- [x] `lib/core/contracts/` 8 个文件写入并冻结，后续无越权改动
- [x] `flutter analyze lib` → No issues found
- [x] 许可头门禁 `dart run tool/check_license_headers.dart` 能真红：
      首次运行抓到 `lib/main.dart` 缺 SPDX 头，exit=1；补齐后 exit=0

## 2. 模块验收（Lead 逐项跑真实命令，不采信汇报）

| 模块 | 用例数 | 命令 | 结果 |
|---|---|---|---|
| 身份与凭证 | 75 | `flutter test test/core/identity` | exit 0，All tests passed |
| 桌面 FileRef | 82（含 SAF 的 22） | `flutter test test/core/files` | exit 0，All tests passed |
| HTTP 服务 | 71 | `flutter test test/core/server` | exit 0，All tests passed |
| 持久化 | 24 | `flutter test test/core/store` | exit 0，All tests passed |
| 主题 / identicon / 外壳 | 58 | `flutter test test/app` | exit 0，All tests passed |
| 全仓静态分析 | — | `flutter analyze lib test` | exit 0，No issues found |

## 3. 端到端（Lead 自己写、自己跑，不交给模块作者）

`test/e2e/m0_acceptance_test.dart` —— 8 条，exit 0：

1. 同一 seed 派生同一 peerId，且过得了契约正则（长度 15）
2. A 签 token，B 用 A 的公钥离线验签通过
3. 篡改 payload 里的 issuer → 验签必须失败
4. 未知 issuer → 被拒，不静默通过
5. token 内不得含任何网络地址（192.168 / 127.0.0.1 / http:// / 47778 全部断言为 false）
6. 真实目录树：列举 → itemKey → 反向解析 → 读内容一致
7. 路径穿越 4 变体在编解码层被拒
8. **32MB 真实文件**分片读取（块大小故意用 1MB+7 非对齐），拼接后 sha256 与原文件一致

`test/e2e/store_persistence_test.dart` —— 5 条，exit 0：

1. 真实落盘：写入 share → close → reopen → 数据仍在且**逐字段**一致
2. upsert 幂等：同 id 写两次只留一条，字段更新生效
3. revokeShare 后仍能查到 revokedAt（撤销要可查，不能整条消失）
4. 消息幂等：同 id 写两次不重复
5. settings 跨 reopen 持久

> 注意第 1 条同时断言了 `dbFile.lengthSync() > 0`——防止把数据写进内存模式却谎称落盘。

## 4. 应用可运行

- [x] `flutter build windows --release` → `√ Built ...\lan_simple_file.exe`
- [x] 启动探针：`pid=80612 alive=True hasWindow=True`
- [x] 窗口截图取证（PrintWindow，不抢焦点、不动鼠标）：
      [docs/screenshots/m0_app.png](screenshots/m0_app.png)
      人工判读：左侧 5 个 tab（附近 / 我的分享 / 群组 / 传输 / 设置）、默认选中「附近」、
      明色主题、主区显示「附近的人」空态。**不是全黑、不是锁屏。**

## 5. 门禁的"能真红"证明（反假绿）

| 门禁 | 故障注入方式 | 结果 |
|---|---|---|
| 许可头 | 缺 SPDX 头的 `lib/main.dart` | 抓到并 exit=1，补齐后 exit=0 |
| 413 回归 | server-dev 把 drain 改回「中途 throw」 | 3 条用例立即复现连接重置，恢复后全绿 |
| 决策笔记 | 注入缺必备章节的笔记 | format 门禁 passed=false 并逐条报缺失 |

## 6. 未验证项（如实记录，不掩盖）

1. **APK 打包未跑通**：本机无网络，Gradle 9.3.1 分发包与 AGP plugin marker 无法下载。
   Kotlin 侧改用 kotlin-compiler-embeddable 独立编译做了等价类型检查（EXITCODE=0，产出 11 个 .class），
   但**这不是 APK 打包验证**，需在有网机补 `flutter build apk --debug`。
2. **Android 真机全部未验证**：SAF provider 行为、大目录分页、4GB+ 偏移、撤权后 canRead、
   Activity 重建时序、句柄驱逐压测。
3. **跨设备连通未验证**：Windows↔Android 实网、防火墙放行、AP 隔离环境。
4. **跨操作系统 identicon 一致性未实测**：只有 Windows 一台机器，
   「同一字符串各平台逐字节相同」靠纯函数构造（整数运算、无浮点、无平台 API）保证；
   需在 mac/Linux 上跑 `test/app/identicon_test.dart` 的固定快照用例才能闭环。
5. **符号链接逃逸**在本机 skip（无 SeCreateSymbolicLinkPrivilege），junction 逃逸真跑通过。
6. **30GB / 100GB 真实大文件**未测，用 32MB 端到端 + 5GiB 稀疏文件（模块内）验证 int64 路径。
7. 真实 50 万项目录未做压力测试。
## 7. 最终回归（2026-11-04 07:35，全部真跑）

| 套件 | 用例 | 结果 |
|---|---|---|
| test/core/identity | 75 | All tests passed |
| test/core/files | 82 | All tests passed |
| test/core/store | 27 | All tests passed |
| test/core/server | 71 | All tests passed |
| test/app | 58 | All tests passed |
| test/e2e（Lead 亲写） | 13 | All tests passed |
| **合计** | **326** | 全绿 |

`flutter analyze lib test` → No issues found（含 444KB 生成物）
`dart run tool/check_license_headers.dart` → 真实退出码 0（63 个文件）

> 判读陷阱记录：用 PowerShell 管道跑 dart 时，`$LASTEXITCODE` 可能被 dart 写到 stderr 的
> 构建钩子日志污染成 1。真实退出码必须用 `*> log` 重定向后单独取 `$LASTEXITCODE`，
> 不能看 `$? ` 或管道末尾。

## 8. 应用二次验证（schema 改动后重建）

- `flutter build windows --release` → Built `lan_simple_file.exe`
- 启动探针：`alive=True hasWindow=True`

## 9. 本阶段产出的决策笔记

9 篇，全部通过 tree / format 门禁（`agent_notes_gate` passed=true，strayCount=0）。
新增第 9 篇：[offer origin 必须落成真实列](../.agents/notes/implemented/architecture/2026-11-04-offer-origin-as-real-column.md)
——记录「用 from_session 推导 origin」为何被否，以及它会在会话清理时静默漂移成 peer。
## 10. M1–M5 阶段验收（2026-11-04 08:30）

### 10.1 全量回归：629 条用例，12 个套件，真实退出码

| 套件 | 用例 | 退出码 |
|---|---|---|
| test/core/identity | 75 | 0 |
| test/core/files | 82 | 0 |
| test/core/store | 27 | 0 |
| test/core/server | 71 | 0 |
| test/app | 58 | 0 |
| test/core/discovery | 42 | 0 |
| test/core/shares | 61 | 0 |
| test/core/transfer | 47 | 0 |
| test/core/messaging | 56 | 0 |
| test/core/groups | 41 | 0 |
| test/core/server_share | 35 | 0 |
| test/e2e（Lead 亲写） | 34 | 0 |
| **合计** | **629** | 全绿 |

`flutter analyze lib test` -> No issues found（含 444KB drift 生成物）

### 10.2 真实启动：应用对外提供 HTTP 服务

`flutter build windows --release` -> Built lan_simple_file.exe（46.8s）

启动后 **curl 探针实测**：
```
alive=True hasWindow=True
PORT=47778 STATUS=200
BODY={"peerId":"p_jpzsvuhxef46s","name":"公司电脑-M600","proto":2}
```
即：应用真的起来了、真的绑上了 47778、真的响应了 API，peerId 是真实派生的。

### 10.3 界面亲眼确认

截图：[docs/screenshots/m1_app_live.png](screenshots/m1_app_live.png)（PrintWindow，不抢焦点不动鼠标）

人工判读：左侧 5 个 tab（附近/我的分享/群组/传输/设置）、选中「附近」高亮、
明色主题、主区空状态「附近的人」+ 说明「M1 实现：局域网发现、在线状态、逐层浏览他人共享。」
**不是全黑、不是锁屏。**

### 10.4 组装层（Lead 亲自写，唯一接线处）

`lib/app/assembly.dart`——各模块互不 import，全靠这里适配：
- `StorePublicKeyLookup`：凭证验证方自证 issuer 的公钥来源
- `StorePeerUpsertSink`：验签通过的公告落 peers 表
- `DiscoveryOnlineProbe` / `DiscoveryGroupOnlineProbe`：发现层活动表到共享/群组两个**同名不同接口**的探测
- `AppAssembler.assemble()`：身份 -> 存储 -> 凭证 -> HTTP（端口回填）-> 发现 -> 消息（注入 keys+verifier）-> 共享

组装层 5 条真实集成用例（`test/e2e/assembly_test.dart`）：
HTTP 真实响应 / 本机记录进 peers 表 / 公钥可查且未知返回 null /
分享创建落库且链接不含网络地址 / **重启后身份稳定且数据仍在**

### 10.5 本阶段 Lead 亲自发现并修复的缺陷

| 缺陷 | 怎么发现的 | 修法 |
|---|---|---|
| `MessageSignature` 用 `codeUnits` 截断非 ASCII，'A' 与 'Ł' 签名碰撞 | store-dev 实测探针 COLLIDE=true | 改 utf8.encode；故障注入验证 4 条用例真红 |
| 契约要求消息签名但 `MessageRecord.sig` 恒空（能签不能验） | store-dev 报告 + 我自己复核 | 补 MessageSignature 契约 + 收侧验签（keys/verifier 注入） |
| `LanFileStore` 零个群组方法，但三张群表已建 | ui-dev 报告 | 补 7 个方法 + GroupRecord/GroupMemberRecord + 真实落盘验证 |
| `MessageRecord.deletedBy` 契约有字段、表无列，静默丢失 | ui-dev 往返探针 READ_BACK=null | 加列 + 双向映射 + build_runner 重生成 |
| `_cachedSettings` 内存缓存导致 reopen 后 `isArchived` 恒 false | 我自己的 e2e 用例变红 | 改真查 settings 表，删缓存 |
| `Offers` 表无 origin 列，靠 from_session 推导会静默漂移 | store-dev 报告 | 加列 + 变异测试证明两方向都能红 |

### 10.6 队友做过的反假绿证明（我认可）

- identity-dev：故障注入跳过验签 -> 用例 red；端口降级路径用探针实测出真实触发条件（errno 10013）
- server-dev：413 修复改回中途 throw -> 3 条用例复现连接重置
- store-dev：origin 推导塞回去 -> 两方向用例同时红；sig 强制置空 -> 5 条红
- saf-dev：自己写的 `const LanFileConstantsTreePageSize = 200` 恒真假断言被自己揪出并改真读契约
- ui-dev：identicon 网格碰撞是规格上限（32768 种）不是实现错，改成两条用例（可见结果强断言 + 碰撞率诚实区间）

### 10.7 仍未验证（诚实清单）

1. **安卓 APK 未打包**：本机无网，Gradle 分发包缺失。需有网机补 `flutter build apk`。
2. **安卓真机全部未验证**：SAF、前台服务、ACTION_SEND、权限引导。
3. **跨设备真实连通未验证**：Windows<->Android 实网、防火墙、AP 隔离、路由器组播转发。
4. **跨操作系统 identicon 一致性未实测**（只有 Windows 一台）。
5. **30GB/100GB 真实大文件未测**（用 32MB 端到端 + 5GiB 稀疏验证 int64）。
6. **真正杀进程再 resume 未测**（只测同进程重建 .partmeta）。
7. **M6 网页会话分享、M7 安卓收尾尚未开工**。
8. 群事件未走真实 WS 联调（只经 GroupBroadcaster 端口）。
## 11. M6 / M7 收尾与最终验收（2026-11-04 09:10）

### 11.1 全量回归：754 条用例，14 个套件，真实退出码全 0

| 套件 | 用例 | 退出码 |
|---|---|---|
| test/core/identity | 75 | 0 |
| test/core/files | 82 | 0 |
| test/core/store | 27 | 0 |
| test/core/server | 71 | 0 |
| test/app | 58 | 0 |
| test/core/discovery | 42 | 0 |
| test/core/shares | 61 | 0 |
| test/core/transfer | 47 | 0 |
| test/core/messaging | 56 | 0 |
| test/core/groups | 41 | 0 |
| test/core/server_share | 35 | 0 |
| test/core/webshare | 23 | 0 |
| test/platform/android | 77 | 0 |
| test/e2e（Lead 亲写） | 59 | 0 |
| **合计** | **754** | 全绿 |

`flutter analyze lib test` -> No issues found
`flutter build windows --release` -> Built lan_simple_file.exe

### 11.2 真实启动 + 全端点实测（不是编译通过，是真发请求）

```
alive=True hasWindow=True
/api/v1/ping    -> 200
/               -> 200   （取件入口页）
/web/share.js   -> 200   （静态资源）
/w/guest        -> 200   （网页访客页）
/s/zzzz         -> 404   （不存在的分享）
/api/v1/nope    -> 404   （未知接口）
```

### 11.3 全链路端到端（Lead 亲写，走完整链路）

`test/e2e/full_chain_test.dart` 2 条：
- 建分享 -> `/s/:id` 页 200 且含分享名 -> `/tree` 返回条目 -> `GET /f/a.txt` 字节与磁盘**逐字节一致**
  -> 带 `Range: bytes=0-5` 得 206 且长度 6 -> 不存在的分享 404
- 停用分享后**立即** 404（证明不是缓存命中）

这条用例曾经真的红过：`/s/:id` 返回 404，原因是 `FlutterAssetSource` 在 `flutter test`
环境里读不到 asset bundle。补了 `fallbackDir` 磁盘回退后转绿。

### 11.4 界面亲眼确认

截图 [docs/screenshots/final_app.png](screenshots/final_app.png)（PrintWindow，不抢焦点不动鼠标）
人工判读：5 个 tab（附近/我的分享/群组/传输/设置）、选中「附近」高亮、明色主题、
主区空状态「附近的人」。不是全黑、不是空白。

### 11.5 M6/M7 期间 Lead 亲自补的关键缺口

| 缺口 | 为什么必须补 |
|---|---|
| 周期性 `sweep()` 定时器 | 没有它，心跳超时永远不被判定，「关页即失效」的兜底形同虚设 |
| `registerGuestRoutes` / `registerShareRoutes` / `registerTreeRoutes` / `registerZipRoutes` / `registerStaticRoutes` 全未注册 | 路由写好了但没人挂到 server 上，取件页永远 404 |
| `FlutterAssetSource`（从 asset bundle 读页面） | 只有测试用的内存版，真机上页面 404 |
| `StoreShareSource`（从 store 解析 ShareTarget） | 只有测试用的内存版，真机查不到分享 |
| `LanAddressGuard`（Dart 侧局域网地址校验） | Flutter 的 dart:io 不走 Android java.net 栈，`network_security_config` 对 Dart 侧网络**完全不生效**，即「明文只限局域网」原本是空的 |
| `MessageSignature` 收侧验签 | 原本「能签不能验」，安全性只落实一半 |

### 11.6 最终未验证清单（诚实，一条不删）

**构建与打包**
1. `flutter build apk` 从未成功（本机无网，Gradle 分发包与 AGP 标记下载失败），**没有任何 APK 产物**。
2. AndroidManifest 合并、split-per-abi、minSdk/targetSdk 与 Flutter 默认值的兼容性未验证。

**Android 真机（全部未验证）**
3. 前台服务 `dataSync` 在 Android 14 的真实行为、通知渠道实际渲染、停止共享回调。
4. MulticastLock 真机上是否真能收到组播、耗电实测。
5. ACTION_SEND 真实 intent 形状（不同 ROM 差异）、多文件分享、以及「接收后建 share」整条链路未接通。
6. 权限引导在 MIUI/EMUI/ColorOS 上的实际页面与文案。
7. SAF 撤权后 `canRead` 的真实返回值。

**网络与跨设备**
8. Windows<->Android 实网连通、防火墙放行、AP 隔离、路由器组播转发。
9. 跨操作系统 identicon 逐字节一致（只有 Windows 一台机器）。

**规模与中断**
10. 30GB/100GB 真实大文件（用 32MB 端到端 + 5GiB 稀疏验证 int64）。
11. 真正杀进程再 resume（只测同进程重建 .partmeta）。
12. 50 万项目录扫描、8 并发 Range、20GB 网页配额压测。

**功能面**
13. 浏览器真机握手（guest.js 的 WebCrypto 只在 Dart 侧用固定公钥测过）。
14. ECDSA P-256 客户端签名验签（服务端目前只校验「有 pubkey」）。
15. OfferService 在 lib 里**尚无实现**：网页发文件走 offer 的链路未接通。
16. Android 四处接线（前台服务计数、分享 intent、权限引导、退出对话框）未接到真实 UI。
17. 通知文案未迁 strings.xml；APK 签名与升级路径文档未写。
## 12. 收尾阶段验收（2026-11-04 09:40）—— M3/M4 补完 + UI 接真实页面

### 12.1 全量回归：849 条用例，18 个套件，真实退出码全 0

| 套件 | 用例 | 套件 | 用例 |
|---|---|---|---|
| identity | 75 | offers | 16 |
| files | 82 | link | 24 |
| store | 27 | server_gateway | 12 |
| server | 71 | android | 77 |
| app | 58 | ui | 34 |
| discovery | 42 | **e2e（Lead 亲写）** | **68** |
| shares | 61 | | |
| transfer | 47 |  |  |
| messaging | 56 |  |  |
| groups | 41 |  |  |
| server_share | 35 | **合计** | **849** |
| webshare | 23 |  |  |

`flutter analyze lib test` -> No issues found

### 12.2 真实启动 + 全端点实测（含新增链路）

```
alive=True hasWindow=True
/api/v1/ping    -> 200
/               -> 200
/web/share.js   -> 200
/w/guest        -> 200
/api/v1/offers  -> 200   （offer 接收侧已接进 App）
/j/zzzz9999     -> 410   （网关：不认识的分享，可读拒绝而非 404）
/s/zzzz9999     -> 404
/api/v1/nope    -> 404
```

### 12.3 本轮 Lead 补完的三个断链（都是「写好了但没接上」）

| 缺口 | 后果 | 补法 |
|---|---|---|
| `DiscoveryService` / `TransferService` 两个契约接口**零实现** | UI 永远空白、下载永远没有地址 | 新增 `DiscoveryServiceImpl`（公告流+活动表+peers 表）与 `StoreTargetResolver`（按 peers 表拼 URL，且过 `LanAddressGuard`） |
| `OfferService` 有实现但**无 HTTP 投递、无接收侧路由** | 「发得出、收不到」 | 新增 `HttpOfferTransport` + `POST /api/v1/offers`、`/offers/:id/decision`、`GET /api/v1/offers`；并给 `OfferServiceImpl` 补 `receiveProposeFrame` / `receiveDecisionFrame` |
| `/j/` 网关注册函数**未被调用**，且 `shareId -> owner` 无数据源 | 链接入口不可用 | `StoreShareSource.ownerOf` 提供归属；`DiscoveryServiceImpl` 实现 `PeerEndpointLookup`；在 assembly 注册 |

### 12.4 真实跨节点端到端（Lead 亲写，全部走真网络）

- `cross_node_transfer_test.dart` 2 条：**A 起服务共享 1MB 文件 -> B 用 TransferService 真下载 -> 逐字节一致**；未知对端 providerOffline。
- `offer_http_test.dart` 2 条：**A propose -> 经真实 HTTP POST 到 B 的 /api/v1/offers -> B 的 GET 能读到该 offer（含真实文件大小 2048 与 note）**；对端离线 providerOffline。
  - 这条抓到一个真实缺陷：接收侧 `GET /api/v1/offers` 的 JSON **漏了 note 字段**，offer 里的备注在传输后丢失。已补。

### 12.5 界面亲眼确认（真实页面已上线）

截图 [docs/screenshots/final_m1.png](screenshots/final_m1.png)（PrintWindow，不抢焦点不动鼠标）
人工判读：侧栏 5 个 tab、选中「附近」高亮、明色主题；主区域是**真实页面的空态**：
标题「附近还没有人」+ 诊断说明「本机已在线等待，但还没有收到其他设备的公告。
可能原因：对方没有打开软件、双方不在同一网段，或系统防火墙拦截了 UDP 47777 广播。」+「重新搜索」按钮。
**不再是占位文案。**

### 12.6 本轮修掉的一个真实测试退化

三个 tab 换成真实页面后，`test/app` 有 3 条**既有用例变红**：
- `默认落在「附近」并显示 M1 占位文案` —— 占位文案已不存在，属正确失败。已改为断言「未连接服务」提示且占位文案确实消失。
- 两条 golden 快照 —— 界面确实变了。已重新生成，并**逐张亲眼核对**（明/暗两套，5 tab、选中态、布局均正确）。

注：golden 图里中文渲染为方块，是 `flutter_test` 无系统字体的已知现象，
因此**快照只证明布局与配色，不证明文案**。真实文案由上面 12.5 的实机截图证明。

### 12.7 仍未验证（最终清单，一条不删）

**构建与打包**
1. `flutter build apk` 从未成功（本机无网，Gradle 分发包与 AGP 标记下载失败），**没有任何 APK 产物**。
2. manifest 合并、split-per-abi、minSdk/targetSdk 兼容性未验证。

**Android 真机（全部未验证）**
3. 前台服务 dataSync 真实行为、通知渲染、停止共享回调。
4. MulticastLock 真机收组播、耗电实测。
5. ACTION_SEND 真实 intent 形状（各 ROM 差异）、多文件、接收后建 share 整链路未接通。
6. 权限引导在 MIUI/EMUI/ColorOS 的实际页面。
7. SAF 撤权后 canRead 真实返回值。

**网络与跨设备**
8. Windows<->Android 实网、防火墙、AP 隔离、路由器组播转发。
9. 跨操作系统 identicon 逐字节一致（只有一台机器）。
10. 二维码未真机扫码；`lsf://` 能否被系统打开依赖 scheme 注册（M7 范围，未做）。

**规模与中断**
11. 30GB/100GB 真实大文件（用 32MB 端到端 + 5GiB 稀疏验证 int64）。
12. 真正杀进程再 resume（只测同进程重建 .partmeta）。
13. 50 万项目录扫描、8 并发 Range、20GB 网页配额压测。

**功能面**
14. 浏览器真机 WebCrypto 握手（guest.js 只在 Dart 侧用固定公钥测过）。
15. ECDSA P-256 客户端签名验签（服务端只校验「有 pubkey」）。
16. `accept 后发起方自动撤销临时 share`——需要传输完成钩子，M2/M4 交界，未实现。
17. Android 四处接线（前台服务计数、分享 intent、权限引导、退出对话框）未接到真实 UI。
18. 通知文案未迁 strings.xml；APK 签名与升级路径文档未写。
19. 建群入口 UI 未做（群页目前只读列表）；未读清零交互未做。
## 13. Android APK 真实打包成功（2026-11-04 10:20）—— 推翻第 12.7 条第 1 项

前几轮一直记为「无网、无法打包」。**这条已推翻**：本机有网络与代理，之前的失败是
Gradle / Dart 构建钩子都没有走代理，而非没有网络。

### 13.1 修复链（每一步都是真实报错驱动，不是猜的）

| 现象 | 真实根因 | 修法 |
|---|---|---|
| `Connection timed out` 下载 gradle-9.3.1 | Gradle 不读 `HTTP_PROXY` 环境变量 | 写 `~/.gradle/gradle.properties` 的 `systemProp.*.proxyHost/Port`，并把局域网段加入 nonProxyHosts |
| `Conflicting configuration: abiFilters cannot be present when splits abi filters are set` | M7 同时配了 `ndk.abiFilters`（Flutter 插件注入）与 `splits.abi` | 在 defaultConfig 里 `ndk { abiFilters.clear() }`，由 splits 决定产物 |
| `libsqlite3.arm64.android.so` 下载 `HandshakeException` | Dart 的 build hooks 走 Dart 自己的 HTTP 栈，不吃 Gradle 代理 | 手工经代理+镜像下载 3 个 ABI 的 `.so`，按内容 sha256 放进 `download-<hash前8位>/libsqlite3.so`（hook 会校验 hash 并复用缓存） |
| `Could not close incremental caches ... class-fq-name-to-source.tab` | Kotlin 增量编译在 Windows 上缓存文件被占用的已知问题 | `android/gradle.properties` 加 `kotlin.incremental=false` |
| `Gradle build failed to produce an .apk` | 开了 split-per-abi，产物名字带 ABI 后缀，Flutter 找不到默认名 | 不是故障：产物在 `build/app/outputs/flutter-apk/app-<abi>-debug.apk` |

### 13.2 产物（真实存在）

```
build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk    98.0 MB
build/app/outputs/flutter-apk/app-armeabi-v7a-debug.apk  76.4 MB
build/app/outputs/flutter-apk/app-x86_64-debug.apk       85.6 MB
```

### 13.3 APK 内容校验（解 zip 逐项断言，不是看文件存在）

arm64 APK：`entries=558`，以下条目全部命中且大小合理：

```
AndroidManifest.xml                          15968
classes.dex                               11294168
lib/arm64-v8a/libsqlite3.so                1732360   <- 原生库真进包了
lib/arm64-v8a/libflutter.so               38828704
assets/flutter_assets/assets/web/share.js      9018   <- 网页取件页随包
assets/flutter_assets/assets/web/guest.html    1935   <- 网页访客页随包
```

### 13.4 Manifest 校验（aapt2 dump 真读 APK 内的二进制 Manifest）

```
foregroundServiceType = 0x00000001        <- 即 dataSync（枚举被编成整数，不是字符串）
ShareForegroundService                    <- 会话级前台服务类确实注册
FOREGROUND_SERVICE_DATA_SYNC 权限           <- 存在
POST_NOTIFICATIONS 权限                     <- 存在
networkSecurityConfig = @0x7f100000        <- NSC 已生效引用
SEND（intent-filter）                       <- ACTION_SEND 入口存在
multicast（CHANGE_WIFI_MULTICAST_STATE）    <- 组播锁权限存在
debuggable = true                          <- debug 包，符合预期
```

注：`dataSync` 与 `usesCleartextTraffic` 在初次文本 grep 中显示 MISS，
前者是因为枚举被编译成 `0x00000001`，后者是**我们刻意没有全局开启**（改用 NSC + Dart 侧
`LanAddressGuard` 双保险）。这不是缺项。

### 13.5 仍然缺的一环（诚实）

`adb devices` 返回空列表 —— **没有连接任何 Android 设备**，因此：

- APK 未安装到真机，未做启动验证。
- 前台服务、组播锁、ACTION_SEND、权限引导、SAF 的真实行为**依旧未验证**（第 12.7 条第 3–7 项原样有效）。
- 但「APK 能否打包」这一条从「从未成功」变为「三个 ABI 全部产出且内容校验通过」。