// SPDX-License-Identifier: GPL-3.0-only

// 网页骨架：只在 M0 阶段证明「页面能加载、能 ping 到本机节点」。
// 后续里程碑在这里接发现列表、分享树、传输与 WS。
(function () {
  "use strict";

  var THEME_KEY = "lsf.theme";
  var THEMES = ["auto", "light", "dark"];
  var THEME_LABELS = { auto: "跟随系统", light: "明", dark: "暗" };

  function readTheme() {
    try {
      var stored = window.localStorage.getItem(THEME_KEY);
      return THEMES.indexOf(stored) >= 0 ? stored : "auto";
    } catch (error) {
      return "auto";
    }
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    var label = document.getElementById("theme-label");
    if (label) label.textContent = THEME_LABELS[theme] || THEME_LABELS.auto;
    try {
      window.localStorage.setItem(THEME_KEY, theme);
    } catch (error) {
      /* 隐私模式下 localStorage 不可写，主题仍在本页生效。 */
    }
  }

  function cycleTheme() {
    var current = readTheme();
    var next = THEMES[(THEMES.indexOf(current) + 1) % THEMES.length];
    applyTheme(next);
  }

  function setText(id, value) {
    var node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function setStatus(message) {
    setText("status", message);
  }

  function setOnline(online) {
    var dot = document.getElementById("dot");
    if (dot) dot.setAttribute("data-online", online ? "true" : "false");
  }

  function ping() {
    return fetch("/api/v1/ping", {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
    }).then(function (response) {
      if (!response.ok) {
        throw new Error("HTTP " + response.status);
      }
      return response.json();
    });
  }

  function renderSelf(payload) {
    setText("self-name", payload.name || "（未命名设备）");
    setText("self-id", payload.peerId || "…");
    setText("self-proto", String(payload.proto));
    setOnline(true);
    setStatus("已连接本机节点。");
  }

  function reportFailure(error) {
    setOnline(false);
    setStatus("连接本机节点失败：" + (error && error.message ? error.message : String(error)));
  }

  function boot() {
    applyTheme(readTheme());
    var toggle = document.getElementById("theme-toggle");
    if (toggle) toggle.addEventListener("click", cycleTheme);

    ping().then(renderSelf).catch(reportFailure);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
