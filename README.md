# lan-simple-file

局域网文件分享与聊天客户端。当前预发布版本：**0.1.0-beta.1**。

## Windows beta

从仓库的 **Releases** 页面下载 Windows x64 ZIP，解压后运行
**lan_simple_file.exe**。保持 data 文件夹、DLL 和主程序在同一目录。
便携包包含程序运行文件，不包含发布者的昵称、头像、聊天记录或分享文件。

### 使用

- 首次启动使用本机用户名，可以在设置中修改昵称与头像。
- 从左侧联系人和群聊分组进入聊天；拖入文件即可创建分享并发送。
- “我的分享”支持备注名称、搜索、栅格展示与右键菜单。
- 分享链接和二维码使用 http://用户名.local/s/分享ID，无需手动填写 IP 或端口。
- 同名域名会自动追加设备后缀；IP 变化后自动更新域名记录。
- 系统托盘支持后台分享，关闭窗口的行为可在设置中修改。
- 自己发送的消息可撤回；对端离线时将在重新连接后同步。

域名访问要求设备处于可互通的局域网，并支持 mDNS。
Windows 的“允许局域网访问”需要一次管理员权限：
仅为当前程序在本地子网、专用/域网络放行网页端口、TCP 80 和 UDP 5353。
端口 80 被其他程序占用时，会保留带端口的链接，并在设置页显示原因。
路由器的 AP 隔离、组播限制或访问设备不支持 mDNS，可能影响跨设备访问。

### 当前验证范围

Windows 正式构建已完成。最近完整回归为 1031 条通过，
一条需要管理员权限的防火墙测试在普通用户环境跳过。
本机后台浏览器已验证域名解析、无端口分享页、文件请求和客户端下载。
跨电脑、Android 真机与 macOS 尚未完成实测，本 beta 仅提供 Windows x64 包。

## 从源码运行

需要 Flutter SDK（Dart >= 3.13.4）和 Visual Studio 的桌面 C++ 开发组件。

~~~powershell
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build windows --release
~~~

截图测试在 Windows 上使用 C:\Windows\Fonts\simhei.ttf。
真实网络用例需串行执行；测试数据使用独立临时目录。
用户资料存储在系统应用数据目录，不在源码或便携包中。

版本记录见 [CHANGELOG.md](CHANGELOG.md)。历史开发计划见
[docs/plan.md](docs/plan.md)，M0 历史验收见
[docs/acceptance.md](docs/acceptance.md)。

## 许可

GPL-3.0-only，完整文本见 [LICENSE](LICENSE)。
修改后分发源码或二进制时，需按同一许可提供相应源码。
