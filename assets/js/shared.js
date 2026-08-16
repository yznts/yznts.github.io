// theme toggle, persisted via localStorage
(function() {
  const KEY = 'yz-theme';
  const stored = localStorage.getItem(KEY);
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const initial = stored || (prefersDark ? 'dark' : 'light');
  document.documentElement.setAttribute('data-theme', initial);

  function bind() {
    const btn = document.querySelector('[data-theme-toggle]');
    if (!btn) return;
    btn.addEventListener('click', () => {
      const cur = document.documentElement.getAttribute('data-theme');
      const next = cur === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      localStorage.setItem(KEY, next);
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else { bind(); }
})();

// project tag filter
(function() {
  function bind() {
    const bar = document.querySelector('[data-project-filter]');
    const list = document.querySelector('[data-project-list]');
    if (!bar || !list) return;

    const chips = Array.from(bar.querySelectorAll('.filter-chip'));
    const cards = Array.from(list.querySelectorAll('.project-card'));

    function apply(tag) {
      chips.forEach(c => c.classList.toggle('is-active', c.dataset.tag === tag));
      let seen = false;
      cards.forEach(card => {
        const tags = (card.dataset.tags || '').split(',').map(t => t.trim()).filter(Boolean);
        card.hidden = tag !== '' && !tags.includes(tag);
        card.classList.toggle('is-first', !card.hidden && !seen);
        card.classList.toggle('is-not-first', !card.hidden && seen);
        if (!card.hidden) seen = true;
      });
      const url = new URL(window.location);
      if (tag) { url.searchParams.set('tag', tag); }
      else { url.searchParams.delete('tag'); }
      history.replaceState(null, '', url);
    }

    bar.addEventListener('click', e => {
      const chip = e.target.closest('.filter-chip');
      if (chip) apply(chip.dataset.tag);
    });

    list.addEventListener('click', e => {
      const tag = e.target.closest('.tag');
      if (!tag) return;
      apply(tag.dataset.tag);
      bar.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });

    const initial = new URL(window.location).searchParams.get('tag') || '';
    if (initial && chips.some(c => c.dataset.tag === initial)) apply(initial);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else { bind(); }
})();
