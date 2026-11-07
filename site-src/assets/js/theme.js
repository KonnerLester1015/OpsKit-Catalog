// Runs in <head> before the page renders, so a saved theme never flashes.
(function () {
  try {
    var saved = localStorage.getItem('opskit-theme');
    if (saved === 'light' || saved === 'dark') document.documentElement.dataset.theme = saved;
  } catch (e) { /* storage blocked: follow the system setting */ }
})();
