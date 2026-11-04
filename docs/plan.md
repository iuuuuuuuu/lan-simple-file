# lan-simple-file 开发计划

版本 v2 ｜ 2026-11-04 ｜ 状态：待 Owner 确认后进 M0
许可：GPL-3.0-only（见 `LICENSE`）

## 0. 本版吸收的修订

| 编号 | 修订 | 影响面 |
|---|---|---|
| R14 | 项目以 **GPL-3.0-only** 开源，衍生分发必须同许可开源 | LICENSE、逐文件 SPDX 头、README、依赖许可审查 |
| R15 | **支持大文件**（不限 4GB，按 100GB 级设计） | 传输层、zip64、临时区配额 |
| R16 | 网页端发文件**必须接收方允许**，且即时 | offer/accept 覆盖网页来源 |
| R17 | 网页端发出的文件**随会话失效**：关闭网页即失效 | 会话型临时 share、清理任务 |
| R18 | 上一轮 4 项确认（网页仅文本图片 → 已放宽为大文件、撤回不限时限、群主权限、明文 HTTP+token） | 见 §9 |

> R18 说明：上一轮「网页端只支持文本与图片」被 R15/R16 取代——
> 网页端现在**支持大文件发送**，代价是必须逐次征询授权且生命周期绑定会话。

## 1. 产品一句话

每台设备跑一个节点（自带 HTTP/WS 服务 + SQLite），局域网内互相发现；共享只记文件位置；
关闭软件即下线，对方再取件会得到「提供者已离线」提示；任何节点可作入口做跳转，链接不绑 IP。

## 2. 许可策略（R14）

| 项 | 决定 |
|---|---|
| 许可 | **GPL-3.0-only**（非 or-later，条款固定） |
| 传染边界 | 分发二进制或修改版 → 必须以同许可开放源码；纯自用部署不触发（GPL 本身边界） |
| 逐文件声明 | 每个源文件头 `SPDX-License-Identifier: GPL-3.0-only`，M0 起强制 |
| 发行物 | 安装包与 APK 内附 LICENSE 与「无担保」声明 |
| 依赖审查 | 逐个核对 Flutter/pub 依赖许可，禁止引入 GPL 不兼容项（如闭源 SDK、部分 CC-BY-NC 资源） |
| 升级路径 | 若发现下游以 SaaS 形式闭源提供 → 重访是否升 AGPL-3.0（见决策笔记） |

## 3. 大文件与网页端会话（R15–R17）

### 3.1 大文件基线（全平台）

| 项 | 设计 |
|---|---|
| 单文件上限 | 100 GB（`i64` 全程，禁 32 位计数） |
| 单目录规模 | ≤ 50 万项（分页 200/页，游标续取） |
| 传输 | Range 分片 1–4 MB，8 并发，`.part` + `.partmeta` 续传 |
| 校验 | 默认 xxh3（快），可选 sha256；校验在接收侧做，失败重下该片 |
| 打包 | zip64 + store 模式（不压缩），超过阈值自动改为「清单 + 并行多文件」 |
| 磁盘前置 | 接受 offer 前检查目标盘余量 ≥ 文件大小 ×1.05，不足直接拒绝并说明 |
| 临时区 | 网页上传落宿主节点 `temp/web-share/`，对总量设配额（默认 20 GB，可配） |

### 3.2 网页端发送：必须授权 + 会话即生命周期

```
浏览器 → 宿主节点 : 握手，WebCrypto 生成临时 ECDSA P-256，换 guest 凭证
浏览器 → 目标 peer : POST /offers（经宿主中继）{files:[{name,size,mime}], note}
目标 peer → 用户   : 弹「XX 想发给你 3 个文件（8.4 GB）」[接受][拒绝]
目标 peer → 浏览器 : decision.accept → 回传一次性上传凭证
浏览器 → 宿主节点 : 分片上传到 temp/web-share/<sessionId>/（可续传）
宿主节点 → 目标   : 通知「可下载」→ 目标走既有下载管道拉取
结束              : 目标拉完 / 浏览器关闭 / 心跳超时(60s) / 显式撤销
                  → share 立即 revoked_at，链接一律 410
                  → 临时文件在宽限期（10 分钟）后删除
```

四条硬规则：

1. **接受前零字节**：未得到 decision.accept，浏览器不得开始上传。
2. **即时性**：接受后 1 秒内开始上传，不做队列等待；拒绝即结束，不留残留。
3. **会话绑定**：`guestSessionId` 心跳每 15 秒；连续两次缺失（≈30 秒）即判定会话结束。
4. **关闭即失效**：页面 `beforeunload` / `pagehide` 主动上报撤销；即使上报失败，
   宿主节点的心跳超时也会兜底撤销。撤销后已下载到对方本地的文件无法追回，UI 需明示。

### 3.3 与节点分享的区别

| | 节点分享（桌面/安卓） | 网页会话分享 |
|---|---|---|
| 生命周期 | 直到手动停止或设的有效期 | 绑会话，关闭页面即失效 |
| 是否复制文件 | 否，只记位置 | 是，落在宿主临时区 |
| 谁能发起 | 任何节点用户 | 任何浏览器访客 |
| 是否需要对方接受 | 是（offer/accept） | 是（强制，无免确认开关） |
| 撤销后 | 410 | 410 + 宽限期后删文件 |

## 4. 技术栈定稿

| 层 | 选型 | 说明 |
|---|---|---|
| 外壳 | Flutter（Windows / macOS / Android 一套代码） | 桌面 + 安卓共用核心 |
| 服务端 | dart:io HttpServer + WebSocketTransformer | 真 HTTP 服务，非 WebView 壳 |
| 发现 | RawDatagramSocket 广播 + 组播，自建签名公告 | 不依赖系统 mDNS |
| 存储 | drift（SQLite，WAL） | 迁移框架内建 |
| 加密 | cryptography：Ed25519 / X25519 / AES-GCM / Argon2id | 身份、token、口令 |
| 状态 | riverpod | 全局 + 页面级 |
| 桌面壳 | tray_manager / window_manager | 托盘常驻、最小化 |
| 安卓 | flutter_foreground_task、file_picker、saf 桥、mobile_scanner | 会话级服务 + SAF + 扫码 |
| 打包 | archive（zip64, store） | 目录一次打包 |
| 网页端 | 同 HTTP 服务内置静态页（原生 JS + WS + WebCrypto） | 零安装取件 + 聊天 + 会话发送 |
| 许可 | GPL-3.0-only | 逐文件 SPDX 头 |

## 5. 数据模型（DDL 摘要）

```sql
device(peer_id PK, pubkey, alg, name, avatar_hash, os, first_seen, last_seen,
       online, is_self, is_guest, note);

share(id PK, kind, root_kind, root_uri, display_name, owner_peer_id,
      created_at, expires_at, mode, password_hash, group_id,
      max_speed_kbps, enabled, missing, revoked_at,
      session_id, is_ephemeral);      -- 网页会话分享专用两列

share_item(share_id, item_key, rel_path, size, mtime, mime, is_dir,
           PRIMARY KEY(share_id, item_key));

grant(share_id, peer_id, granted_at, expires_at);

thread(id PK, kind, title, avatar_hash, peer_id, group_id,
       last_msg_hlc, last_msg_preview, unread, muted, pinned,
       created_at, deleted_at);

grp(id PK, name, avatar_hash, owner_peer_id, created_at, epoch);
group_member(group_id, peer_id, role, joined_at, last_seen);
group_key(group_id, epoch, wrapped_for_peer, wrapped_blob);

message(id PK, thread_id, sender_peer_id, kind, hlc, ts, body, attach_json, sig,
        revoked_at, revoke_reason, edited_at);

attach(id PK, msg_id, share_id, owner_peer_id, item_key, name, size, mime,
       is_dir, sub_path, local_path, state);

offer(id PK, from_peer, from_session, to_peer, attach_json, size_total,
      status, created_at, decided_at, note, expire_at);

transfer(id PK, direction, peer_id, share_id, item_key, bytes_total, bytes_done,
         status, speed_bps, created_at, finished_at, err);

guest_session(session_id PK, host_peer, pubkey, created_at, last_beat,
              revoked_at, quota_bytes, used_bytes);

msg_seen(thread_id, peer_id, last_hlc);
peer_block(peer_id PK, reason, until);
settings(key PK, value);
```

## 6. 协议增量

### 6.1 发现公告 v2

```json
{ "v":2, "id":"p_7fk3m9x2a1cdk", "name":"YG", "av":"sha256:ab12",
  "port":47778, "ip":"192.168.1.23", "shareCount":7,
  "caps":["chat","group","offer","push","web-session"],
  "mode":"serving", "ts":1762300000, "sig":"base64url" }
```

### 6.2 offer / accept（节点来源与网页来源共用）

```
POST /api/v1/offers          { from_peer | from_session, to_peer, files[], note }
POST /api/v1/offers/:id/decision  { accept | reject, reason? }
GET  /api/v1/offers?since=        待决策列表
```

- 节点间 offer：接受后生成 `mode=offer` 临时 share，ttl 30min，仅接收方可读，完成即撤销。
- 网页 offer：接受后生成上传凭证，浏览器直传宿主临时区，宿主再转交（见 §3.2）。
- 未响应 30 分钟过期；过期不保留任何 token。

### 6.3 撤回与删除语义（无中心下的诚实边界）

| 操作 | 生效范围 |
|---|---|
| 撤回我的消息 | 全局尽力广播，对端显示「已撤回」；已截图导出无法追回 |
| 删除我的消息 | 本地删 + 广播 delete，对端在线即删，离线下次同步删 |
| 群主删他人消息 | 广播 mod 事件，其他节点尽力遵守，非强制 |
| 删除会话 | 仅本地，不影响对方；同 peer 再来信会重建 |
| 停止共享 / 撤销链接 | 全局，广播 revoke + jti 进吊销表 |
| 撤销网页会话分享 | 立即 410 + 宽限期后删临时文件 |
| 删除群文件卡片 | 只删索引，不删磁盘原文件 |

### 6.4 私聊 / 群聊通道

```
WS /ws
  {t:"hello", id, name, av, caps}
  {t:"msg", thread, msg:{id,kind,hlc,body,attach,sig}}
  {t:"ack", msgIds:[...]}
  {t:"revoke", msgId, ts, sig}
  {t:"offer"} / {t:"offer-decision"}
  {t:"presence", id, online, ts}
  {t:"pull", thread, sinceHlc}
  {t:"progress", transferId, done}
```

消息 id = `senderPeerId + ":" + seq`，grow-only set，HLC 排序，离线按 `sinceHlc` 补拉。

### 6.5 群文件历史索引

`attach` 存 `shareId + ownerPeerId + itemKey + 一次性 token`，不存 IP。
点开时先查 peers 表：在线 → `/j/<shareId>/<itemKey>?k=`；
离线 → 提示「提供者 X 已离线（最后在线 N 分钟前）」并提供「上线后提醒我」。

### 6.6 网页端访客（浏览器不可寻址）

```
浏览器 → 宿主 : /w/session  WebCrypto ECDSA P-256 → guest 凭证
guest 消息    : 经宿主中转 → 目标节点
目标回信      : 目标 → 宿主 → 浏览器 WS
```

guest 标记 `is_guest`，不能参与发现公告、不能成为被寻址节点、不能被直连；
离线消息暂存宿主，随会话结束一并清除（不做 24h 留存——见 R17 的会话语义）。

## 7. 主题与头像规格

### 7.1 双色主题

| Token | 明 | 暗 |
|---|---|---|
| bg | #F7F8FA | #0E1116 |
| surface | #FFFFFF | #161A21 |
| line | #E5E7EB | #242A33 |
| fg | #16181D | #E6E9EF |
| fg-dim | #6B7280 | #8B94A3 |
| accent | #3B82F6 | #4F8DFD |

在线/离线用 accent 实心/空心圆表达，不新增色相。

### 7.2 identicon

```
h = sha256(peerId)
hue = h[0..2] % 360 ；sat 45~65%
5x5 网格，第 1、5 列镜像 → 取 15 位决定填充
输出 SVG + 400px PNG，按 avatar_hash 缓存
```

## 8. 里程碑

| 阶段 | 内容 | 工期 | 依赖 |
|---|---|---|---|
| M0 | 地基：工程、许可落地、身份、FileRef、存储、服务骨架 | 3d | — |
| M1 | 发现 + 共享管理 + 浏览树 | 5d | M0 |
| M2 | 传输：Range/续传/校验/打包 + 网页取件页 | 5d | M1 |
| M3 | 链接 token / 网关跳转 / 二维码 | 3d | M2 |
| M4 | 单聊 + offer/accept + 网页聊天 | 5d | M2 |
| M5 | 群组 + 群文件历史 + 撤回删除 | 6d | M4 |
| M6 | 网页会话分享（大文件上传、授权、失效回收） | 4d | M2, M4 |
| M7 | 安卓短时模型 + 权限引导 + 打包收尾 | 5d | M1..M6 |

合计 36 工作日；单人含缓冲 9 周。

### M0（3d）地基
- Flutter 工程，windows + android 双 target
- **许可落地**：LICENSE 已就位；逐文件 SPDX 头模板；README 声明；依赖许可核查清单
- drift schema v1 + 迁移框架 + 结构自检
- Ed25519 身份、peerId 派生、签名/验签 + 跨端 test vector
- FileRef 抽象 + LocalRef + SafRef（分页 list、length、mtime、exists）
- HttpServer:47778 + /api/v1/ping + /api/v1/profile + 端口冲突顺延
- 托盘 + 单实例 + 开机自启开关
- 双色主题 token + identicon 生成 + 头像选择

验收：两机互 ping 通；改名即时生效；未设头像时两端 identicon 一致；
安卓 SAF 选目录后能列出前 200 项；`flutter analyze` 与许可头检查均通过。

### M1（5d）发现与共享
- UDP 广播 + 组播公告、签名校验、心跳、上下线状态机
- peers 表 + 附近的人 UI
- 共享 CRUD：桌面目录/文件选择、安卓 SAF 文件/目录选择
- 首扫后台 + 索引缓存 + 增量刷新 + 手动刷新
- /api/v1/peers/:id/shares、/s/:id/tree 分页
- 共享管理页：状态、停止共享、重新定位

验收：A 共享目录，B 3 秒内看到人并逐层展开；A 删源文件后 B 看到「已失效」并能重新定位。

### M2（5d）传输与网页取件
- Range 流 + ETag(size+mtime) + 206 + HEAD，全程 i64
- 下载池 8 并发、`.part` 续传、xxh3 校验、失败重下单片
- 传输面板：进度/速度/剩余/暂停/取消
- /s/:id/zip（zip64, store）与单文件下载；超阈值自动改清单模式
- 网页取件页：响应式、目录懒加载、下载引导按钮

验收：**30 GB** 文件断网 30 秒后自动续传完成且校验通过；手机浏览器打开链接能下载并解压；
零字节文件与超长中文名各测一个。

### M3（3d）链接与寻址
- capability token 签发/校验（sid, sub, perm, nbf, exp, jti）
- 吊销表 + 「立即失效所有链接」
- /j/:shareId 网关跳转
- 二维码生成（分享/配对）+ mobile_scanner 扫码直达
- 桌面 .local 主机名发布与重名检测；可选 .lan 内网域

验收：换 IP 后旧链接仍可下；扫码直达；撤销后立刻 410。

### M4（5d）单聊与双向传输
- thread/message/attach 落地，direct 会话
- WS 互连、在线投递、离线补拉、去重、HLC 排序
- 单聊 UI：气泡（文本/图片/文件卡片）、时间分组、未读
- offer/accept 全流程（节点来源）+ 接受后临时 share 自动撤销
- 网页端单聊（guest 中继）
- 撤回：单条消息、单条文件卡片

验收：桌面 ↔ 安卓发文件必须对方点接受才传输；拒绝后发送方看到「已拒绝」；
网页与桌面聊通；撤回后对端 5 秒内变「已撤回」。

### M5（6d）群组
- 建群、邀请、成员面板、群头像与名称编辑
- 群消息日志 + 补拉 + 去重；群文件历史（按人/时间筛选）
- 群内选择文件即发共享卡片
- owner 离线时群文件卡片显示离线提示 + 上线提醒
- 撤回/删除（含群主删他人）、退出群、群解散

验收：三机各离线发消息，重连后日志完全一致；A 关软件后群里点他文件得到离线提示。

### M6（4d）网页会话分享
- guest 会话握手（WebCrypto）、心跳 15s、超时判定
- 网页 offer → 目标授权 → 上传凭证 → 分片直传宿主临时区（可续传）
- 临时 share 生命周期：拉完/关闭/超时/撤销 → 410 → 宽限期删文件
- 临时区配额与清理任务（默认 20 GB）
- 网页端 UI：上传进度、剩余时间、取消；目标端 UI：接受弹窗、来源标记「网页访客」

验收：浏览器关掉页面后 30 秒内链接变 410，临时文件 10 分钟后从磁盘消失；
未授权时浏览器无法上传一个字节；8 GB 文件经网页路径成功送达且校验通过。

### M7（5d）安卓收尾
- 会话级前台服务（有共享才起）+ 通知栏操作
- 退出前置校验（有传输/被下载时二次确认）
- ACTION_SEND 接收入口 → 直接建 share
- 权限引导流：通知 → 电池优化 → SAF 授权
- cleartext 限定局域网段
- 打包：Windows 安装器 + APK split-per-abi + 签名与升级路径说明 + LICENSE 随包

验收：安卓打开共享 → 桌面下载 → 安卓关闭 → 桌面刷新得到离线提示；
系统分享面板发图能建共享；关屏传 2 GB 不中断。

## 9. 上一轮 4 项确认的落地

| 项 | 结论 | 落地位置 |
|---|---|---|
| 网页端发文件 | 支持大文件，但必须对方逐次授权，且随会话失效 | M6 |
| 撤回时限 | 不限时限，可随时撤回（同一条只能撤一次） | M4 |
| 群主权限 | 可删他人消息、可移除成员，不能删除整群历史 | M5 |
| 加密 | v1 明文 HTTP + token；HTTPS 作设置项后补 | M3 预留，v2 实现 |

## 10. 真机验收（每阶段结束跑一次）

1. 构建 + 双端安装，全程录屏留证。
2. 断网、切后台、杀进程、改 IP、路由器重启五种中断各测一遍。
3. AP 隔离环境（开热点模拟）验证提示文案，不允许空白列表。
4. 中文名、超长路径、>4GB、30GB、0 字节文件各测一个。
5. 网页会话：关页、断网、心跳超时、显式撤销四种失效路径各测一次，确认 410 与文件清理。
6. 界面改动必须截图/录屏亲眼确认。

## 11. 风险与对策

| 风险 | 对策 |
|---|---|
| 安卓被系统杀掉导致对方取件失败 | 会话级服务 + 离线提示 + 断点续传，产品上诚实 |
| SAF 遍历慢（1 万文件 5–10 秒） | 后台首扫 + 索引缓存 + 分页，绝不在请求路径现扫 |
| 无中心下撤回/删除不彻底 | UI 明确「尽力而为」，不做虚假承诺 |
| 网页 guest 中继被滥用 | guest 仅能联系宿主认可对象，限频，可拉黑 |
| 网页临时区被塞满 | 配额 + 会话超时清理 + 拒绝时立即释放 |
| GPL 与依赖许可冲突 | M0 起建立依赖许可核查清单，引入前先查 |
| 双色主题限制表达力 | 状态用形状与透明度，实测可读性 |
