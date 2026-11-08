# Miuix UI

The Flutter Windows and Android clients use `flutter_miuix` 1.3.0. The
embedded HTML download client remains a separate implementation.

## Components

- `AppMiuixTheme` follows the saved/system brightness and bold-text preference.
  Existing content tokens match the Miuix palette. MaterialApp, Navigator,
  text selection and system-bar integration remain framework infrastructure.
- Buttons, icon commands, fields, switches, checkboxes, cards, badges,
  progress indicators, dividers and settings rows use Miuix components.
- Desktop navigation uses MiuixNavigationRail; mobile uses MiuixNavigationBar.
- Dialogs, upload sheets and context menus use route-local Miuix popup hosts.
  The returned future completes after the route is removed, before launching
  a native picker or changing a menu's originating row.
- Menus compose MiuixBasicComponent rows so long names wrap on small screens
  and disabled items are skipped during keyboard navigation.
- Toasts compose MiuixCard and icon commands to preserve status icons and
  message-specific lifetimes.
- Tooltips combine MiuixPlainTooltip/MiuixTooltipState with OverlayPortal.
  The package's TooltipBox invalidates an OverlayEntry during widget updates;
  the portal instead preserves theme inheritance and anchor disposal.

`lib/ui/widgets/app_controls.dart` retains application contracts that the
library does not provide, including form validation, character limits after
IME composition, keyboard dismissal and controller ownership. Native file
pickers, window controls, tray integration, HTTP, identity and persistence
are unchanged by this migration.

## Verification

Run functional regression with:

```text
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --exclude-tags=golden
```

On Windows with the existing golden fonts, verify visual snapshots with:

```text
flutter test --no-pub --concurrency=1 --tags=golden
```

Snapshots cover light/dark desktop navigation, chats and shares, plus 360px
mobile navigation, shares and settings. Adapter tests cover theme changes
while a tooltip is visible, tooltip bounds/disposal, dialog Escape/outside
dismissal, mobile keyboards at 150% text scale, IME input, disabled commands,
keyboard menu navigation and long menu labels.

Run headless embedded-web navigation checks separately:

```text
cd test/web
npm ci
npx playwright install chromium --no-shell
npm test
```

Run Flutter test commands sequentially; concurrent invocations can contend for
the same native SQLite DLL. Web tests use a separate headless browser and a
loopback-only fixture server, without changing user browser state.

Package validation does not establish physical Xiaomi or MuMu `.local`
reachability. The user separately confirmed domain/share access with diagnostic builds.

For the earlier Miuix migration candidate on 2026-11-08, static analysis passed,
functional regression passed 1112 tests
with 2 environment-dependent skips, and all 17 golden tests passed. Windows
release and three signed Android ABI packages built successfully in isolated
source directories. Package verification matched the previous release signer,
checked ABI/version/mobile assets, and confirmed all 144 source/dependency inputs
against the working tree.
