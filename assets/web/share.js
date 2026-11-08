// SPDX-License-Identifier: GPL-3.0-only

// 取件页：按 /s/:shareId/tree 拉目录，按 /s/:shareId/f/ 下载单文件。
// 不做任何本地存储；离开页面即失效（服务端不保留状态）。
(function () {
  "use strict";

  var THEME_KEY = "lsf.theme";
  var THEMES = ["auto", "light", "dark"];
  var THEME_LABELS = { auto: "跟随系统", light: "明", dark: "暗" };

  var body = document.body;
  var shareId = body.getAttribute("data-share-id") || "";
  var currentPath = "";
  var nextCursor = null;
  var loading = false;
  var requestRevision = 0;
  var pendingRequest = null;
  var shownEntries = [];
  var rootKey = "";

  function routePath() {
    return new URL(window.location.href).searchParams.get("path") || "";
  }

  function directoryUrl(path) {
    var url = new URL(window.location.href);
    if (path) url.searchParams.set("path", path);
    else url.searchParams.delete("path");
    return url.pathname + url.search + url.hash;
  }

  function directoryLink(link, path) {
    link.href = directoryUrl(path);
    link.addEventListener("click", function (event) {
      if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      navigate(path, true);
    });
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
    var label = document.getElementById("theme-label");
    if (label) label.textContent = THEME_LABELS[theme] || THEME_LABELS.auto;
    try {
      window.localStorage.setItem(THEME_KEY, theme);
    } catch (error) {
      /* 隐私模式下写不进去，本页仍然生效。 */
    }
  }

  function cycleTheme() {
    var current = readTheme();
    applyTheme(THEMES[(THEMES.indexOf(current) + 1) % THEMES.length]);
  }

  function setText(id, value) {
    var node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function setStatus(message) {
    setText("status", message);
  }

  function fileUrl(key) {
    return "/s/" + encodeURIComponent(shareId) + "/f/" + encodePath(key);
  }

  function zipUrl(path) {
    return "/s/" + encodeURIComponent(shareId) + "/zip?path=" + encodeURIComponent(path);
  }

  function treeUrl(path, cursor) {
    var url = "/s/" + encodeURIComponent(shareId) + "/tree?path=" + encodeURIComponent(path);
    if (cursor) url += "&cursor=" + encodeURIComponent(cursor);
    return url;
  }

  // 逐段编码，保留分隔斜杠，避免把整条路径编码成一个段。
  function encodePath(key) {
    return String(key)
      .split("/")
      .map(function (part) {
        return encodeURIComponent(part);
      })
      .join("/");
  }

  function formatSize(size) {
    if (size === null || size === undefined) return "—";
    if (size < 1024) return size + " B";
    var units = ["KB", "MB", "GB", "TB"];
    var value = size;
    var index = -1;
    do {
      value = value / 1024;
      index++;
    } while (value >= 1024 && index < units.length - 1);
    return value.toFixed(value >= 10 ? 0 : 1) + " " + units[index];
  }

  function formatTime(millis) {
    if (!millis) return "";
    try {
      return new Date(millis).toLocaleString();
    } catch (error) {
      return "";
    }
  }

  function appendEntries(entries) {
    var list = document.getElementById("entries");
    var card = document.getElementById("list-card");
    if (!list || !card) return;
    card.hidden = false;
    shownEntries = shownEntries.concat(entries);
    shownEntries.sort(function (a, b) {
      return Number(b.isDir) - Number(a.isDir) || String(a.key).localeCompare(String(b.key));
    });
    list.textContent = "";
    shownEntries.forEach(function (entry) {
      var li = document.createElement("li");
      li.className = "entry" + (entry.isDir ? " entry-dir" : "");

      var link = document.createElement("a");
      link.className = "entry-name";
      link.textContent = entry.name;
      if (entry.isDir) {
        directoryLink(link, entry.key);
      } else {
        link.href = fileUrl(entry.key);
        link.setAttribute("download", "");
      }
      li.appendChild(link);

      var meta = document.createElement("span");
      meta.className = "entry-meta mono";
      meta.textContent = entry.isDir ? "目录" : formatSize(entry.size);
      li.appendChild(meta);

      if (!entry.isDir && entry.modifiedAt) {
        var time = document.createElement("span");
        time.className = "entry-time";
        time.textContent = formatTime(entry.modifiedAt);
        li.appendChild(time);
      }
      list.appendChild(li);
    });
  }

  function renderCrumbs() {
    var nav = document.getElementById("crumbs");
    if (!nav) return;
    nav.textContent = "";
    var root = document.createElement("a");
    directoryLink(root, "");
    root.textContent = "根目录";
    nav.appendChild(root);
    if (!currentPath) return;
    var relative = currentPath;
    var accumulated = "";
    if (rootKey && rootKey !== ".") {
      if (currentPath === rootKey) return;
      if (currentPath.indexOf(rootKey + "/") === 0) {
        relative = currentPath.slice(rootKey.length + 1);
        accumulated = rootKey;
      }
    }
    var parts = relative.split("/");
    parts.forEach(function (part) {
      accumulated = accumulated ? accumulated + "/" + part : part;
      var target = accumulated;
      var sep = document.createElement("span");
      sep.className = "crumb-sep";
      sep.textContent = "/";
      nav.appendChild(sep);
      var link = document.createElement("a");
      directoryLink(link, target);
      link.textContent = part;
      nav.appendChild(link);
    });
  }

  function load(path, cursor, append) {
    if (append && loading) return;
    if (pendingRequest) pendingRequest.abort();
    pendingRequest = new AbortController();
    var revision = ++requestRevision;
    loading = true;
    if (!append) {
      var list = document.getElementById("entries");
      if (list) list.textContent = "";
      shownEntries = [];
      nextCursor = null;
      setStatus("正在读取目录…");
    }
    var more = document.getElementById("more-row");
    if (more) more.hidden = true;
    fetch(treeUrl(path, cursor), {
      headers: { Accept: "application/json" },
      cache: "no-store",
      signal: pendingRequest.signal,
    })
      .then(function (response) {
        if (!response.ok) {
          return response.json().then(
            function (payload) {
              throw new Error(payload && payload.message ? payload.message : "HTTP " + response.status);
            },
            function () {
              throw new Error("HTTP " + response.status);
            }
          );
        }
        return response.json();
      })
      .then(function (payload) {
        if (revision !== requestRevision) return;
        rootKey = payload.rootKey || "";
        renderCrumbs();
        var entries = Array.isArray(payload.entries) ? payload.entries : [];
        nextCursor = payload.nextCursor || null;
        appendEntries(entries);
        var more = document.getElementById("more-row");
        if (more) more.hidden = !nextCursor;
        if (entries.length === 0 && !append) {
          setStatus("这个目录是空的。");
        } else {
          setStatus("已列出 " + document.querySelectorAll("#entries .entry").length + " 项。");
        }
        setOnline(true);
      })
      .catch(function (error) {
        if (revision !== requestRevision || error.name === "AbortError") return;
        if (more) more.hidden = !nextCursor;
        setOnline(false);
        setStatus("读取失败：" + (error && error.message ? error.message : String(error)));
      })
      .then(function () {
        if (revision !== requestRevision) return;
        loading = false;
        pendingRequest = null;
      });
  }

  function navigate(path, push) {
    currentPath = path || "";
    if (push && routePath() !== currentPath) {
      window.history.pushState(null, "", directoryUrl(currentPath));
    }
    renderCrumbs();
    var zip = document.getElementById("download-zip");
    if (zip) zip.href = zipUrl(currentPath);
    load(currentPath, null, false);
  }

  function setOnline(online) {
    var dot = document.getElementById("dot");
    if (dot) dot.setAttribute("data-online", online ? "true" : "false");
  }

  // 打包超过上限时服务端改发清单 JSON，这里如实提示，不静默失败。
  function probeZip() {
    var link = document.getElementById("download-zip");
    if (!link) return;
    link.addEventListener("click", function () {
      fetch(zipUrl(currentPath), {
        headers: { Accept: "application/json", Range: "bytes=0-0" },
        cache: "no-store",
      })
        .then(function (response) {
          if (response.ok && response.headers.get("content-type") === "application/json") {
            return response.json();
          }
          return null;
        })
        .then(function (payload) {
          if (payload && payload.mode === "manifest") {
            setStatus("文件太多（共 " + payload.total + " 个），请逐项下载。");
          }
        })
        .catch(function (error) {
          setStatus("打包检查失败：" + (error && error.message ? error.message : String(error)));
        });
    });
  }

  function boot() {
    applyTheme(readTheme());
    var toggle = document.getElementById("theme-toggle");
    if (toggle) toggle.addEventListener("click", cycleTheme);

    var more = document.getElementById("load-more");
    if (more) {
      more.addEventListener("click", function () {
        if (nextCursor) load(currentPath, nextCursor, true);
      });
    }
    var refresh = document.getElementById("refresh");
    if (refresh) {
      refresh.addEventListener("click", function () {
        navigate(currentPath);
      });
    }
    probeZip();
    if (!shareId) {
      setOnline(false);
      setStatus("地址缺少分享标识，无法浏览。");
      return;
    }
    window.addEventListener("popstate", function () { navigate(routePath()); });
    navigate(routePath());
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
