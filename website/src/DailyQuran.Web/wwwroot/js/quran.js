// Daily Quran — the surah index and the reader.
(() => {
  'use strict';

  const dq = window.dq;
  const root = document.documentElement;
  const LAST_READ = 'dq-last';
  const DISPLAY = 'dq-display';
  const RESTORE = 'dq-restore';

  const readJson = (text) => {
    try { return JSON.parse(text) ?? null; } catch { return null; }
  };

  // Folds case, accents, apostrophes and hyphens away, so "al baqara",
  // "Al-Baqarah" and "albaqarah" all find the same surah.
  const fold = (text) => text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ًͯ-ٰٟ]/g, '')
    .replace(/[\s'’`\-]/g, '');

  // ===== Surah index =====

  const index = document.querySelector('[data-surah-index]');
  if (index) {
    const input = index.querySelector('[data-surah-search]');
    const items = [...index.querySelectorAll('[data-surah-list] > li')];
    const empty = index.querySelector('[data-empty]');
    const keys = items.map((item) => fold(item.dataset.search || ''));
    const reference = /^\s*(\d{1,3})\s*(?:[:.\s]\s*(\d{1,3}))?\s*$/;

    const filter = () => {
      const query = input.value.trim();
      const match = query.match(reference);
      let shown = 0;
      items.forEach((item, i) => {
        const visible = !query
          || (match ? item.dataset.number === match[1] : keys[i].includes(fold(query)));
        item.hidden = !visible;
        if (visible) shown++;
      });
      if (empty) empty.hidden = shown > 0;
    };
    input?.addEventListener('input', filter);

    input?.form?.addEventListener('submit', (event) => {
      event.preventDefault();
      const match = input.value.match(reference);
      if (match) {
        window.location.href = match[2] ? `/quran/${match[1]}/${match[2]}` : `/quran/${match[1]}`;
        return;
      }
      const first = items.find((item) => !item.hidden);
      if (first) window.location.href = first.querySelector('a').href;
    });

    const last = readJson(dq?.store.get(LAST_READ));
    const card = index.querySelector('[data-continue]');
    if (card && last && Number.isInteger(last.s) && Number.isInteger(last.a) && typeof last.n === 'string') {
      card.href = `/quran/${last.s}/${last.a}`;
      card.querySelector('[data-continue-label]').textContent = `${last.n} ${last.s}:${last.a}`;
      card.hidden = false;
    }
  }

  // ===== Reader =====

  const reader = document.querySelector('[data-reader]');
  if (!reader) return;

  const surah = Number(reader.dataset.surah);
  const surahName = reader.dataset.surahName;
  const hasTranslation = reader.dataset.hasTranslation === 'true';
  const ayat = [...reader.querySelectorAll('.ayah')];

  const scrollToAyah = (number, { highlight = false, behavior = 'smooth' } = {}) => {
    const target = document.getElementById(`a${number}`);
    if (!target) return false;
    target.scrollIntoView({ block: 'start', behavior });
    if (highlight) {
      target.classList.remove('is-fading');
      target.classList.add('is-focused');
      window.setTimeout(() => {
        target.classList.add('is-fading');
        target.classList.remove('is-focused');
      }, 2600);
    }
    return true;
  };

  // --- Opening on an ayah: from the address, or back where the reader was
  //     before changing translation. ---

  const restore = readJson(sessionStorage.getItem(RESTORE));
  sessionStorage.removeItem(RESTORE);
  if (restore && restore.s === surah && restore.a > 1) {
    scrollToAyah(restore.a, { behavior: 'instant' });
  } else if (reader.dataset.focus) {
    requestAnimationFrame(() => scrollToAyah(reader.dataset.focus, { highlight: true, behavior: 'instant' }));
  }

  // --- The ayah being read: the one crossing the upper part of the screen ---

  let current = ayat[0];
  let saveTimer = 0;
  const jumpInput = document.querySelector('[data-ayah-jump] input');

  const remember = () => {
    window.clearTimeout(saveTimer);
    saveTimer = window.setTimeout(() => {
      dq?.store.set(LAST_READ, JSON.stringify({ s: surah, a: Number(current.dataset.ayah), n: surahName }));
    }, 700);
  };

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          current = entry.target;
          if (jumpInput && document.activeElement !== jumpInput) jumpInput.placeholder = `${current.dataset.ayah} of ${ayat.length}`;
          remember();
        }
      });
    }, { rootMargin: '-30% 0px -60% 0px' });
    ayat.forEach((ayah) => observer.observe(ayah));
  }

  // --- A thin gold line under the bar: how far through the surah ---

  const progress = document.querySelector('[data-progress]');
  let ticking = false;
  const drawProgress = () => {
    ticking = false;
    const box = reader.getBoundingClientRect();
    const travel = Math.max(1, box.height - window.innerHeight);
    const done = Math.min(1, Math.max(0, -box.top / travel));
    if (progress) progress.style.transform = `scaleX(${done})`;
  };
  window.addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(drawProgress); }
  }, { passive: true });
  drawProgress();

  // --- Going elsewhere ---

  document.querySelector('[data-surah-jump]')?.addEventListener('change', (event) => {
    window.location.href = `/quran/${event.target.value}`;
  });

  document.querySelector('[data-ayah-jump]')?.addEventListener('submit', (event) => {
    event.preventDefault();
    const number = parseInt(jumpInput.value, 10);
    if (scrollToAyah(number, { highlight: true })) {
      jumpInput.value = '';
      jumpInput.blur();
    }
  });

  // Changing translation reloads the page; come back to the same ayah.
  document.querySelector('form[data-keep-place]')?.addEventListener('dq:before-submit', () => {
    sessionStorage.setItem(RESTORE, JSON.stringify({ s: surah, a: Number(current.dataset.ayah) }));
  });

  // --- Settings that only change how the page looks ---

  const settings = document.querySelector('[data-settings]');
  const display = Object.assign({ scale: 1, script: 'naskh', hideArabic: false, hideTranslation: false }, readJson(dq?.store.get(DISPLAY)));
  const sizeOutput = document.querySelector('[data-size-value]');

  function applyDisplay() {
    display.scale = Math.min(1.6, Math.max(0.8, Math.round(display.scale * 10) / 10));
    if (!hasTranslation) display.hideArabic = false;
    if (display.hideArabic && display.hideTranslation) display.hideTranslation = false;

    root.style.setProperty('--reader-scale', display.scale);
    root.dataset.script = display.script;
    root.toggleAttribute('data-hide-arabic', display.hideArabic);
    root.toggleAttribute('data-hide-translation', display.hideTranslation && hasTranslation);

    if (sizeOutput) sizeOutput.textContent = `${Math.round(display.scale * 100)}%`;
    settings?.querySelectorAll('[data-show]').forEach((button) => {
      const hidden = button.dataset.show === 'arabic' ? display.hideArabic : display.hideTranslation;
      button.setAttribute('aria-pressed', String(!hidden));
    });
    settings?.querySelectorAll('[data-script-set]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.scriptSet === display.script));
    });
    dq?.store.set(DISPLAY, JSON.stringify(display));
  }

  function markTheme() {
    const choice = dq?.store.get('dq-theme') || 'auto';
    settings?.querySelectorAll('[data-theme-set]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.themeSet === choice));
    });
  }

  settings?.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.dataset.size) {
      display.scale += Number(button.dataset.size) * 0.1;
    } else if (button.dataset.show) {
      const key = button.dataset.show === 'arabic' ? 'hideArabic' : 'hideTranslation';
      display[key] = !display[key];
      // Never hide both: turning one off with the other already off swaps them.
      if (display.hideArabic && display.hideTranslation) {
        display[key === 'hideArabic' ? 'hideTranslation' : 'hideArabic'] = false;
      }
    } else if (button.dataset.scriptSet) {
      display.script = button.dataset.scriptSet;
    } else if (button.dataset.themeSet) {
      dq?.setTheme(button.dataset.themeSet);
      return;
    } else {
      return;
    }
    applyDisplay();
  });

  document.addEventListener('dq:theme', markTheme);
  applyDisplay();
  markTheme();

  // Close the settings on a click elsewhere, or Escape.
  document.addEventListener('click', (event) => {
    if (settings?.open && !settings.contains(event.target)) settings.open = false;
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && settings?.open) {
      settings.open = false;
      settings.querySelector('summary')?.focus();
    }
  });

  // --- Copying an ayah, or a link to it ---

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      const copied = document.execCommand('copy');
      area.remove();
      return copied;
    }
  }

  reader.addEventListener('click', async (event) => {
    const button = event.target.closest('[data-copy], [data-share]');
    if (!button) return;
    const ayah = button.closest('.ayah');
    const number = ayah.dataset.ayah;
    const reference = `${surahName} ${surah}:${number}`;
    const url = `${window.location.origin}/quran/${surah}/${number}`;

    if (button.hasAttribute('data-copy')) {
      const arabic = ayah.querySelector('.arabic')?.innerText
        ?? [...ayah.querySelectorAll('.w-ar')].map((word) => word.innerText).join(' ');
      const translation = ayah.querySelector('.translation')?.innerText;
      const text = [arabic, translation, `— ${reference}`].filter(Boolean).join('\n\n');
      if (await copyText(text)) dq?.toast(`${reference} copied`);
      return;
    }

    if (navigator.share && window.matchMedia('(pointer: coarse)').matches) {
      try { await navigator.share({ title: reference, url }); } catch { /* dismissed */ }
      return;
    }
    if (await copyText(url)) dq?.toast('Link copied');
  });
})();
