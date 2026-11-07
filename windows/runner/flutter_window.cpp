#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "native_file_drop.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lan_simple_file/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "destroy") {
          result->NotImplemented();
          return;
        }
        // Leave the Flutter callback stack before destroying its engine.
        if (!PostMessage(GetHandle(), WM_CLOSE, 0, 0)) {
          result->Error("close_failed", "Cannot schedule window shutdown");
          return;
        }
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  elevated_file_drop_ = EnableElevatedFileDrop(
      GetHandle(), flutter_controller_->view()->GetNativeWindow());

  // Dart decides visibility after loading the saved startup preference and
  // registering the tray. Showing the first frame here would flash the window
  // and take focus even for a silent launch.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DROPFILES && elevated_file_drop_ && flutter_controller_) {
    const auto drop = ReadNativeFileDrop(
        reinterpret_cast<HDROP>(wparam), hwnd,
        flutter_controller_->view()->GetNativeWindow());
    flutter::MethodChannel<flutter::EncodableValue> channel(
        flutter_controller_->engine()->messenger(), "desktop_drop",
        &flutter::StandardMethodCodec::GetInstance());
    channel.InvokeMethod(
        "entered", std::make_unique<flutter::EncodableValue>(
                       flutter::EncodableList{
                           flutter::EncodableValue(double(drop.position.x)),
                           flutter::EncodableValue(double(drop.position.y))}));
    flutter::EncodableList paths;
    for (const auto& path : drop.paths) paths.emplace_back(path);
    channel.InvokeMethod("performOperation",
                         std::make_unique<flutter::EncodableValue>(paths));
    channel.InvokeMethod("exited", nullptr);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
