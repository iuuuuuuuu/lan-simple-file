# Android network diagnostic build

Build a signed, ARM64-only diagnostic candidate with the existing signing key:

```powershell
./tool/build_android_release.ps1 -TargetPlatform android-arm64 -BuildName 0.1.0-beta.6.diag3 -BuildNumber 12 -NetworkDiagnostics
```

The diagnostic flag is off by default in source builds; the beta release workflow
explicitly enables it. Diag3 retains the app ID and data, and has ARM64
versionCode 2012 (diag2 was 2011). Formal beta.6 uses build 13 / ARM64 code 2013.
The user confirmed domain reachability with diag2. Diag3 keeps those networking
changes and fixes the public root sentinel for SAF folders such as `primary:1`.
Never uninstall the previous app to install this candidate.

On the phone, keep the app open while reproducing the failed PC request. After
at least 30 seconds, open Settings, then Help and diagnostics > Network diagnostics. Share
the log through Android's share sheet or save it with the system document picker.
Neither operation uses this app's LAN server or requires ADB/storage permission.
Cancellation is reported separately from a successful save.

The journal contains UTC timestamps, app/Android versions, interface addresses,
network transport/capability/route/proxy metadata, activity multicast-lock state,
power/background restrictions, lifecycle transitions, UDP send destinations and
errno, mDNS state/query/reply metadata, HTTP bind attempts and request status.
The app samples network state every 15 seconds while running. Export adds DNS
resolution and direct HTTP root checks against this device's own interfaces and
ports. These self checks cannot prove that another LAN device can connect.

No packet payloads, HTTP paths/query strings/bodies, tokens, chat/file contents,
SSID, MAC, device serial or signing keys are included. Local addresses and the
configured domain remain visible to diagnose routing and name resolution.
Only the dedicated cache directory is exposed by a non-exported FileProvider
with a temporary read grant; the native bridge validates the exact export path.

The persistent journal rotates at 512 KiB per file and retains two previous
files (1.5 MiB total); export uses one replaceable file of approximately 1.5 MiB.
The pending queue is capped at 128 records and 8 KiB per record, and overflow is
reported. Logging I/O failure does not stop networking; export reports failure
instead of claiming an empty or incomplete file was saved.

Transport errors are displayed separately from malformed datagrams. Diag2 fixes
Android LAN address selection using ConnectivityManager network capabilities:
Wi-Fi and Ethernet interfaces are eligible; cellular and VPN interfaces are not.
The same selection filters mDNS and UDP discovery membership. If no LAN is
connected, discovery does not fall back to the default cellular interface.
Logs include the selected interfaces and diagnostic revision 3. The user confirmed
domain and share access with the diagnostic builds; the earlier EPERM failure did
not recur in the submitted log and its cause remains unconfirmed.

Diag3 also adds an in-app share catalog opened from chat avatars. Direct-chat
headers address the selected peer ID; message avatars address the sender ID,
including group senders and self. The catalog reuses the home-page visibility
rules and supports search, folder navigation, pagination, refresh and file links.
Restricted shares keep their access labels without exposing IDs or credentials.
File links open in the system browser; opening the catalog itself needs no
external window. In-app HTTP requests use the discovered LAN endpoint directly.
