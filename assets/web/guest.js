// SPDX-License-Identifier: GPL-3.0-only

// 网页访客页：握手、心跳、页面关闭上报。
//
// 三条不可省略的浏览器侧行为：
//   1. 每 15s 一跳心跳，宿主连续缺 2 拍即判定会话结束；
//   2. beforeunload / pagehide 主动上报 close，让链接立刻 410；
//   3. 上传前必须拿到 grant —— 没有 grant 就调上传接口，服务端会 403。
(function () {
  "use strict";

  var THEME_KEY = "lsf.theme";
  var THEMES = ["auto", "light", "dark"];
  var THEME_LABELS = { auto: "跟随系统", light: "明", dark: "暗" };

  var state = {
    sessionId: null,
    heartbeatMs: 15000,
    timer: null,
    closed: false,
  };

  function $(id) {
    return document.getElementById(id);
  }

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
    var label = $("theme-label");
    if (label) label.textContent = THEME_LABELS[theme] || THEME_LABELS.auto;
    try {
      window.localStorage.setItem(THEME_KEY, theme);
    } catch (error) {
      /* 隐私模式下不可写，主题仍在本页生效。 */
    }
  }

  function cycleTheme() {
    var current = readTheme();
    applyTheme(THEMES[(THEMES.indexOf(current) + 1) % THEMES.length]);
  }

  function setStatus(message) {
    var node = $("status");
    if (node) node.textContent = message;
  }

  function setFeed(ok) {
    var dot = $("feed-dot");
    if (dot) dot.setAttribute("data-online", ok ? "true" : "false");
  }

  function postJson(url, body) {
    return fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
      cache: "no-store",
    }).then(function (response) {
      return response.json().then(function (json) {
        return { status: response.status, json: json };
      });
    });
  }

  // 握手：真实实现里 pubkey 来自 WebCrypto 生成的 ECDSA P-256 密钥对。
  function handshake() {
    return generatePubkey().then(function (pubkey) {
      return postJson("/w/session", { pubkey: pubkey });
    }).then(function (result) {
      if (result.status !== 200) {
        throw new Error("握手失败 HTTP " + result.status);
      }
      state.sessionId = result.json.guestSessionId;
      state.heartbeatMs = (result.json.heartbeatSeconds || 15) * 1000;
      $("session-id").textContent = state.sessionId;
      $("host-peer").textContent = result.json.hostPeer || "…";
      $("quota").textContent = formatBytes(result.json.quotaBytes || 0);
      setFeed(true);
      setStatus("已连接宿主节点，会话生效中。");
      startHeartbeat();
    });
  }

  function generatePubkey() {
    if (!window.crypto || !window.crypto.subtle) {
      return Promise.reject(new Error("当前浏览器不支持 WebCrypto"));
    }
    return window.crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"]
    ).then(function (pair) {
      return window.crypto.subtle.exportKey("spki", pair.publicKey);
    }).then(function (buffer) {
      return base64Url(new Uint8Array(buffer));
    });
  }

  function base64Url(bytes) {
    var binary = "";
    for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return window.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function formatBytes(n) {
    if (!n) return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    var v = n;
    while (v >= 1024 && i < units.length - 1) {
      v = v / 1024;
      i++;
    }
    return (i === 0 ? v : v.toFixed(1)) + " " + units[i];
  }

  function startHeartbeat() {
    stopHeartbeat();
    state.timer = window.setInterval(function () {
      if (!state.sessionId || state.closed) return;
      postJson("/w/session/" + state.sessionId + "/beat", {}).then(function (result) {
        if (result.status === 410) {
          setFeed(false);
          setStatus("会话已结束，请刷新页面重新握手。");
          stopHeartbeat();
        }
      }).catch(function () {
        setFeed(false);
      });
    }, state.heartbeatMs);
  }

  function stopHeartbeat() {
    if (state.timer) {
      window.clearInterval(state.timer);
      state.timer = null;
    }
  }

  // 关闭页面即结束会话：两种事件都上报，失败也不阻塞卸载。
  function reportClose() {
    if (state.closed || !state.sessionId) return;
    state.closed = true;
    var url = "/w/session/" + state.sessionId + "/close";
    try {
      if (navigator.sendBeacon) {
        navigator.sendBeacon(url, new Blob([JSON.stringify({})], { type: "application/json" }));
      } else {
        fetch(url, { method: "POST", keepalive: true });
      }
    } catch (error) {
      /* 上报失败由宿主心跳超时兜底。 */
    }
  }

  function boot() {
    applyTheme(readTheme());
    var toggle = $("theme-toggle");
    if (toggle) toggle.addEventListener("click", cycleTheme);

    window.addEventListener("pagehide", reportClose);
    window.addEventListener("beforeunload", reportClose);

    handshake().catch(function (error) {
      setFeed(false);
      setStatus("握手失败：" + (error && error.message ? error.message : error));
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
