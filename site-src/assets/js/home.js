import { loadCatalog, el, plural, isCrossPlatform, needsAdmin, moduleBadges, announce } from './common.js';

const form = document.getElementById('filters');
const input = document.getElementById('q');
const chipBox = document.getElementById('category-chips');
const platformSelect = document.getElementById('platform');
const adminSelect = document.getElementById('admin');
const resetButton = document.getElementById('reset');
const grid = document.getElementById('grid');
const count = document.getElementById('result-count');

const state = { q: '', category: '', platform: '', admin: '' };
let packages = [];

function readUrl() {
  const params = new URLSearchParams(location.search);
  state.q = params.get('q') || '';
  state.category = params.get('category') || '';
  state.platform = ['windows', 'cross'].includes(params.get('platform')) ? params.get('platform') : '';
  state.admin = ['yes', 'no'].includes(params.get('admin')) ? params.get('admin') : '';
  input.value = state.q;
  platformSelect.value = state.platform;
  adminSelect.value = state.admin;
}

function writeUrl() {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(state)) if (value) params.set(key, value);
  const query = params.toString();
  history.replaceState(null, '', query ? `?${query}` : location.pathname);
}

function haystack(pkg) {
  return [
    pkg.id, pkg.name, pkg.description, pkg.category, ...pkg.tags,
    ...pkg.scripts.flatMap((s) => [s.name, s.id.split('/')[1], s.description]),
    ...pkg.widgets.map((w) => w.name),
  ].join(' ').toLowerCase();
}

function matches(pkg) {
  if (state.category && pkg.category !== state.category) return false;
  if (state.platform === 'windows' && isCrossPlatform(pkg)) return false;
  if (state.platform === 'cross' && !isCrossPlatform(pkg)) return false;
  if (state.admin === 'yes' && !needsAdmin(pkg)) return false;
  if (state.admin === 'no' && needsAdmin(pkg)) return false;
  const terms = state.q.toLowerCase().split(/\s+/).filter(Boolean);
  return terms.every((term) => pkg._search.includes(term));
}

function card(pkg) {
  const badges = [...moduleBadges(pkg)];
  if (needsAdmin(pkg)) badges.push(el('span', { class: 'badge warning', title: 'At least one script needs to run as administrator' }, 'admin'));
  if (!isCrossPlatform(pkg)) badges.push(el('span', { class: 'badge', title: 'Some scripts only run on Windows' }, 'Windows'));

  const counts = [plural(pkg.scripts.length, 'script')];
  if (pkg.widgets.length) counts.push(plural(pkg.widgets.length, 'widget'));

  return el('article', { class: 'card' },
    el('div', {},
      el('h3', {}, el('a', { href: `package.html?id=${encodeURIComponent(pkg.id)}` }, pkg.name)),
      el('div', { class: 'id' }, pkg.id)),
    el('p', { class: 'desc' }, pkg.description),
    el('div', { class: 'meta' },
      el('span', { class: 'badge accent' }, pkg.category),
      el('span', { class: 'mono' }, `v${pkg.version}`),
      el('span', { class: 'sep', 'aria-hidden': 'true' }, '·'),
      el('span', {}, counts.join(' · '))),
    badges.length ? el('div', { class: 'badges' }, badges) : null);
}

function renderChips(catalog) {
  const used = new Map();
  for (const pkg of packages) used.set(pkg.category, (used.get(pkg.category) || 0) + 1);
  const order = (catalog.categories || []).filter((c) => used.has(c));
  for (const c of used.keys()) if (!order.includes(c)) order.push(c);

  const chip = (value, label, n) => el('button', {
    type: 'button',
    class: 'chip',
    'aria-pressed': String(state.category === value),
    dataset: { category: value },
    onclick: () => { state.category = state.category === value && value ? '' : value; update(); },
  }, label, n === undefined ? null : el('span', { class: 'count' }, ` ${n}`));

  chipBox.replaceChildren(chip('', 'All', packages.length), ...order.map((c) => chip(c, c, used.get(c))));
}

function render() {
  for (const button of chipBox.querySelectorAll('.chip')) {
    button.setAttribute('aria-pressed', String(button.dataset.category === state.category));
  }
  const shown = packages.filter(matches);
  grid.setAttribute('aria-busy', 'false');
  if (shown.length) {
    grid.replaceChildren(...shown.map(card));
  } else {
    grid.replaceChildren(el('div', { class: 'empty' },
      el('p', {}, 'No packages match these filters.'),
      el('button', { type: 'button', class: 'button secondary small', onclick: clearFilters }, 'Clear filters')));
  }
  const filtered = Object.values(state).some(Boolean);
  count.textContent = filtered ? `Showing ${shown.length} of ${plural(packages.length, 'package')}` : plural(packages.length, 'package');
  resetButton.hidden = !filtered;
  return shown.length;
}

let announceTimer;
function update() {
  writeUrl();
  const n = render();
  clearTimeout(announceTimer);
  announceTimer = setTimeout(() => announce(`${plural(n, 'package')} found`), 600);
}

function clearFilters() {
  Object.assign(state, { q: '', category: '', platform: '', admin: '' });
  input.value = '';
  platformSelect.value = '';
  adminSelect.value = '';
  update();
  input.focus();
}

let typingTimer;
input.addEventListener('input', () => {
  clearTimeout(typingTimer);
  typingTimer = setTimeout(() => { state.q = input.value.trim(); update(); }, 120);
});
platformSelect.addEventListener('change', () => { state.platform = platformSelect.value; update(); });
adminSelect.addEventListener('change', () => { state.admin = adminSelect.value; update(); });
resetButton.addEventListener('click', clearFilters);
form.addEventListener('submit', (event) => { event.preventDefault(); state.q = input.value.trim(); update(); });
window.addEventListener('popstate', () => { readUrl(); render(); });

// "/" focuses search, like in OpsKit.
document.addEventListener('keydown', (event) => {
  if (event.key === '/' && !event.ctrlKey && !event.metaKey && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) {
    event.preventDefault();
    input.focus();
  }
});

readUrl();
try {
  const catalog = await loadCatalog();
  packages = catalog.packages
    .map((pkg) => Object.assign(pkg, { _search: haystack(pkg) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  renderChips(catalog);
  render();
} catch (error) {
  grid.setAttribute('aria-busy', 'false');
  grid.replaceChildren(el('div', { class: 'empty' },
    el('p', {}, `Couldn't load the catalog (${error.message}).`),
    el('p', {}, el('a', { href: 'catalog.json' }, 'Open catalog.json'))));
  count.textContent = '';
}
