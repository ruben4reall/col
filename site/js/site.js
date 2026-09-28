/* Islet website. Plays the real captures of the island in turn on the hero's screen; a chip shows one and stops the
   tour. Everything is readable without this script. */
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  for (const mac of document.querySelectorAll('[data-mac]')) mac.setAttribute('data-lid', 'still');

  const shots = [...document.querySelectorAll('[data-demo] .shot[data-state]')];
  const chips = [...document.querySelectorAll('.demo-chips .chip')];
  const caption = document.querySelector('.demo-caption');
  if (!shots.length || !chips.length) return;

  let index = 0;
  let tour = null;
  const show = (i) => {
    index = i;
    const state = chips[i].dataset.state;
    shots.forEach((shot) => shot.classList.toggle('on', shot.dataset.state === state));
    chips.forEach((chip, j) => chip.setAttribute('aria-pressed', String(j === i)));
    if (caption) caption.textContent = chips[i].dataset.caption;
  };
  const start = () => {
    if (reduce || tour) return;
    tour = setInterval(() => show((index + 1) % chips.length), 3600);
  };
  chips.forEach((chip, i) => chip.addEventListener('click', () => {
    clearInterval(tour);
    tour = -1;
    show(i);
  }));
  // The tour waits for the Mac to be on screen, and pauses while the tab is hidden.
  const observer = new IntersectionObserver(([entry]) => { if (entry.isIntersecting && tour === null) start(); });
  observer.observe(document.querySelector('.hero'));
  document.addEventListener('visibilitychange', () => {
    if (tour === -1) return;
    if (document.hidden) { clearInterval(tour); tour = null; } else start();
  });

})();

/* Scenes: real captures of Islet and real pieces of macOS (the arrow cursor, a file's Finder thumbnail, a TextEdit
   window), moved in time like a short film. Each plays while it is on screen; with reduced motion it rests on its
   last frame. */
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Where things sit, in points of the scene: a wide view on computers, a closer one on phones (see .scene in
  // islet.css), so the island stays as large as a phone allows. The notch is at the centre of each view.
  const phone = matchMedia('(max-width: 734px)');
  const layout = () => (phone.matches ? {
    drop: { file: [130, 400], cursorStart: [210, 480], grab: [142, 400], notch: [310, 70], airdrop: [496, 100] },
    clip: { window: [50, 300], keys: [310, 488], flyer: [55, 399], flyerEnd: [90, 18], cursorStart: [560, 430], notch: [310, 16], row: [190, 58] },
  } : {
    drop: { file: [250, 280], cursorStart: [340, 350], grab: [262, 280], notch: [450, 70], airdrop: [636, 100] },
    clip: { window: [72, 228], keys: [720, 300], flyer: [77, 327], flyerEnd: [230, 18], cursorStart: [640, 330], notch: [450, 16], row: [330, 58] },
  });

  function runner(stage, script, still, place) {
    const shots = [...stage.querySelectorAll('.shot[data-state]')];
    const steps = [...(stage.closest('figure')?.querySelectorAll('[data-step]') ?? [])];
    const timers = [];
    const api = {
      state(name) { shots.forEach((shot) => shot.classList.toggle('on', shot.dataset.state === name)); },
      step(index) { steps.forEach((node) => node.classList.toggle('now', Number(node.dataset.step) === index)); },
      move(el, x, y, ms = 0, ease = 'cubic-bezier(0.45, 0, 0.2, 1)') {
        el.style.transition = ms
          ? `left ${ms}ms ${ease}, top ${ms}ms ${ease}, opacity 0.3s ease, transform ${ms}ms ${ease}`
          : 'opacity 0.3s ease, transform 0.35s ease';
        el.style.setProperty('--x', x);
        el.style.setProperty('--y', y);
      },
      style(el, props) { Object.assign(el.style, props); },
      at(ms, fn) { timers.push(setTimeout(fn, ms)); },
    };
    // Everything in its place for this screen from the start, and again if the screen changes.
    place(api);
    phone.addEventListener('change', () => place(api));
    let playing = false;
    const play = () => {
      if (playing) return;
      playing = true;
      const loop = () => { const length = script(api); api.at(length, loop); };
      loop();
    };
    const stop = () => { playing = false; timers.splice(0).forEach(clearTimeout); };
    if (reduce) { still(api); return; }
    new IntersectionObserver(([entry]) => (entry.isIntersecting ? play() : stop()), { threshold: 0.35 }).observe(stage);
    document.addEventListener('visibilitychange', () => (document.hidden ? stop() : null));
  }

  // Drag a file onto the notch: the island opens, keeps it on the shelf, next to AirDrop.
  const drop = document.querySelector('[data-scene="drop"]');
  if (drop) {
    const file = drop.querySelector('[data-file]');
    const cursor = drop.querySelector('[data-cursor]');
    const place = (a) => { const L = layout().drop; a.move(file, ...L.file); return L; };
    runner(drop, (a) => {
      const L = place(a);
      a.state(null); a.step(0);
      file.classList.remove('dragging');
      a.style(file, { opacity: 1, transform: 'translate(-50%, -50%)' });
      a.move(cursor, ...L.cursorStart); a.style(cursor, { opacity: 0 });
      a.at(300, () => a.style(cursor, { opacity: 1 }));
      a.at(500, () => a.move(cursor, ...L.grab, 800));
      a.at(1500, () => file.classList.add('dragging'));
      a.at(1600, () => { a.move(file, ...L.notch, 1300); a.move(cursor, L.notch[0] + 12, L.notch[1], 1300); });
      a.at(2400, () => a.state('drop'));
      a.at(2950, () => { a.style(file, { opacity: 0, transform: 'translate(-50%, -50%) scale(0.4)' }); a.state('one'); a.step(1); });
      a.at(3700, () => { a.move(cursor, ...L.airdrop, 900); a.step(2); });
      a.at(5900, () => { a.style(cursor, { opacity: 0 }); a.state(null); });
      a.at(6700, () => { file.classList.remove('dragging'); a.move(file, ...L.file); a.style(file, { transform: 'translate(-50%, -50%)' }); });
      a.at(6800, () => a.style(file, { opacity: 1 }));
      return 7600;
    }, (a) => { place(a); a.state('one'); a.style(file, { opacity: 0 }); a.step(1); }, place);
  }

  // Copy a line in TextEdit: it flies into the notch, and waits at the top of the clipboard.
  const clip = document.querySelector('[data-scene="clip"]');
  if (clip) {
    const win = clip.querySelector('.window');
    const keys = clip.querySelector('[data-keys]');
    const flyer = clip.querySelector('[data-flyer]');
    const cursor = clip.querySelector('[data-cursor]');
    const place = (a) => { const L = layout().clip; a.move(win, ...L.window); a.move(keys, ...L.keys); return L; };
    runner(clip, (a) => {
      const L = place(a);
      a.state(null); a.step(0);
      a.style(keys, { opacity: 0, transform: 'translate(-50%, 0) scale(0.8)' });
      // The row lifts off the selected line of TextEdit: 5 points in and 100 down from the window's corner.
      a.move(flyer, ...L.flyer); a.style(flyer, { opacity: 0, transform: 'none' });
      a.move(cursor, ...L.cursorStart); a.style(cursor, { opacity: 0 });
      a.at(500, () => a.style(keys, { opacity: 1, transform: 'translate(-50%, 0) scale(1)' }));
      a.at(950, () => keys.classList.add('down'));
      a.at(1200, () => keys.classList.remove('down'));
      // It lifts off as it appears, so it never sits on top of the text it copies.
      a.at(1250, () => {
        a.move(flyer, ...L.flyerEnd, 950, 'cubic-bezier(0.55, 0, 0.3, 1)');
        a.style(flyer, { opacity: 1, transform: 'scale(0.5)' });
      });
      a.at(2150, () => { a.style(flyer, { opacity: 0 }); a.step(1); });
      a.at(2400, () => a.style(keys, { opacity: 0 }));
      a.at(2600, () => { a.style(cursor, { opacity: 1 }); a.move(cursor, ...L.notch, 900); });
      a.at(3500, () => a.state('clip'));
      a.at(3900, () => { a.move(cursor, ...L.row, 700); a.step(2); });
      a.at(6300, () => { a.style(cursor, { opacity: 0 }); a.state(null); });
      return 7100;
    }, (a) => { place(a); a.state('clip'); a.step(2); }, place);
  }

  // Settings: pages on, then off, with the island following.
  const custom = document.querySelector('[data-toggle-demo]');
  if (custom && !reduce) {
    let timer = null;
    new IntersectionObserver(([entry]) => {
      clearInterval(timer);
      if (entry.isIntersecting) timer = setInterval(() => { custom.dataset.state = custom.dataset.state === 'off' ? 'on' : 'off'; }, 2600);
    }, { threshold: 0.3 }).observe(custom);
  }

  // Sizes and glass: chips, and a slow tour until one is chosen.
  const chipTour = (stage, chips, key, start) => {
    if (!stage || !chips.length) return;
    const order = chips.map((chip) => chip.dataset[key]);
    let current = order.indexOf(start);
    let tour = null;
    const show = (index) => {
      current = index;
      stage.querySelectorAll('.shot[data-state]').forEach((shot) => shot.classList.toggle('on', shot.dataset.state === order[index]));
      chips.forEach((chip, i) => chip.setAttribute('aria-pressed', String(i === index)));
    };
    chips.forEach((chip, i) => chip.addEventListener('click', () => { clearInterval(tour); tour = -1; show(i); }));
    if (!reduce) {
      new IntersectionObserver(([entry]) => {
        if (tour === -1) return;
        clearInterval(tour);
        tour = entry.isIntersecting ? setInterval(() => show((current + 1) % order.length), 2400) : null;
      }, { threshold: 0.4 }).observe(stage);
    }
  };
  chipTour(document.querySelector('.sizes:not(.glass) .size-stage'), [...document.querySelectorAll('.sizes:not(.glass) .size-chips .chip')], 'size', 'standard');
  chipTour(document.querySelector('.glass-stage'), [...document.querySelectorAll('.glass-chips .chip')], 'glass', 'liquid');
  chipTour(document.querySelector('.agent-stage'), [...document.querySelectorAll('.agent-chips .chip')], 'agent', 'claude');

  // Ruben's own page counter (ruben-analytics): one anonymous page view, no cookie, no identifier, sent only from
  // the published site.
  addEventListener('load', () => {
    if (!location.hostname.endsWith('getislet.vercel.app')) return;
    const endpoint = 'https://ruben-analytics.vercel.app/api/hit';
    const body = JSON.stringify({ site: 'islet', path: location.pathname, ref: document.referrer });
    try { if (!navigator.sendBeacon(endpoint, body)) throw new Error('beacon'); }
    catch { fetch(endpoint, { method: 'POST', body, keepalive: true }).catch(() => {}); }
  });
})();
