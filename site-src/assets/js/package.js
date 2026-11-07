import {
  loadCatalog, el, icon, plural, formatBytes, isCrossPlatform, needsAdmin, allModules, runsEverywhere,
  copyButton, announce,
} from './common.js';

const VENDOR = '../vendor';
const root = document.getElementById('package-root');
const crumb = document.getElementById('crumb-name');
const repoUrl = document.querySelector('meta[name="opskit-repo"]').content.replace(/\/$/, '');
const id = new URLSearchParams(location.search).get('id') || '';

let hljsPromise;
function loadHighlighter() {
  hljsPromise ??= Promise.all([
    import(`${VENDOR}/highlight.js-11.10.0/core.min.js`),
    import(`${VENDOR}/highlight.js-11.10.0/languages/powershell.min.js`),
    import(`${VENDOR}/highlight.js-11.10.0/languages/markdown.min.js`),
  ]).then(([core, powershell, markdown]) => {
    const hljs = core.default;
    hljs.registerLanguage('powershell', powershell.default);
    hljs.registerLanguage('markdown', markdown.default);
    return hljs;
  });
  return hljsPromise;
}

function languageFor(path) {
  if (/\.(ps1|psd1|psm1)$/i.test(path)) return 'powershell';
  if (/\.md$/i.test(path)) return 'markdown';
  return null;
}

function srcUrl(pkg, path) {
  return `src/${encodeURIComponent(pkg.id)}/${path.split('/').map(encodeURIComponent).join('/')}`;
}

function section(title, ...children) {
  const headingId = `h-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;
  return el('section', { class: 'pkg-section', 'aria-labelledby': headingId },
    el('div', { class: 'section-head' }, el('h2', { id: headingId }, title)),
    ...children);
}

function panel(title, ...children) {
  return el('section', { class: 'panel', 'aria-label': title }, el('h2', { class: 'panel-title' }, title), ...children);
}

function platformText(item) {
  return runsEverywhere(item) ? (item.platforms?.length ? item.platforms.join(', ') : 'All platforms') : 'Windows only';
}

// ---------- Header ----------

function header(pkg) {
  const badges = [el('span', { class: 'badge accent' }, pkg.category), ...allModules(pkg).map((m) => el('span', { class: 'badge', title: 'Required PowerShell module' }, m))];
  if (needsAdmin(pkg)) badges.push(el('span', { class: 'badge warning' }, 'admin'));
  if (!isCrossPlatform(pkg)) badges.push(el('span', { class: 'badge' }, 'Windows'));

  return el('header', { class: 'pkg-header' },
    el('div', {},
      el('h1', {}, pkg.name),
      el('p', { class: 'desc' }, pkg.description),
      el('ul', { class: 'pkg-facts' },
        el('li', {}, 'by ', el('strong', {}, el('a', { href: `https://github.com/${encodeURIComponent(pkg.author)}` }, pkg.author))),
        el('li', {}, 'Version ', el('strong', { class: 'mono' }, pkg.version)),
        el('li', {}, 'Updated ', el('strong', {}, el('time', { datetime: pkg.updated }, pkg.updated))),
        el('li', {}, 'Id ', el('strong', { class: 'mono' }, pkg.id))),
      el('div', { class: 'badges' }, badges)));
}

// ---------- Aside: install, requirements, links ----------

function installPanel(pkg) {
  const zipName = pkg.download.url.split('/').pop();
  const menuPath = `Catalog › ${pkg.name} › Install`;
  const script = [
    `$zip = Join-Path ([IO.Path]::GetTempPath()) '${zipName}'`,
    `Invoke-WebRequest -Uri '${pkg.download.url}' -OutFile $zip`,
    `if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne '${pkg.download.sha256}') { throw 'Checksum mismatch' }`,
    `Expand-Archive -Path $zip -DestinationPath 'C:\\path\\to\\OpsKit\\Custom' -Force`,
  ].join('\n');

  return panel('Install',
    el('div', { class: 'install-step' },
      el('h3', {}, 'In OpsKit', el('span', { class: 'badge' }, 'coming soon')),
      el('div', { class: 'copy-row' }, el('code', {}, menuPath), copyButton(menuPath, 'Copy', 'OpsKit menu path'))),
    el('div', { class: 'install-step' },
      el('h3', {}, 'Manual'),
      el('ol', {},
        el('li', {}, el('a', { href: pkg.download.url, download: zipName }, `Download ${zipName}`), ` (${formatBytes(pkg.download.size)})`),
        el('li', {}, 'Extract it into the OpsKit ', el('code', {}, 'Custom/'), ' folder, so you get ', el('code', {}, `Custom/${pkg.id}/module.psd1`), '.'),
        el('li', {}, 'Restart OpsKit. The package shows up as ', el('strong', {}, pkg.name), ' in the menu.')),
      el('p', { class: 'hash' }, 'SHA-256: ', pkg.download.sha256, ' ', copyButton(pkg.download.sha256, 'Copy', 'SHA-256 checksum'))),
    el('div', { class: 'install-step' },
      el('h3', {}, 'Or with PowerShell'),
      el('p', { class: 'muted' }, 'Downloads, checks the hash and extracts. Change the destination folder first.'),
      el('div', { class: 'copy-row' }, el('pre', { tabindex: '0', 'aria-label': 'PowerShell install commands' }, script), copyButton(script, 'Copy', 'install commands'))));
}

function requirementsPanel(pkg) {
  const modules = allModules(pkg);
  const adminScripts = pkg.scripts.filter((s) => s.requiresAdmin);
  return panel('Requirements',
    el('ul', { class: 'req-list' },
      el('li', {}, 'OpsKit ', el('code', {}, `${pkg.minOpsKitVersion}+`), ' on PowerShell 7.4+'),
      el('li', {}, 'Platforms: ', isCrossPlatform(pkg) ? 'Windows, Linux, macOS' : 'Windows (some or all scripts)'),
      el('li', {}, 'Modules: ', modules.length ? modules.map((m) => el('span', { class: 'badge' }, m)) : 'none'),
      el('li', {}, 'Admin: ', adminScripts.length ? `${adminScripts.map((s) => s.name).join(', ')}` : 'not needed')));
}

function linksPanel(pkg) {
  const issue = new URL(`${repoUrl}/issues/new`);
  issue.searchParams.set('template', 'package-problem.yml');
  issue.searchParams.set('title', `[${pkg.id}] `);
  issue.searchParams.set('package', pkg.id);
  issue.searchParams.set('version', pkg.version);
  return panel('Links',
    el('ul', { class: 'link-list' },
      el('li', {}, el('a', { href: pkg.sourceUrl }, 'View on GitHub')),
      el('li', {}, el('a', { href: issue.href }, 'Report a problem')),
      el('li', {}, el('a', { href: pkg.download.url }, 'Download zip'))));
}

function notice() {
  return el('div', { class: 'notice', role: 'note' }, icon('warning'),
    el('p', { class: 'notice-text' }, el('strong', {}, 'Community scripts run with your permissions. '), 'Read the code before running it.'));
}

// ---------- Main column ----------

function scriptsSection(pkg) {
  const items = pkg.scripts.map((s) => {
    const badges = [el('span', { class: 'badge' }, platformText(s))];
    if (s.requiresAdmin) badges.unshift(el('span', { class: 'badge warning' }, 'needs admin'));
    for (const m of s.requiresModules || []) badges.push(el('span', { class: 'badge' }, m));

    const params = s.parameters.length
      ? el('div', { class: 'table-wrap', tabindex: '0', role: 'region', 'aria-label': `${s.name} parameters` },
        el('table', {},
          el('thead', {}, el('tr', {}, ['Parameter', 'Type', 'Required', 'Prompt'].map((h) => el('th', { scope: 'col' }, h)))),
          el('tbody', {}, s.parameters.map((p) => el('tr', {},
            el('td', {}, el('code', {}, `-${p.name}`)),
            el('td', {}, el('code', {}, p.type)),
            el('td', {}, p.mandatory ? el('span', { class: 'yes' }, 'Yes') : 'No'),
            el('td', {}, p.helpMessage || '', p.validateSet ? el('div', { class: 'muted' }, `One of: ${p.validateSet.join(', ')}`) : null))))))
      : el('p', { class: 'muted' }, 'No parameters.');

    return el('article', { class: 'script' },
      el('h3', {}, s.name),
      el('p', { class: 'file' }, s.file || s.id),
      el('p', {}, s.description),
      el('div', { class: 'badges' }, badges),
      params);
  });
  return section(`Scripts (${pkg.scripts.length})`, el('div', { class: 'script-list' }, items));
}

function widgetsSection(pkg) {
  const items = pkg.widgets.map((w) => {
    const badges = [el('span', { class: 'badge' }, platformText(w))];
    if (w.refreshSeconds) badges.push(el('span', { class: 'badge' }, `refresh ${w.refreshSeconds}s`));
    for (const m of w.requiresModules || []) badges.push(el('span', { class: 'badge' }, m));
    return el('article', { class: 'script' },
      el('h3', {}, w.name),
      el('p', { class: 'file' }, w.file || w.id),
      el('p', {}, w.description),
      el('div', { class: 'badges' }, badges));
  });
  return section(`Home screen widgets (${pkg.widgets.length})`,
    el('p', { class: 'muted' }, 'Widgets are small read-only panels on the OpsKit home screen.'),
    el('div', { class: 'script-list' }, items));
}

function readmeSection(pkg) {
  const body = el('div', { class: 'readme', 'aria-busy': 'true' }, el('p', { class: 'muted' }, 'Loading README…'));
  (async () => {
    try {
      const [{ marked }, purify, text] = await Promise.all([
        import(`${VENDOR}/marked-12.0.2/marked.esm.js`),
        import(`${VENDOR}/dompurify-3.1.6/purify.es.js`),
        fetch(srcUrl(pkg, 'README.md')).then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.text(); }),
      ]);
      const DOMPurify = purify.default;
      const html = DOMPurify.sanitize(marked.parse(text, { gfm: true }), {
        FORBID_TAGS: ['img', 'picture', 'video', 'audio', 'iframe', 'style', 'form', 'input', 'button', 'svg', 'math'],
        FORBID_ATTR: ['style', 'id', 'name'],
      });
      const fragment = el('div');
      fragment.innerHTML = html;
      // The page already has an h1 and h2s: shift README headings down one level.
      for (const h of [...fragment.querySelectorAll('h1, h2, h3, h4, h5')].reverse()) {
        const next = el(`h${Number(h.tagName[1]) + 1}`);
        next.append(...h.childNodes);
        h.replaceWith(next);
      }
      for (const a of fragment.querySelectorAll('a[href]')) {
        if (/^https?:/i.test(a.getAttribute('href'))) a.setAttribute('rel', 'nofollow noopener noreferrer');
      }
      const blocks = fragment.querySelectorAll('pre code');
      if (blocks.length) {
        const hljs = await loadHighlighter();
        for (const code of blocks) {
          const lang = (code.className.match(/language-(\w+)/) || [])[1];
          const language = lang && hljs.getLanguage(lang) ? lang : (/^(ps1|pwsh|posh)$/i.test(lang || '') ? 'powershell' : null);
          if (language) code.innerHTML = hljs.highlight(code.textContent, { language }).value;
        }
      }
      body.replaceChildren(...fragment.childNodes);
    } catch (error) {
      body.replaceChildren(el('p', { class: 'muted' }, `Couldn't load the README (${error.message}).`));
    }
    body.setAttribute('aria-busy', 'false');
  })();
  return section('README', body);
}

function fileOrder(path) {
  if (path === 'module.psd1') return 4;
  if (/^readme\.md$/i.test(path)) return 5;
  if (path.startsWith('Widgets/')) return 3;
  if (path.split('/').pop().startsWith('_')) return 2;
  if (!path.includes('/') && /\.ps1$/i.test(path)) return 1;
  return 6;
}

function sourceSection(pkg) {
  const files = [...pkg.files].sort((a, b) => fileOrder(a.path) - fileOrder(b.path) || a.path.localeCompare(b.path));
  const tabList = el('div', { class: 'file-tabs', role: 'tablist', 'aria-label': 'Package files' });
  const fileLabel = el('span', { class: 'mono' });
  const fileInfo = el('span');
  const rawLink = el('a', {}, 'Raw');
  let currentText = '';
  const toolbar = el('div', { class: 'code-toolbar' },
    el('span', {}, fileLabel, ' ', fileInfo),
    el('span', { class: 'badges' }, rawLink, copyButton(() => currentText, 'Copy', 'file contents')));
  const gutter = el('pre', { class: 'gutter', 'aria-hidden': 'true' });
  const code = el('code');
  const codePre = el('pre', { class: 'code' }, code);
  const view = el('div', { class: 'code-view', role: 'tabpanel', tabindex: '0', id: 'source-panel' }, gutter, codePre);
  const cache = new Map();

  const tabs = files.map((file, index) => el('button', {
    type: 'button',
    role: 'tab',
    class: 'file-tab',
    id: `tab-${index}`,
    'aria-selected': 'false',
    'aria-controls': 'source-panel',
    tabindex: '-1',
    dataset: { path: file.path },
    onclick: () => select(index, true),
    onkeydown: (event) => {
      const keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      let next = null;
      if (event.key in keys) next = (index + keys[event.key] + files.length) % files.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = files.length - 1;
      if (next !== null) { event.preventDefault(); select(next, true); tabs[next].focus(); }
    },
  }, file.path));
  tabList.append(...tabs);

  async function select(index, updateHash) {
    const file = files[index];
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === index));
      tab.tabIndex = i === index ? 0 : -1;
    });
    view.setAttribute('aria-labelledby', tabs[index].id);
    fileLabel.textContent = file.path;
    fileInfo.textContent = '';
    rawLink.href = srcUrl(pkg, file.path);
    if (updateHash) history.replaceState(null, '', `#file=${encodeURIComponent(file.path)}`);
    view.setAttribute('aria-busy', 'true');
    try {
      if (!cache.has(file.path)) {
        const response = await fetch(srcUrl(pkg, file.path));
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        cache.set(file.path, (await response.text()).replace(/\r\n?/g, '\n'));
      }
      if (tabs[index].getAttribute('aria-selected') !== 'true') return;   // another tab was picked meanwhile
      const text = cache.get(file.path).replace(/\n$/, '');
      currentText = text;
      const lines = text.split('\n').length;
      gutter.textContent = Array.from({ length: lines }, (_, i) => i + 1).join('\n');
      fileInfo.textContent = `· ${plural(lines, 'line')} · ${formatBytes(file.size ?? text.length)}`;
      const language = languageFor(file.path);
      code.textContent = text;
      if (language) {
        const hljs = await loadHighlighter();
        if (tabs[index].getAttribute('aria-selected') === 'true') code.innerHTML = hljs.highlight(text, { language }).value;
      }
    } catch (error) {
      gutter.textContent = '';
      code.textContent = `Couldn't load ${file.path} (${error.message}).`;
    }
    view.setAttribute('aria-busy', 'false');
  }

  const fromHash = decodeURIComponent((location.hash.match(/^#file=(.+)$/) || [])[1] || '');
  const start = Math.max(0, files.findIndex((f) => f.path === fromHash));
  select(start, false);
  if (fromHash) requestAnimationFrame(() => view.scrollIntoView({ block: 'start' }));

  return section('Source', el('p', { class: 'muted' }, 'Exactly what the zip contains.'), el('div', { class: 'source' }, tabList, toolbar, view));
}

// ---------- Page ----------

function render(pkg) {
  document.title = `${pkg.name} · OpsKit Catalog`;
  document.querySelector('meta[name="description"]')?.setAttribute('content', `${pkg.name}: ${pkg.description}`);
  crumb.textContent = pkg.name;

  const main = [scriptsSection(pkg)];
  if (pkg.widgets.length) main.push(widgetsSection(pkg));
  if (pkg.files.some((f) => /^readme\.md$/i.test(f.path))) main.push(readmeSection(pkg));
  main.push(sourceSection(pkg));

  root.replaceChildren(
    header(pkg),
    el('div', { class: 'pkg-layout' },
      el('div', { class: 'pkg-main' }, main),
      el('aside', { class: 'pkg-aside', 'aria-label': 'Install and details' },
        notice(), installPanel(pkg), requirementsPanel(pkg), linksPanel(pkg))));
  root.classList.remove('loading-block');
  root.setAttribute('aria-busy', 'false');
}

function notFound(message) {
  document.title = 'Package not found · OpsKit Catalog';
  crumb.textContent = 'Not found';
  root.replaceChildren(
    el('h1', {}, 'Package not found'),
    el('p', {}, message),
    el('p', {}, el('a', { class: 'button', href: './' }, 'Browse all packages')));
  root.classList.remove('loading-block');
  root.setAttribute('aria-busy', 'false');
  announce('Package not found');
}

try {
  const catalog = await loadCatalog();
  const pkg = catalog.packages.find((p) => p.id === id) || catalog.packages.find((p) => p.id.toLowerCase() === id.toLowerCase());
  if (pkg) render(pkg);
  else notFound(id ? `There is no package with the id “${id}”.` : 'No package id was given.');
} catch (error) {
  notFound(`Couldn't load the catalog (${error.message}).`);
}
