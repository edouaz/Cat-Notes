(() => {
  const key = 'opennotes-appearance';
  const modes = ['system', 'light', 'dark'];
  let mode = 'system';

  try {
    const saved = localStorage.getItem(key);
    if (modes.includes(saved)) mode = saved;
  } catch {
    // System appearance remains available when browser storage is blocked.
  }

  function apply(value) {
    mode = modes.includes(value) ? value : 'system';
    if (mode === 'system') delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = mode;
  }

  apply(mode);

  document.addEventListener('DOMContentLoaded', () => {
    const control = document.querySelector('#appearance');
    if (!control) return;
    control.value = mode;
    control.addEventListener('change', () => {
      apply(control.value);
      try {
        localStorage.setItem(key, mode);
      } catch {
        // A manual choice still works for this page without persistent storage.
      }
    });
  });
})();
