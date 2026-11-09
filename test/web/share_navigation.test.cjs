// SPDX-License-Identifier: GPL-3.0-only
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const http = require('node:http');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const folder = 'primary:DCIM/Camera/旅行 100%20';
const nested = folder + '/二级';
let browser, server, origin;
let delayFolder = false;
let folderRequested;
let groupedCatalog = false;
const entry = (key, isDir) => ({ key, name: key.split('/').at(-1), isDir, size: 12 });

before(async () => {
  const avatar = await fs.readFile(path.join(root, 'assets/logos/c.png'));
  const assets = {};
  for (const name of ['index.html', 'share.html', 'share.js', 'app.js', 'style.css']) {
    assets[name] = await fs.readFile(path.join(root, 'assets/web', name), 'utf8');
  }
  const html = assets['share.html'].replaceAll('__LSF_SHARE_ID__', 'test')
    .replaceAll('__LSF_SHARE_NAME__', '旅行照片').replaceAll('__LSF_SHARE_OWNER_NAME__', '好好吃饭')
    .replaceAll('__LSF_SHARE_OWNER_AVATAR__', '/avatar.png')
    .replaceAll('__LSF_SHARE_PEER__', 'p_test').replaceAll('__LSF_CLIENT_DOWNLOAD__', '');
  server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/avatar.png') {
      res.writeHead(200, { 'Content-Type': 'image/png' });
      return res.end(avatar);
    }
    function json(data, status = 200) {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data));
    }
    if (url.pathname === '/api/v1/ping') return json({ name: '好好吃饭' });
    if (url.pathname === '/api/v1/shared-roots' && groupedCatalog) {
      const group = url.searchParams.get('group');
      if (group !== null && !['work', 'photos', ''].includes(group)) return json({ error: '分享分组不存在或已删除' }, 404);
      const shares = [
        { name: 'b.txt', kind: 'file', access: 'browse', href: '/s/test', collectionId: 'work' },
        { name: 'z-folder', kind: 'folder', access: 'browse', href: '/s/test', collectionId: 'work' },
        { name: 'a.txt', kind: 'file', access: 'browse', href: '/s/test', collectionId: 'photos' },
      ];
      return json({ owner: { name: '好好吃饭' }, order: 'owner', groups: [
        { id: 'work', name: '工作资料' }, { id: 'photos', name: '<script>照片</script>' },
      ], shares: group === null ? shares : shares.filter(s => s.collectionId === group) });
    }
    if (url.pathname === '/api/v1/shared-roots') return json({ owner: { name: '好好吃饭' }, shares: [
      { name: 'a.txt', kind: 'file', access: 'browse', href: '/s/test' },
      { name: 'z-folder', kind: 'folder', access: 'browse', href: '/s/test' },
    ] });
    if (url.pathname === '/s/test/tree') {
      const dir = url.searchParams.get('path');
      if (dir === 'missing') return json({ message: 'Directory not found' }, 404);
      if (dir === folder && delayFolder) {
        folderRequested?.();
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      let entries, nextCursor = null;
      if (!dir) {
        entries = url.searchParams.get('cursor')
          ? [entry('primary:DCIM/Camera/b.txt', false)]
          : [entry('primary:DCIM/Camera/a.txt', false), entry(folder, true)];
        if (!url.searchParams.get('cursor')) nextCursor = '\u0001d/' + folder;
      } else if (dir === folder) entries = [entry(folder + '/a.txt', false), entry(nested, true)];
      else if (dir === nested) entries = [entry(nested + '/文件%20.txt', false)];
      else return json({ message: 'Out of root' }, 403);
      return json({ rootKey: 'primary:DCIM/Camera', entries, nextCursor });
    }
    const filename = url.pathname.startsWith('/web/') ? url.pathname.slice(5) : null;
    const body = url.pathname === '/' ? assets['index.html'] : url.pathname === '/s/test' ? html : assets[filename];
    if (body !== undefined) {
      res.writeHead(200, { 'Content-Type': filename?.endsWith('.js') ? 'text/javascript; charset=utf-8' :
        filename?.endsWith('.css') ? 'text/css' : 'text/html; charset=utf-8' });
      return res.end(body);
    }
    res.writeHead(404); res.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true, channel: 'chromium' });
});

after(async () => {
  await browser?.close();
  if (server) await new Promise(resolve => server.close(resolve));
});

async function ready(page, names) {
  await page.waitForFunction(expected => {
    const actual = Array.from(document.querySelectorAll('#entries .entry-name'), x => x.textContent);
    return JSON.stringify(actual) === JSON.stringify(expected) && document.querySelector('#status').textContent.startsWith('已列出');
  }, names);
}

for (const [name, viewport] of Object.entries({ mobile: { width: 390, height: 844 }, desktop: { width: 1280, height: 800 } })) {
  test(`${name}: share groups preserve owner order, deep links and browser history`, async () => {
    groupedCatalog = true;
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(origin + '/');
      await page.waitForSelector('.catalog-entry');
      assert.deepEqual(await page.locator('.catalog-entry-name').allTextContents(), ['b.txt', 'z-folder', 'a.txt']);
      assert.deepEqual(await page.locator('.catalog-group-heading').allTextContents(), ['工作资料', '<script>照片</script>']);
      await page.selectOption('#share-group', 'work');
      await page.waitForFunction(() => document.querySelectorAll('.catalog-entry').length === 2);
      assert.equal(new URL(page.url()).searchParams.get('group'), 'work');
      await page.reload();
      await page.waitForSelector('.catalog-entry');
      assert.deepEqual(await page.locator('.catalog-entry-name').allTextContents(), ['b.txt', 'z-folder']);
      await page.selectOption('#share-group', 'photos');
      await page.waitForFunction(() => document.querySelectorAll('.catalog-entry').length === 1);
      await page.goBack();
      await page.waitForFunction(() => document.querySelectorAll('.catalog-entry').length === 2);
      assert.equal(await page.locator('#share-group').inputValue(), 'work');
      await page.screenshot({ path: path.join(root, `build/web-regression/groups-${name}.png`), fullPage: true });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      await page.goto(origin + '/?group=deleted');
      await page.waitForFunction(() => document.querySelector('#status').textContent.includes('分组不存在'));
      assert.equal(await page.locator('.catalog-entry').count(), 0);
      await page.selectOption('#share-group', '*');
      await page.waitForFunction(() => document.querySelectorAll('.catalog-entry').length === 3);
      assert.deepEqual(errors, []);
    } finally { groupedCatalog = false; await page.close(); }
  });
}

for (const [name, viewport] of Object.entries({ mobile: { width: 390, height: 844 }, desktop: { width: 1280, height: 800 } })) {
  test(`${name}: folder-first catalog, paging, deep links, refresh and history`, async () => {
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(origin + '/');
      await page.waitForSelector('.catalog-entry');
      assert.deepEqual(await page.locator('.catalog-entry-name').allTextContents(), ['z-folder', 'a.txt']);
      await page.goto(origin + '/s/test?token=keep%2Bthis#files');
      await page.waitForFunction(() => {
        const image = document.querySelector('.share-owner-avatar');
        return image.complete && image.naturalWidth > 0;
      });
      await ready(page, ['旅行 100%20', 'a.txt']);
      await page.locator('#load-more').click();
      await ready(page, ['旅行 100%20', 'a.txt', 'b.txt']);
      const directory = page.locator('.entry-dir a');
      const href = new URL(await directory.getAttribute('href'), origin);
      assert.equal(href.searchParams.get('path'), folder);
      assert.equal(href.searchParams.get('token'), 'keep+this');
      assert.equal(href.hash, '#files');
      await directory.click();
      await ready(page, ['二级', 'a.txt']);
      assert.equal(new URL(page.url()).searchParams.get('path'), folder);
      assert.deepEqual(await page.locator('#crumbs a').allTextContents(), ['根目录', '旅行 100%20']);
      await page.reload();
      await ready(page, ['二级', 'a.txt']);
      await page.locator('.entry-dir a').click();
      await ready(page, ['文件%20.txt']);
      assert.equal(new URL(page.url()).searchParams.get('path'), nested);
      assert.ok((await page.locator('#download-zip').getAttribute('href')).includes(encodeURIComponent(nested)));
      assert.ok((await page.locator('.entry-name').getAttribute('href')).endsWith('%E6%96%87%E4%BB%B6%2520.txt'));
      await page.goBack();
      await ready(page, ['二级', 'a.txt']);
      await page.goForward();
      await ready(page, ['文件%20.txt']);
      await page.locator('#refresh').click();
      await ready(page, ['文件%20.txt']);
      await page.goBack();
      await ready(page, ['二级', 'a.txt']);
      await fs.mkdir(path.join(root, 'build/web-regression'), { recursive: true });
      await page.screenshot({ path: path.join(root, `build/web-regression/${name}.png`), fullPage: true });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      await page.locator('#crumbs a').first().click();
      await ready(page, ['旅行 100%20', 'a.txt']);
      assert.equal(new URL(page.url()).searchParams.has('path'), false);
      assert.deepEqual(errors, []);
    } finally { await page.close(); }
  });
}

test('stale requests cannot replace a later route; failed deep links can return home', async () => {
  const page = await browser.newPage();
  try {
    await page.goto(origin + '/s/test');
    await ready(page, ['旅行 100%20', 'a.txt']);
    delayFolder = true;
    const requested = new Promise(resolve => { folderRequested = resolve; });
    await page.locator('.entry-dir a').click();
    await requested;
    await page.locator('#crumbs a').first().click();
    await ready(page, ['旅行 100%20', 'a.txt']);
    await page.waitForTimeout(350);
    await ready(page, ['旅行 100%20', 'a.txt']);
    await page.goto(origin + '/s/test?path=missing');
    await page.waitForFunction(() => document.querySelector('#status').textContent.includes('Directory not found'));
    await page.locator('#crumbs a').first().click();
    await ready(page, ['旅行 100%20', 'a.txt']);
  } finally { delayFolder = false; await page.close(); }
});
