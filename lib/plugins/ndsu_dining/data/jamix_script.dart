// The NDSU Dining menu scraper, tested in a browser. To try a change, paste `jamixScript` into a browser console on
// https://usa.jamix.cloud/menu/?anro=99035&k=10 and run e.g. `await wl.menu("2026-10-19")` or
// `await wl.station("2026-10-19", 0, 0, { only: ["Cobb Salad"] })`.
const jamixScript = r'''
// Drives the Jamix (Vaadin) menu page. Injected by jamix_service.dart into a headless web view, and called with
// callAsyncJavaScript. The page has no working JSON API on usa.jamix.cloud, so this clicks through the UI.
window.wl = (() => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function waitFor(test, timeout = 12000) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      try { const v = test(); if (v) return v; } catch (e) {}
      await sleep(80);
    }
    throw new Error('Timed out waiting for the menu page');
  }
  // Icon fonts put glyphs in the Unicode private use area (Residence's product buttons end in one), so drop them.
  const icons = new RegExp('[' + String.fromCharCode(0xE000) + '-' + String.fromCharCode(0xF8FF) + ']', 'g');
  const text = el => (el ? el.textContent : '').replace(icons, '').replace(/\s+/g, ' ').trim();
  const buttons = () => [...document.querySelectorAll('.v-button')];
  const busy = () => document.querySelector('.v-loading-indicator[style*="display: block"]');

  // Most halls split the day into meal tabs. Twisted Taco has one menu, so its stations sit on the home page.
  const groups = () => [...document.querySelectorAll('.v-button-product-list-group')];
  // Only the home page has the day arrows. Every page has a home button, hidden on the home page itself.
  const onHome = () => document.querySelector('.date--next');

  async function home() {
    // The first visit shows a "View menus" button that accepts the terms of use.
    const view = await waitFor(() => buttons().find(b => /View menus/i.test(text(b))) || onHome() ||
      document.querySelector('.navigation--home'));
    if (!onHome()) view.click();
    await waitFor(() => !busy() && onHome());
    // A closed day has no stations, so don't wait long for them.
    try { await waitFor(() => document.querySelector('.v-tabsheet') || groups().length, 3000); } catch (e) {}
  }

  function dateLabel() { return text(document.querySelector('.v-label-sub-caption, .label-sub-caption .v-label')); }

  const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october',
    'november', 'december'];
  // "Monday, October 19, 2026" → days since 1970 (UTC), so dates compare without time zones.
  function dayNumber(label) {
    const m = /([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})/.exec(label);
    if (!m) return null;
    const month = MONTHS.indexOf(m[1].toLowerCase());
    return month < 0 ? null : Date.UTC(+m[3], month, +m[2]) / 86400000;
  }

  // Steps the page's day arrows until it shows `iso` (YYYY-MM-DD). The page remembers the last day shown.
  async function goTo(iso) {
    if (!iso) return;
    const [y, mo, d] = iso.split('-').map(Number);
    const target = Date.UTC(y, mo - 1, d) / 86400000;
    for (let guard = 0; guard < 60; guard++) {
      const now = dayNumber(dateLabel());
      if (now === null) throw new Error('Unreadable date on the menu page');
      if (now === target) return;
      const before = dateLabel();
      const b = document.querySelector(target > now ? '.date--next' : '.date--previous');
      if (!b) throw new Error('No date button');
      b.click();
      await waitFor(() => !busy() && dateLabel() && dateLabel() !== before);
    }
    throw new Error('That day is not on the menu');
  }

  const tabs = () => [...document.querySelectorAll('.v-tabsheet-tabitem')];

  // Tabs scrolled out of view are hidden cells, and a plain click() doesn't select them, so send the mouse events.
  function press(el) {
    ['mousedown', 'mouseup', 'click'].forEach(type =>
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window })));
  }
  // Tabs often start with the same station (Residence's all open with Homestyle), so compare the whole tab.
  const tabContent = () => text(document.querySelector('.v-tabsheet-content'));
  const stationButtons = () => document.querySelector('.v-tabsheet')
    ? [...document.querySelectorAll('.v-tabsheet-content .v-button-product-list-group')] : groups();

  async function openTab(i) {
    if (!tabs().length) return '';
    const t = tabs()[i];
    const cap = text(t);
    if (!t.classList.contains('v-tabsheet-tabitem-selected')) {
      const before = tabContent();
      press(t.querySelector('.v-caption') || t);
      await waitFor(() => !busy() && tabs()[i].classList.contains('v-tabsheet-tabitem-selected'));
      // The content swaps in a moment after the tab is selected.
      try { await waitFor(() => tabContent() !== before, 2500); } catch (e) {}
    }
    await sleep(120);
    return cap;
  }

  function stations() {
    return stationButtons().map(b => {
      const capEl = b.querySelector('.multiline-button-caption-text');
      const capClone = capEl ? capEl.cloneNode(true) : null;
      if (capClone) capClone.querySelectorAll('.mealoption-diets').forEach(e => e.remove());
      return {
        name: text(capClone),
        items: [...b.querySelectorAll('.menu-item')].map(m => ({
          name: text(m.querySelector('.item-name')),
          diets: text(m.querySelector('.menuitem-diets')),
        })).filter(m => m.name),
      };
    });
  }

  // The whole day's menu: every tab, its stations and item names. No nutrition (that takes a click per item).
  async function menu(iso) {
    await home();
    await goTo(iso);
    const out = { date: dateLabel(), menus: [] };
    for (let i = 0; i < Math.max(tabs().length, 1); i++) {
      const name = await openTab(i);
      out.menus.push({ name, stations: stations() });
    }
    return JSON.stringify(out);
  }

  function readLabel() {
    const facts = {};
    document.querySelectorAll('.nv-list li').forEach(li => {
      const s = li.querySelectorAll('span');
      if (s.length >= 2) facts[text(s[0]).replace(/^-\s*/, '')] = text(s[1]);
    });
    const spans = [...document.querySelectorAll('span')].filter(e => !e.children.length);
    const portion = spans.map(text).find(t => /\(\s*[\d.]+\s*g\s*\)/.test(t)) || '';
    return { facts, portion };
  }

  const products = () => buttons().filter(b => b.classList.contains('v-button-product'));
  const nutritionButtons = () => buttons().filter(b => b.classList.contains('nutrition'));
  const nvButton = () => buttons().find(b => /Nutritive values/i.test(text(b)));
  const nameOf = b => text(b.querySelector('.item-name') || b.querySelector('.v-button-caption') || b);
  async function back(ready) {
    document.querySelector('.navigation--previous').click();
    await waitFor(() => !busy() && ready());
  }
  async function label() {
    await waitFor(() => !busy() && document.querySelector('.nv-list li'));
    return readLabel();
  }

  const norm = s => (s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  // Label pages sometimes name an item slightly differently from the menu, so `only` also matches loosely.
  const matches = (name, wanted) => wanted.some(w => {
    const a = norm(name), b = norm(w);
    return a === b || a.includes(b) || b.includes(a);
  });

  // Nutrition for the items at one station: all of them, just `opts.only` (a tap), or all but `opts.skip`
  // (already cached). Setting `wl.abort` stops a `background` read after the current item, so a tap doesn't
  // wait for a whole station; the result then has `aborted: true` and the items read so far. The flag is
  // cleared when a read ends rather than when it starts, so an abort sent just before a read begins still counts.
  // Jamix has two layouts: a station either lists its products (each with its own Ingredients / Nutritive values
  // page), or goes straight to Nutritive values, which shows the station total plus a button per item.
  async function station(iso, tabIndex, stationIndex, opts = {}) {
    const only = opts.only || null, skip = (opts.skip || []).map(norm);
    const want = name => only ? matches(name, only) : !skip.includes(norm(name));
    const stop = () => opts.background && api.abort;
    await home();
    await goTo(iso);
    await openTab(tabIndex);
    const info = stations()[stationIndex];
    const st = stationButtons()[stationIndex];
    if (!st) throw new Error('Station not found');
    st.click();
    await waitFor(() => !busy() && (products().length || nvButton()));
    const items = [];
    let aborted = false;
    if (products().length) {
      let names = products().map(nameOf).filter(want);
      // A tapped name that matches nothing here: read the whole station rather than nothing.
      if (only && !names.length) names = products().map(nameOf);
      for (const name of names) {
        if (stop()) { aborted = true; break; }
        const p = products().find(x => nameOf(x) === name);
        if (!p) continue;
        p.click();
        (await waitFor(() => !busy() && nvButton())).click();
        items.push({ name, ...(await label()) });
        await back(() => nvButton());
        await back(() => products().length);
      }
    } else {
      nvButton().click();
      await waitFor(() => !busy() && (nutritionButtons().length || document.querySelector('.nv-list li')));
      await sleep(150);
      if (nutritionButtons().length) {
        let names = nutritionButtons().map(text).filter(want);
        if (only && !names.length) names = nutritionButtons().map(text);
        for (const name of names) {
          if (stop()) { aborted = true; break; }
          const b = nutritionButtons().find(x => text(x) === name);
          if (!b) continue;
          b.click();
          await waitFor(() => !busy() && document.title === name);
          items.push({ name, ...(await label()) });
          await back(() => nutritionButtons().length);
        }
      } else if (info && info.items.length) {
        items.push({ name: info.items[0].name, ...readLabel() });
      }
    }
    api.abort = false;
    await home();
    return JSON.stringify({ items, aborted });
  }

  const api = { menu, station, abort: false };
  return api;
})();
''';
