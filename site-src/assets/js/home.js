import {
  el, plural, announce, copyText, loadPackages, usedCategories, matchesFilters, monogram, countsText, shortCategory, packageUrl, focusOnSlash,
} from './common.js';

// Filter links used to point at the home page. The full filters live on browse.html now.
if (/[?&](q|category|platform|admin)=/.test(location.search)) location.replace(`browse.html${location.search}`);

const LIMIT = 5;
const form = document.getElementById('finder-form');
const input = document.getElementById('q');
const chipBox = document.getElementById('category-chips');
const list = document.getElementById('finder-list');
const more = document.getElementById('finder-more');

const state = { q: '', category: '' };
let packages = [];

function browseHref() {
  const params = new URLSearchParams();
  if (state.q) params.set('q', state.q);
  if (state.category) params.set('category', state.category);
  const query = params.toString();
  return query ? `browse.html?${query}` : 'browse.html';
}

function row(pkg) {
  return el('li', {},
    el('a', { class: 'mini-row', href: packageUrl(pkg) },
      el('span', { class: 'tile', 'aria-hidden': 'true' }, monogram(pkg)),
      el('span', { class: 'mini-text' },
        el('span', { class: 'mini-name' }, pkg.name),
        el('span', { class: 'mini-desc' }, pkg.description)),
      el('span', { class: 'mini-counts' }, countsText(pkg))));
}

function render() {
  for (const button of chipBox.querySelectorAll('.chip')) {
    button.setAttribute('aria-pressed', String(button.dataset.category === state.category));
  }
  const shown = packages.filter((pkg) => matchesFilters(pkg, state));
  list.setAttribute('aria-busy', 'false');
  list.replaceChildren(...(shown.length
    ? shown.slice(0, LIMIT).map(row)
    : [el('li', { class: 'finder-empty' }, 'No packages match.')]));

  const filtered = Boolean(state.q || state.category);
  more.href = browseHref();
  more.firstElementChild.textContent = filtered
    ? `See ${shown.length === 1 ? 'the 1 match' : `all ${shown.length} matches`} in Browse`
    : `Browse all ${plural(packages.length, 'package')}`;
  more.hidden = filtered && shown.length === 0;
  return shown.length;
}

let announceTimer;
function update() {
  const n = render();
  clearTimeout(announceTimer);
  announceTimer = setTimeout(() => announce(`${plural(n, 'package')} found`), 600);
}

function renderChips(catalog) {
  const chip = (value, label, n, fullName) => el('button', {
    type: 'button',
    class: 'chip',
    title: fullName,
    'aria-label': fullName ? `${fullName}, ${n}` : null,
    'aria-pressed': 'false',
    dataset: { category: value },
    onclick: () => { state.category = state.category === value && value ? '' : value; update(); },
  }, label, el('span', { class: 'count', 'aria-hidden': fullName ? 'true' : null }, ` ${n}`));

  chipBox.replaceChildren(
    chip('', 'All', packages.length),
    ...usedCategories(catalog, packages).map((c) => chip(c.name, shortCategory(c.name), c.count, c.name)));
}

let typingTimer;
input.addEventListener('input', () => {
  clearTimeout(typingTimer);
  typingTimer = setTimeout(() => { state.q = input.value.trim(); update(); }, 120);
});
form.addEventListener('submit', (event) => {
  event.preventDefault();
  state.q = input.value.trim();
  location.href = browseHref();
});
focusOnSlash(input);

// Quick start copy button. Copies the commands without the "> " prompts.
const quickCopy = document.getElementById('quickstart-copy');
const quickCode = document.querySelector('.quickstart code');
if (quickCopy && quickCode) {
  quickCopy.hidden = false;
  quickCopy.addEventListener('click', () => {
    const text = [...quickCode.childNodes].filter((n) => !n.classList?.contains('prompt')).map((n) => n.textContent).join('').trim();
    copyText(text, quickCopy);
  });
}

try {
  const result = await loadPackages();
  packages = result.packages;
  state.q = input.value.trim();   // the browser may restore the field on Back
  renderChips(result.catalog);
  render();
} catch (error) {
  list.setAttribute('aria-busy', 'false');
  list.replaceChildren(el('li', { class: 'finder-empty' },
    `Couldn't load the catalog (${error.message}). `, el('a', { href: 'catalog.json' }, 'Open catalog.json')));
}
