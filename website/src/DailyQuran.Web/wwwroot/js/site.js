// Daily Quran — what every page shares: theme, header, menu, reveals, toast.
(() => {
  'use strict';

  const root = document.documentElement;

  // Browser storage can be missing or throw (private windows, blocked site
  // data); the site then simply forgets preferences between visits.
  const store = {
    get(key) {
      try { return window.localStorage.getItem(key); } catch { return null; }
    },
    set(key, value) {
      try {
        if (value === null || value === undefined) window.localStorage.removeItem(key);
        else window.localStorage.setItem(key, value);
      } catch { /* not kept */ }
    },
  };

  // ----- Theme: light, dark, or following the device -----

  const media = window.matchMedia('(prefers-color-scheme: dark)');
  const effectiveTheme = () => root.dataset.theme || (media.matches ? 'dark' : 'light');

  function setTheme(choice) {
    if (choice === 'light' || choice === 'dark') {
      root.dataset.theme = choice;
      store.set('dq-theme', choice);
    } else {
      delete root.dataset.theme;
      store.set('dq-theme', null);
    }
    document.dispatchEvent(new CustomEvent('dq:theme'));
  }

  document.querySelectorAll('[data-theme-toggle]').forEach((button) => {
    button.addEventListener('click', () => setTheme(effectiveTheme() === 'dark' ? 'light' : 'dark'));
  });
  media.addEventListener?.('change', () => document.dispatchEvent(new CustomEvent('dq:theme')));

  // ----- Header: transparent over the green, paper once scrolled -----

  const header = document.querySelector('[data-header]');
  const updateHeader = () => {
    header?.classList.toggle('is-solid', window.scrollY > 24 || header.classList.contains('is-open'));
  };
  window.addEventListener('scroll', updateHeader, { passive: true });
  updateHeader();

  // ----- Menu on small screens -----

  const toggle = document.querySelector('[data-nav-toggle]');
  const setMenu = (open) => {
    toggle?.setAttribute('aria-expanded', String(open));
    header?.classList.toggle('is-open', open);
    updateHeader();
  };
  toggle?.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && header?.classList.contains('is-open')) {
      setMenu(false);
      toggle?.focus();
    }
  });
  header?.querySelectorAll('.site-nav a').forEach((link) => link.addEventListener('click', () => setMenu(false)));

  // ----- Sections ease in as they arrive -----

  const reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -6% 0px' });
    reveals.forEach((element) => observer.observe(element));
  } else {
    reveals.forEach((element) => element.classList.add('is-visible'));
  }

  // ----- Forms that apply themselves when a choice changes -----

  document.querySelectorAll('form[data-autosubmit]').forEach((form) => {
    form.querySelectorAll('select, input[type="checkbox"]').forEach((control) => {
      control.addEventListener('change', () => {
        form.dispatchEvent(new CustomEvent('dq:before-submit'));
        form.submit();
      });
    });
  });

  // ----- A quiet confirmation at the foot of the screen -----

  const toastElement = document.querySelector('[data-toast]');
  let toastTimer = 0;
  function toast(message) {
    if (!toastElement) return;
    toastElement.textContent = message;
    toastElement.classList.add('is-shown');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toastElement.classList.remove('is-shown'), 2200);
  }

  window.dq = { store, setTheme, effectiveTheme, toast };
})();
