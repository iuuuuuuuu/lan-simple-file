// SPDX-License-Identifier: GPL-3.0-only

// The root page lists only the serving node's published shares.
(function () {
  "use strict";

  var THEME_KEY = "lsf.theme";
  var THEMES = ["auto", "light", "dark"];
  var THEME_LABELS = { auto: "跟随系统", light: "明", dark: "暗" };
  var shares = [];
  var groups = [];
  var requestRevision = 0;
  var controller;

  function selectedGroup() {
    return new URL(window.location.href).searchParams.get('group');
  }

  function renderGroups() {
    var select = document.getElementById('share-group');
    select.textContent = '';
    [{ id: '*', name: '全部分组' }].concat(groups).forEach(function (group) {
      var option = document.createElement('option');
      option.value = group.id;
      option.textContent = group.name;
      select.appendChild(option);
    });
    select.value = selectedGroup() === null ? '*' : selectedGroup();
    document.getElementById('group-filter').hidden = groups.every(function (group) {
      return group.id === '';
    }) && selectedGroup() === null;
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
    var toggle = document.getElementById("theme-toggle");
    if (toggle) toggle.title = "切换明暗主题（" + THEME_LABELS[theme] + "）";
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

  function getJson(path, signal) {
    return fetch(path, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      signal: signal,
    }).then(function (response) {
      if (!response.ok) {
        return response.json().then(function (data) {
          throw new Error(data.error || 'HTTP ' + response.status);
        });
      }
      return response.json();
    });
  }

  function renderOwner(owner) {
    var title = (owner.name || "本机") + "的分享";
    setText("catalog-title", title);
    document.title = title + " · lan-simple-file";
    setText("catalog-domain", window.location.host);
    var avatar = document.getElementById("owner-avatar");
    if (avatar && owner.avatar) {
      var url = new URL(owner.avatar, window.location.href);
      if (url.origin === window.location.origin && url.pathname.indexOf("/api/v1/avatar/") === 0) {
        avatar.src = url.href;
        avatar.hidden = false;
        avatar.onerror = function () { avatar.hidden = true; };
      }
    }
  }

  function renderShares() {
    var search = document.getElementById("share-search").value.trim().toLocaleLowerCase();
    var visible = shares.filter(function (entry) {
      return String(entry.name || "").toLocaleLowerCase().indexOf(search) >= 0;
    });
    var list = document.getElementById("shared-roots");
    list.textContent = "";
    var lastGroup = null;
    visible.forEach(function (entry) {
      var collection = entry.collectionId || '';
      if (selectedGroup() === null && groups.some(function (g) { return g.id !== ''; }) && lastGroup !== collection) {
        var group = groups.find(function (g) { return g.id === collection; });
        var heading = document.createElement('li');
        heading.className = 'catalog-group-heading';
        heading.textContent = group ? group.name : '未分组';
        list.appendChild(heading);
        lastGroup = collection;
      }
      var row = document.createElement("li");
      row.className = "catalog-entry";
      var folder = entry.kind === "folder";
      var icon = document.getElementById(folder ? "catalog-folder-icon" : "catalog-file-icon");
      row.appendChild(icon.content.cloneNode(true));
      var href = null;
      if (entry.access === "browse" && typeof entry.href === "string") {
        var url = new URL(entry.href, window.location.href);
        if (url.origin === window.location.origin && /^\/s\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
          href = url.pathname + url.search;
        }
      }
      var name = document.createElement(href ? "a" : "span");
      name.className = "catalog-entry-name";
      name.textContent = entry.name;
      if (href) name.href = href;
      row.appendChild(name);
      var meta = document.createElement("span");
      meta.className = "catalog-entry-meta";
      var labels = { password: "需口令", people: "仅限指定用户", group: "仅限群组" };
      meta.textContent = href ? (folder ? "文件夹" : "文件") : (labels[entry.access] || "受限分享");
      row.appendChild(meta);
      list.appendChild(row);
    });
    setStatus(search ? "共 " + shares.length + " 项，匹配 " + visible.length + " 项" : "共 " + shares.length + " 项");
    var empty = document.getElementById("empty-state");
    empty.hidden = visible.length > 0;
    empty.textContent = search ? "没有匹配的分享" : "还没有可访问的分享";
  }

  function loadShares() {
    var revision = ++requestRevision;
    if (controller) controller.abort();
    controller = new AbortController();
    var signal = controller.signal;
    shares = [];
    document.getElementById('shared-roots').textContent = '';
    document.getElementById('empty-state').hidden = true;
    var refresh = document.getElementById("refresh");
    refresh.disabled = true;
    document.getElementById("shared-roots").setAttribute("aria-busy", "true");
    setStatus("正在读取分享…");
    var group = selectedGroup();
    var catalogUrl = '/api/v1/shared-roots' + (group === null ? '' : '?group=' + encodeURIComponent(group));
    Promise.all([getJson("/api/v1/ping", signal), getJson(catalogUrl, signal)])
      .then(function (results) {
        if (revision !== requestRevision) return;
        var payload = results[1];
        renderOwner(payload.owner || results[0]);
        shares = Array.isArray(payload.shares) ? payload.shares : [];
        groups = Array.isArray(payload.groups) ? payload.groups : [];
        renderGroups();
        if (payload.order !== 'owner') shares.sort(function (a, b) {
          return (b.kind === "folder") - (a.kind === "folder") ||
            String(a.name).localeCompare(String(b.name));
        });
        renderShares();
      })
      .catch(function (error) {
        if (revision !== requestRevision) return;
        setStatus("读取分享失败：" + (error && error.message ? error.message : String(error)));
        document.getElementById('group-filter').hidden = false;
        var select = document.getElementById('share-group');
        select.textContent = '';
        var option = document.createElement('option');
        option.value = '*'; option.textContent = '全部分组';
        select.appendChild(option);
        select.selectedIndex = -1;
      })
      .then(function () {
        if (revision !== requestRevision) return;
        refresh.disabled = false;
        document.getElementById("shared-roots").removeAttribute("aria-busy");
      });
  }

  function boot() {
    applyTheme(readTheme());
    var toggle = document.getElementById("theme-toggle");
    if (toggle) toggle.addEventListener("click", cycleTheme);

    document.getElementById("refresh").addEventListener("click", loadShares);
    document.getElementById("share-search").addEventListener("input", renderShares);
    document.getElementById('share-group').addEventListener('change', function (event) {
      var url = new URL(window.location.href);
      if (event.target.value === '*') url.searchParams.delete('group');
      else url.searchParams.set('group', event.target.value);
      window.history.pushState(null, '', url);
      loadShares();
    });
    window.addEventListener('popstate', loadShares);
    setText("catalog-domain", window.location.host);
    loadShares();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
