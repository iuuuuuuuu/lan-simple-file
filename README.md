# lan-simple-file

局域网文件分享与聊天客户端。当前预发布版本：**0.1.0-beta.3**。

## Windows beta

网页“下载 Windows 安装程序”提供 Setup EXE，运行后安装到当前用户目录，
并注册开始菜单与卸载入口。安装后的客户端会保存一份安装程序供网页下载。
GitHub Releases 同时提供 Windows x64 安装程序与便携 ZIP。
便携 ZIP 不包含安装程序，网页客户端下载功能需要使用安装版。
安装程序不包含发布者的昵称、头像、聊天记录或分享文件。

### 使用

- 首次启动使用本机用户名，可以在设置中修改昵称与头像。
- 从左侧联系人和群聊分组进入聊天；拖入文件即可创建分享并发送。
- “我的分享”支持备注名称、搜索、栅格展示与右键菜单。
- 分享链接和二维码使用 http://用户名.local/s/分享ID，无需手动填写 IP 或端口。
- 同名域名会自动追加设备后缀；IP 变化后自动更新域名记录。
- 系统托盘支持后台分享，关闭窗口的行为可在设置中修改。
- Windows 设置页可开启或关闭“开机自动启动”，默认不启用。
- 自己发送的消息可撤回；对端离线时将在重新连接后同步。

域名访问要求设备处于可互通的局域网，并支持 mDNS。
Windows 的“允许局域网访问”需要一次管理员权限：
仅为当前程序在本地子网、专用/域网络放行网页端口、TCP 80 和 UDP 5353。
端口 80 被其他程序占用时，会保留带端口的链接，并在设置页显示原因。
路由器的 AP 隔离、组播限制或访问设备不支持 mDNS，可能影响跨设备访问。
Windows 系统 HTTP 代理未绕过 .local 时，新生成的分享链接会自动使用局域网 IP，
不修改系统代理配置。已复制的旧域名链接不受此回退影响；
如需继续使用域名链接，请在自己的代理设置中将 *.local 加入绕过列表。

### 当前验证范围

Windows 正式构建已完成。完整回归串行执行；
需要管理员权限的防火墙测试在普通用户环境跳过，MuMu 联机专项需单独开启。
本机后台浏览器已验证域名解析、无端口分享页、文件请求和客户端下载。
MuMu Android 12 x86_64 已通过设备集成测试，包括 UI、实际下载、消息撤回、
服务重启持久化和前台服务启停；还验证了模拟器下载 PC 的安装程序。
安卓真手机、跨物理电脑和 macOS 仍待实测。

## Android beta

GitHub Releases 提供 ARM64、ARMv7 与 x86_64 APK；多数手机使用 ARM64，MuMu 使用 x86_64。
最低支持 Android 7（API 24），当前实测为 MuMu Android 12 x86_64。
发布 APK 使用独立签名，不能覆盖此前 debug 签名的测试版；卸载测试版会清除应用数据，
请先保留需要的数据。后续发布版沿用同一签名，可覆盖更新。

“我的分享”加号可选择文件、文件夹或照片。目录使用系统选择器的持久只读授权，
普通目录无需“所有文件访问”权限。Android 11+ 可从设置中的“文件访问”进入
系统“所有文件访问”授权页，是否开启由用户决定。
该权限不会解除系统目录选择器的限制；Android/data、Android/obb 和应用私有目录仍受保护。

## 从源码运行

需要 Flutter SDK（Dart >= 3.13.4）和 Visual Studio 的桌面 C++ 开发组件。

~~~powershell
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build windows --release
~~~

截图测试在 Windows 上使用 C:\Windows\Fonts\simhei.ttf。
GitHub 发布流水线运行静态检查与串行功能回归，golden 截图使用独立标签，
留在具有该字体的本机运行，不通过替换字体或更新基线绕过差异。
真实网络用例需串行执行；测试数据使用独立临时目录。
用户资料存储在系统应用数据目录，不在源码或便携包中。

版本记录见 [CHANGELOG.md](CHANGELOG.md)。历史开发计划见
[docs/plan.md](docs/plan.md)，M0 历史验收见
[docs/acceptance.md](docs/acceptance.md)。

## 许可

GPL-3.0-only，完整文本见 [LICENSE](LICENSE)。
修改后分发源码或二进制时，需按同一许可提供相应源码。

## MuMu 安卓测试

启动模拟器并通过 ADB 连接后运行：

~~~powershell
flutter test integration_test/android_smoke_test.dart -d 127.0.0.1:16384
~~~

ADB 端口由 MuMu 实例决定。测试使用独立临时目录，测试完成后安装正常客户端。
MuMu 默认 NAT 地址为 `10.0.2.15`，组播无法直接到达宿主机。
客户端会通过 `10.0.2.2:47778` 定期交换已签名的发现公告并建立认证聊天；
宿主机也需要运行新版客户端。

真实 NAT 联机测试使用独立临时资料，不打开 Windows 窗口。
先在一个终端运行后台宿主节点，再在另一个终端运行 MuMu 用例：

~~~powershell
flutter test test/e2e/mumu_discovery_host_test.dart --dart-define=RUN_MUMU_DISCOVERY=true
flutter test integration_test/android_http_discovery_test.dart -d 127.0.0.1:16384 --dart-define=RUN_MUMU_DISCOVERY=true
~~~

用例验证自动发现、附近列表、签名聊天、撤回、持续在线和服务退出。
完成后需重新安装正常客户端 APK，避免留下集成测试入口。

Windows 安装程序源码在 tool/windows_installer.iss，使用 Inno Setup 编译；
传入 RuntimeDir（Flutter release 目录）和 OutputDir（安装程序输出目录）。

### 安卓发布签名

Windows 上使用 tool/build_android_release.ps1 构建签名 APK，需要 Flutter 与 JDK keytool。
第一次执行时加 -InitializeSigningKey，之后不再加该参数。
脚本在用户目录 .android/lan-simple-file 下生成独立密钥与 Windows 当前用户加密的凭据，
并通过进程环境变量提供给 Gradle，不把密钥、密码写入仓库或安装包。
请妥善备份签名密钥及可恢复的密码；Windows 加密凭据不能直接迁移到另一台电脑。
其他构建环境可设置 LAN_SIMPLE_FILE_KEYSTORE、LAN_SIMPLE_FILE_STORE_PASSWORD、
LAN_SIMPLE_FILE_KEY_ALIAS、LAN_SIMPLE_FILE_KEY_PASSWORD 后运行 flutter build apk --release --split-per-abi。
缺少签名配置时发布构建会明确失败，不回退到 debug 签名。

### GitHub 发布

推送 v*-beta.* 标签触发 .github/workflows/release.yml，也可针对已有 beta 标签手动触发。
仓库需配置 ANDROID_KEYSTORE_BASE64、ANDROID_STORE_PASSWORD、ANDROID_KEY_PASSWORD、
ANDROID_KEY_ALIAS 四个 Actions secrets；使用同一发布密钥，不能为每次流水线重新生成。
先运行 Windows 功能回归，再由 Windows 与 Linux runner 构建安装包和签名 APK；
所有产物摘要校验通过后才将草稿公开为预发布版本。
