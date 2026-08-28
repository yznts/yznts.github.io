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

// downloads: platform detection, version switching, checksum copying
(function() {
  const PLATFORMS = [
    { key: 'macos',   label: 'macOS',   match: /mac|iphone|ipad/i },
    { key: 'windows', label: 'Windows', match: /win/i },
    { key: 'linux',   label: 'Linux',   match: /linux|x11|cros/i },
  ];

  // What to hand someone who just clicks the big button: an installer
  // beats a package, a package beats a bare binary.
  const FORMATS = {
    macos:   ['dmg', 'pkg', 'zip', 'tar.gz', 'binary'],
    windows: ['msi', 'exe', 'zip', 'binary'],
    linux:   ['appimage', 'deb', 'binary', 'tar.gz', 'rpm', 'arch'],
  };

  // Apple Silicon reports the same platform string as Intel, so the arch
  // stays a guess: universal builds cover both, and the full list is
  // always one scroll away.
  function detect() {
    const ua = navigator.userAgent || '';
    const platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
    const haystack = platform + ' ' + ua;
    const found = PLATFORMS.find(p => p.match.test(haystack));
    if (!found) return null;
    const arm = /arm|aarch64/i.test(ua) || (found.key === 'macos' && navigator.maxTouchPoints > 1);
    return { key: found.key, label: found.label, arch: arm ? 'arm64' : 'amd64' };
  }

  function bind() {
    const root = document.querySelector('[data-downloads]');
    if (!root) return;

    const select = root.querySelector('[data-dl-version]');
    const prerelease = root.querySelector('[data-dl-prerelease]');
    const releases = Array.from(root.querySelectorAll('[data-dl-release]'));
    const hero = root.querySelector('[data-dl-hero]');
    const primary = root.querySelector('[data-dl-primary]');
    const primaryLabel = root.querySelector('[data-dl-primary-label]');
    const primaryMeta = root.querySelector('[data-dl-primary-meta]');
    const detected = detect();

    function shown() {
      return releases.find(r => r.dataset.dlRelease === select.value);
    }

    // The primary button follows the platform and the selected version.
    function updatePrimary() {
      if (!detected || !hero) return;
      const release = shown();
      if (!release) return;
      const assets = Array.from(release.querySelectorAll('[data-dl-asset="' + detected.key + '"]'));
      if (!assets.length) { hero.hidden = true; return; }
      // Rank by architecture first, then by how ready to run the format is.
      const formats = FORMATS[detected.key] || [];
      const rank = a => {
        const arch = a.dataset.dlArch;
        const fits = arch === detected.arch || arch === 'universal' ? 0 : 100;
        const format = formats.indexOf(a.dataset.dlFormat);
        return fits + (format === -1 ? formats.length : format);
      };
      const asset = assets.slice().sort((a, b) => rank(a) - rank(b))[0];
      hero.hidden = false;
      primary.href = asset.href;
      primaryLabel.textContent = 'Download for ' + detected.label;
      // The row is a grid now, so the size is a sibling rather than nested.
      const size = asset.parentElement.querySelector('.dl-size');
      primaryMeta.textContent = [asset.dataset.dlFile, size && size.textContent.trim()]
        .filter(Boolean).join(' · ');
    }

    // A project whose every release is still a pre-release (an rc series,
    // say) has nothing to show with them hidden, so the toggle starts on.
    const options = Array.from(select.options);
    const anyStable = options.some(o => o.dataset.prerelease !== 'true');
    if (prerelease && !anyStable) {
      // Unchecking would leave nothing on the page, so the control says
      // what is going on instead of pretending to be a choice.
      prerelease.checked = true;
      prerelease.disabled = true;
      const label = prerelease.closest('.dl-toggle');
      if (label) {
        label.classList.add('is-forced');
        const text = label.querySelector('span');
        if (text) text.textContent = 'Pre-releases only, so far';
      }
    }

    function updateVersions() {
      const withPre = (prerelease && prerelease.checked) || !anyStable;
      Array.from(select.options).forEach(option => {
        option.hidden = option.dataset.prerelease === 'true' && !withPre;
      });
      // Fall back to the newest visible version when the selected one hides.
      const current = select.selectedOptions[0];
      if (current && current.hidden) {
        const next = Array.from(select.options).find(o => !o.hidden);
        if (next) { select.value = next.value; }
      }
      releases.forEach(r => { r.hidden = r.dataset.dlRelease !== select.value; });
      updatePrimary();
    }

    select.addEventListener('change', updateVersions);
    if (prerelease) prerelease.addEventListener('change', updateVersions);

    root.addEventListener('click', e => {
      const copy = e.target.closest('[data-dl-copy]');
      if (!copy) return;
      navigator.clipboard && navigator.clipboard.writeText(copy.dataset.dlCopy);
      const code = copy.querySelector('code');
      if (!code) return;
      const original = code.textContent;
      code.textContent = 'copied';
      setTimeout(() => { code.textContent = original; }, 900);
    });

    updateVersions();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else { bind(); }
})();
