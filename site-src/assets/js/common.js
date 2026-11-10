// Shared helpers for every page. Importing this module also wires up the theme toggle.

const THEME_KEY = 'opskit-theme';
const root = document.documentElement;
const darkQuery = matchMedia('(prefers-color-scheme: dark)');

function currentTheme() {
  return root.dataset.theme || (darkQuery.matches ? 'dark' : 'light');
}

function initThemeToggle() {
  const button = document.getElementById('theme-toggle');
  if (!button) return;
  const label = () => {
    const next = currentTheme() === 'dark' ? 'light' : 'dark';
    button.setAttribute('aria-label', `Switch to ${next} theme`);
    button.title = `Switch to ${next} theme`;
  };
  label();
  button.hidden = false;
  button.addEventListener('click', () => {
    const next = currentTheme() === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    try { localStorage.setItem(THEME_KEY, next); } catch { /* not saved, still applied */ }
    label();
  });
  darkQuery.addEventListener('change', label);
}

// Screen reader announcements (copy feedback, result counts).
const live = document.createElement('div');
live.className = 'visually-hidden';
live.setAttribute('role', 'status');
live.setAttribute('aria-live', 'polite');
document.body.append(live);

export function announce(message) {
  live.textContent = '';
  setTimeout(() => { live.textContent = message; }, 50);
}

/** Creates an element. attrs: class, text, dataset, on<event>, or any attribute. Children: nodes or strings. */
export function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key === 'dataset') Object.assign(node.dataset, value);
    else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : String(value));
  }
  for (const child of children.flat()) {
    if (child === undefined || child === null || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

const ICONS = {
  shield: '<path d="M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3Z"/>',
  warning: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>',
  download: '<path d="M12 3v12m0 0-5-5m5 5 5-5M4 21h16"/>',
  github: '<path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21"/>',
  bug: '<path d="M8 2l1.9 1.9M16 2l-1.9 1.9M9 7.1V6a3 3 0 0 1 6 0v1.1M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6Zm0 0v-9M6 13H2M22 13h-4M6.5 8.5 4 6M17.5 8.5 20 6M6.5 17.5 4 20M17.5 17.5 20 20"/>',
};

export function icon(name) {
  const span = document.createElement('span');
  span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${ICONS[name]}</svg>`;
  return span.firstElementChild;
}

export async function loadCatalog() {
  const response = await fetch('catalog.json', { cache: 'no-cache' });
  if (!response.ok) throw new Error(`catalog.json returned HTTP ${response.status}`);
  const catalog = await response.json();
  if (catalog.schemaVersion !== 1) throw new Error(`Unsupported catalog schemaVersion ${catalog.schemaVersion}`);
  return catalog;
}

export function plural(count, word) {
  return `${count} ${word}${count === 1 ? '' : 's'}`;
}

export function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  return `${(bytes / 1024).toFixed(bytes < 10240 ? 1 : 0)} KB`;
}

/** True when a script or widget runs on Linux and macOS too. */
export function runsEverywhere(item) {
  return !item.platforms || item.platforms.length === 0 || item.platforms.some((p) => p !== 'Windows');
}

export function isCrossPlatform(pkg) {
  return [...pkg.scripts, ...pkg.widgets].every(runsEverywhere);
}

export function needsAdmin(pkg) {
  return pkg.scripts.some((s) => s.requiresAdmin);
}

/** Package modules plus anything a script or widget needs on top. */
export function allModules(pkg) {
  const modules = new Set(pkg.requiresModules);
  for (const item of [...pkg.scripts, ...pkg.widgets]) for (const m of item.requiresModules || []) modules.add(m);
  return [...modules];
}

export function moduleBadges(pkg) {
  return allModules(pkg).map((m) => el('span', { class: 'badge', title: 'Required PowerShell module' }, m));
}

// ---------- Package lists (home and browse) ----------

export function packageUrl(pkg) {
  return `package.html?id=${encodeURIComponent(pkg.id)}`;
}

/** Two or three characters for the package tile: digits if the id has them (Microsoft365 → 365), else its capitals. */
export function monogram(pkg) {
  const digits = pkg.id.match(/\d+/);
  if (digits) return digits[0].slice(0, 3);
  const caps = pkg.id.replace(/[^A-Z]/g, '');
  return (caps.length >= 2 ? caps : pkg.id).slice(0, 2).toUpperCase();
}

const SHORT_CATEGORIES = { 'Active Directory': 'AD', 'Microsoft 365 / Entra ID': 'M365', 'Service Management': 'ITSM' };
export function shortCategory(category) {
  return SHORT_CATEGORIES[category] || category;
}

export function countsText(pkg) {
  const parts = [plural(pkg.scripts.length, 'script')];
  if (pkg.widgets.length) parts.push(plural(pkg.widgets.length, 'widget'));
  return parts.join(' · ');
}

/** Lower-case text that search terms are matched against. */
export function haystack(pkg) {
  return [
    pkg.id, pkg.name, pkg.description, pkg.category, ...pkg.tags,
    ...pkg.scripts.flatMap((s) => [s.name, s.id.split('/')[1], s.description]),
    ...pkg.widgets.map((w) => w.name),
  ].join(' ').toLowerCase();
}

/** filters: { q, category, platform: ''|'windows'|'cross', admin: ''|'yes'|'no' }. pkg._search comes from haystack(). */
export function matchesFilters(pkg, filters) {
  if (filters.category && pkg.category !== filters.category) return false;
  if (filters.platform === 'windows' && isCrossPlatform(pkg)) return false;
  if (filters.platform === 'cross' && !isCrossPlatform(pkg)) return false;
  if (filters.admin === 'yes' && !needsAdmin(pkg)) return false;
  if (filters.admin === 'no' && needsAdmin(pkg)) return false;
  const terms = (filters.q || '').toLowerCase().split(/\s+/).filter(Boolean);
  return terms.every((term) => pkg._search.includes(term));
}

/** Loads the catalog and returns its packages sorted by name, ready for matchesFilters. */
export async function loadPackages() {
  const catalog = await loadCatalog();
  const packages = catalog.packages
    .map((pkg) => Object.assign(pkg, { _search: haystack(pkg) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return { catalog, packages };
}

/** Categories in catalog order that at least one package uses, with counts. */
export function usedCategories(catalog, packages) {
  const used = new Map();
  for (const pkg of packages) used.set(pkg.category, (used.get(pkg.category) || 0) + 1);
  const order = (catalog.categories || []).filter((c) => used.has(c));
  for (const c of used.keys()) if (!order.includes(c)) order.push(c);
  return order.map((name) => ({ name, count: used.get(name) }));
}

/** "/" focuses the search box, like in OpsKit. */
export function focusOnSlash(input) {
  document.addEventListener('keydown', (event) => {
    if (event.key === '/' && !event.ctrlKey && !event.metaKey && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) {
      event.preventDefault();
      input.focus();
    }
  });
}

export async function copyText(text, button) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const area = el('textarea', { class: 'visually-hidden', readonly: true });
    area.value = text;
    document.body.append(area);
    area.select();
    document.execCommand('copy');
    area.remove();
  }
  if (button) {
    const original = button.dataset.label || button.textContent;
    button.dataset.label = original;
    button.textContent = 'Copied';
    button.classList.add('copied');
    clearTimeout(button._timer);
    button._timer = setTimeout(() => { button.textContent = original; button.classList.remove('copied'); }, 2000);
  }
  announce('Copied to clipboard');
}

export function copyButton(getText, label = 'Copy', what = '') {
  return el('button', {
    type: 'button',
    class: 'copy-button',
    'aria-label': what ? `Copy ${what}` : null,
    onclick: (event) => copyText(typeof getText === 'function' ? getText() : getText, event.currentTarget),
  }, label);
}

initThemeToggle();
