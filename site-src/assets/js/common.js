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

// Lucide icon shapes (ISC licence). The parts with a class are animated in site.css, after
// lucide-animated (MIT): the animation plays when the button or link around the icon is hovered.
const ICONS = {
  warning: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><g class="arrow"><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></g>',
  copy: '<rect class="front" width="14" height="14" x="8" y="8" rx="2" ry="2"/><path class="back" d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  'arrow-right': '<path class="shaft" d="M5 12h14"/><path class="head" d="m12 5 7 7-7 7"/>',
};

export function icon(name) {
  const span = document.createElement('span');
  span.innerHTML = `<svg class="ico ico-${name}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${ICONS[name]}</svg>`;
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

/** { PackageId: 'assets/logos/PackageId.svg' } from the build. Missing or broken means no logos. */
async function loadLogos() {
  try {
    const response = await fetch('assets/logos/index.json', { cache: 'no-cache' });
    return response.ok ? await response.json() : {};
  } catch {
    return {};
  }
}

/** Loads the catalog and returns its packages sorted by name, ready for matchesFilters. */
export async function loadPackages() {
  const [catalog, logos] = await Promise.all([loadCatalog(), loadLogos()]);
  const packages = catalog.packages
    .map((pkg) => Object.assign(pkg, { _search: haystack(pkg), _logo: logos[pkg.id] || null }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return { catalog, packages };
}

/** The square tile for a package: its logo if there is one, else its monogram. */
export function packageTile(pkg, large = false) {
  const tile = el('span', { class: large ? 'tile large' : 'tile', 'aria-hidden': 'true' });
  const showMonogram = () => { tile.classList.remove('has-logo'); tile.replaceChildren(monogram(pkg)); };
  if (pkg._logo) {
    tile.classList.add('has-logo');
    tile.append(el('img', { src: pkg._logo, alt: '', loading: 'lazy', decoding: 'async', onerror: showMonogram }));
  } else {
    showMonogram();
  }
  return tile;
}

/** Categories in catalog order that at least one package uses, with counts. */
export function usedCategories(catalog, packages) {
  const used = new Map();
  for (const pkg of packages) used.set(pkg.category, (used.get(pkg.category) || 0) + 1);
  const order = (catalog.categories || []).filter((c) => used.has(c));
  for (const c of used.keys()) if (!order.includes(c)) order.push(c);
  return order.map((name) => ({ name, count: used.get(name) }));
}

/** How long search waits after the last keystroke before it filters. */
export const SEARCH_DELAY = 280;

/** Dims a result list while a search is pending. */
export function markUpdating(list) {
  list.classList.add('is-updating');
}

/** Plays the fade-in on freshly rendered result rows. */
export function playEnter(list) {
  list.classList.remove('is-updating', 'is-entering');
  void list.offsetWidth;   // restart the animation
  list.classList.add('is-entering');
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
    // Copy buttons hold a copy icon, a check icon and a .copy-label; CSS swaps the icons while .copied is set.
    const label = button.querySelector('.copy-label') || button;
    const original = button.dataset.label || label.textContent;
    button.dataset.label = original;
    label.textContent = 'Copied';
    button.classList.add('copied');
    clearTimeout(button._timer);
    button._timer = setTimeout(() => { label.textContent = original; button.classList.remove('copied'); }, 2000);
  }
  announce('Copied to clipboard');
}

export function copyButton(getText, label = 'Copy', what = '') {
  return el('button', {
    type: 'button',
    class: 'copy-button',
    'aria-label': what ? `Copy ${what}` : null,
    onclick: (event) => copyText(typeof getText === 'function' ? getText() : getText, event.currentTarget),
  }, icon('copy'), icon('check'), el('span', { class: 'copy-label' }, label));
}

initThemeToggle();
