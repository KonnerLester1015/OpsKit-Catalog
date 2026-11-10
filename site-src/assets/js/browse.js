import {
  el, plural, announce, loadPackages, usedCategories, matchesFilters, monogram, countsText, packageUrl, focusOnSlash,
  moduleBadges, isCrossPlatform, needsAdmin,
} from './common.js';

const form = document.getElementById('filters');
const input = document.getElementById('q');
const catBox = document.getElementById('category-list');
const segments = [...document.querySelectorAll('.segmented[data-filter]')];
const resetButton = document.getElementById('reset');
const list = document.getElementById('pkg-list');
const title = document.getElementById('list-title');
const count = document.getElementById('result-count');
const stats = document.getElementById('browse-stats');

const ALLOWED = { platform: ['windows', 'cross'], admin: ['yes', 'no'] };
const state = { q: '', category: '', platform: '', admin: '' };
let packages = [];

function readUrl() {
  const params = new URLSearchParams(location.search);
  state.q = params.get('q') || '';
  state.category = params.get('category') || '';
  for (const key of Object.keys(ALLOWED)) state[key] = ALLOWED[key].includes(params.get(key)) ? params.get(key) : '';
  input.value = state.q;
}

function writeUrl() {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(state)) if (value) params.set(key, value);
  const query = params.toString();
  history.replaceState(null, '', query ? `?${query}` : location.pathname);
}

function row(pkg) {
  const badges = [el('span', { class: 'badge accent' }, pkg.category), ...moduleBadges(pkg)];
  if (!isCrossPlatform(pkg)) badges.push(el('span', { class: 'badge', title: 'Some scripts only run on Windows' }, 'Windows'));
  if (needsAdmin(pkg)) badges.push(el('span', { class: 'badge warning', title: 'At least one script needs to run as administrator' }, 'admin'));

  return el('li', {},
    el('a', { class: 'pkg-row', href: packageUrl(pkg) },
      el('span', { class: 'tile large', 'aria-hidden': 'true' }, monogram(pkg)),
      el('span', { class: 'pkg-row-main' },
        el('span', { class: 'pkg-row-title' },
          el('span', { class: 'pkg-row-name' }, pkg.name),
          el('span', { class: 'pkg-row-id' }, `${pkg.id} · v${pkg.version}`)),
        el('span', { class: 'pkg-row-desc' }, pkg.description),
        el('span', { class: 'badges' }, badges)),
      el('span', { class: 'pkg-row-side' },
        el('span', { class: 'pkg-row-counts' }, countsText(pkg)),
        el('span', { class: 'pkg-row-view', 'aria-hidden': 'true' }, 'View →'))));
}

function renderCategories(catalog) {
  const button = (value, label, n) => el('button', {
    type: 'button',
    class: 'cat-button',
    'aria-pressed': 'false',
    dataset: { category: value },
    onclick: () => { state.category = value; update(); },
  }, el('span', {}, label), el('span', { class: 'count' }, String(n)));

  catBox.replaceChildren(
    button('', 'All packages', packages.length),
    ...usedCategories(catalog, packages).map((c) => button(c.name, c.name, c.count)));
}

function render() {
  for (const b of catBox.querySelectorAll('.cat-button')) b.setAttribute('aria-pressed', String(b.dataset.category === state.category));
  for (const group of segments) {
    for (const b of group.querySelectorAll('button')) b.setAttribute('aria-pressed', String(b.dataset.value === state[group.dataset.filter]));
  }

  const shown = packages.filter((pkg) => matchesFilters(pkg, state));
  list.setAttribute('aria-busy', 'false');
  if (shown.length) {
    list.replaceChildren(...shown.map(row));
  } else {
    list.replaceChildren(el('li', { class: 'empty' },
      el('p', {}, 'No packages match these filters.'),
      el('button', { type: 'button', class: 'button secondary small', onclick: clearFilters }, 'Clear filters')));
  }
  title.textContent = state.category || 'All packages';
  count.textContent = `${shown.length} of ${packages.length} · A–Z`;
  resetButton.hidden = !Object.values(state).some(Boolean);
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
  update();
  input.focus();
}

for (const group of segments) {
  for (const b of group.querySelectorAll('button')) {
    b.addEventListener('click', () => { state[group.dataset.filter] = b.dataset.value; update(); });
  }
}
let typingTimer;
input.addEventListener('input', () => {
  clearTimeout(typingTimer);
  typingTimer = setTimeout(() => { state.q = input.value.trim(); update(); }, 120);
});
form.addEventListener('submit', (event) => { event.preventDefault(); state.q = input.value.trim(); update(); });
resetButton.addEventListener('click', clearFilters);
window.addEventListener('popstate', () => { readUrl(); render(); });
focusOnSlash(input);

readUrl();
try {
  const result = await loadPackages();
  packages = result.packages;
  const scripts = packages.reduce((n, p) => n + p.scripts.length, 0);
  const widgets = packages.reduce((n, p) => n + p.widgets.length, 0);
  stats.textContent = [plural(packages.length, 'package'), plural(scripts, 'script'), plural(widgets, 'widget')].join(' · ');
  renderCategories(result.catalog);
  render();
} catch (error) {
  list.setAttribute('aria-busy', 'false');
  list.replaceChildren(el('li', { class: 'empty' },
    el('p', {}, `Couldn't load the catalog (${error.message}).`),
    el('p', {}, el('a', { href: 'catalog.json' }, 'Open catalog.json'))));
  count.textContent = '';
}
