/* Col website. Everything here is motion and sound on top of a page that reads complete without it: real captures and
   recordings of Col, played as the visitor scrolls and clicks. */

const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const phone = matchMedia('(max-width: 734px)');

/* Sounds, synthesized: a click, a selection, an opening, an answer. Nothing to download, and nothing plays before the
   visitor's first click, as browsers require. The speaker in the bar turns them off, and the choice is remembered. */
const sound = (() => {
  let ctx = null;
  let out = null;
  let enabled = true;
  try { enabled = localStorage.getItem('col-sound') !== 'off'; } catch {}
  const start = () => {
    if (ctx) return ctx;
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return null;
    ctx = new Context();
    const compressor = ctx.createDynamicsCompressor();
    compressor.threshold.value = -18;
    compressor.ratio.value = 4;
    out = ctx.createGain();
    out.gain.value = 0.55;
    out.connect(compressor).connect(ctx.destination);
    return ctx;
  };
  const tone = (frequency, { at = 0, length = 0.12, peak = 0.08, type = 'sine', glide = null, attack = 0.004 } = {}) => {
    const t = ctx.currentTime + at;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(frequency, t);
    if (glide) osc.frequency.exponentialRampToValueAtTime(glide, t + length * 0.8);
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(peak, t + attack);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + length);
    osc.connect(gain).connect(out);
    osc.start(t);
    osc.stop(t + length + 0.02);
  };
  const noise = ({ at = 0, length = 0.02, peak = 0.05, from = 3000, to = null, q = 0.8 } = {}) => {
    const t = ctx.currentTime + at;
    const frames = Math.ceil(ctx.sampleRate * length);
    const buffer = ctx.createBuffer(1, frames, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < frames; i++) data[i] = Math.random() * 2 - 1;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.Q.value = q;
    filter.frequency.setValueAtTime(from, t);
    if (to) filter.frequency.exponentialRampToValueAtTime(to, t + length);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(peak, t + Math.min(0.01, length / 3));
    gain.gain.exponentialRampToValueAtTime(0.0001, t + length);
    source.connect(filter).connect(gain).connect(out);
    source.start(t);
  };
  const voices = {
    // A soft glass tap.
    tick() { noise({ length: 0.018, peak: 0.05, from: 4200, q: 1.2 }); tone(2400, { length: 0.05, peak: 0.035 }); },
    // Two partials, the second a fifth above, falling slightly: a segment being chosen.
    select() { tone(880, { length: 0.11, peak: 0.05, glide: 840 }); tone(1320, { length: 0.09, peak: 0.025, glide: 1260 }); noise({ length: 0.012, peak: 0.03, from: 5000 }); },
    // Air rising, the island opening.
    open() { noise({ length: 0.24, peak: 0.045, from: 500, to: 2600, q: 0.7 }); tone(330, { length: 0.2, peak: 0.04, glide: 660 }); },
    // A bright two-note chime.
    allow() { tone(1318.5, { length: 0.36, peak: 0.06 }); tone(1975.5, { at: 0.075, length: 0.42, peak: 0.055 }); tone(2637, { at: 0.075, length: 0.2, peak: 0.012 }); },
    // Two low notes, falling.
    deny() { tone(392, { length: 0.2, peak: 0.07, type: 'triangle' }); tone(293.7, { at: 0.11, length: 0.26, peak: 0.07, type: 'triangle' }); },
    on() { tone(660, { length: 0.08, peak: 0.05 }); tone(990, { at: 0.06, length: 0.12, peak: 0.05 }); },
  };
  return {
    get enabled() { return enabled; },
    set enabled(value) {
      enabled = value;
      try { localStorage.setItem('col-sound', value ? 'on' : 'off'); } catch {}
    },
    play(name) {
      if (!enabled || !voices[name]) return;
      if (!start()) return;
      if (ctx.state === 'suspended') ctx.resume();
      voices[name]();
    },
  };
})();

// The speaker in the bar, and every element that sounds when clicked.
(() => {
  const toggle = document.querySelector('.nav-sound');
  if (toggle) {
    toggle.setAttribute('aria-pressed', String(sound.enabled));
    toggle.addEventListener('click', () => {
      sound.enabled = !sound.enabled;
      toggle.setAttribute('aria-pressed', String(sound.enabled));
      if (sound.enabled) sound.play('on');
    });
  }
  document.addEventListener('click', (event) => {
    const target = event.target.closest('[data-sound]');
    if (target) sound.play(target.dataset.sound);
  });
})();

// Things rise into place as they come into view.
(() => {
  const items = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) { items.forEach((el) => el.classList.add('in')); return; }
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) { entry.target.classList.add('in'); observer.unobserve(entry.target); }
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
  items.forEach((el) => observer.observe(el));
})();

/* A set of states on a screen, chosen by chips, with a slow tour while it is on screen until a chip is chosen. */
function switcher({ stage, chips, caption = null, interval = 3000, sounds = true }) {
  if (!stage || !chips.length) return null;
  const shots = [...stage.querySelectorAll('.shot[data-state]')];
  const order = chips.map((chip) => chip.dataset.state);
  let current = Math.max(0, chips.findIndex((chip) => chip.getAttribute('aria-pressed') === 'true'));
  let tour = null;
  let chosen = false;
  const show = (index) => {
    current = index;
    const state = order[index];
    shots.forEach((shot) => shot.classList.toggle('on', shot.dataset.state === state));
    chips.forEach((chip, i) => chip.setAttribute('aria-pressed', String(i === index)));
    if (caption) {
      caption.style.opacity = 0;
      setTimeout(() => { caption.textContent = chips[index].dataset.caption; caption.style.opacity = 1; }, 160);
    }
  };
  chips.forEach((chip, i) => chip.addEventListener('click', () => {
    chosen = true;
    clearInterval(tour);
    if (sounds) sound.play(order[i] === 'open' || order[i] === 'ask' ? 'open' : 'select');
    show(i);
  }));
  if (!reduce) {
    new IntersectionObserver(([entry]) => {
      clearInterval(tour);
      if (entry.isIntersecting && !chosen && !document.hidden) tour = setInterval(() => show((current + 1) % order.length), interval);
    }, { threshold: 0.4 }).observe(stage);
    document.addEventListener('visibilitychange', () => { if (document.hidden) clearInterval(tour); });
  }
  show(current);
  return { show };
}

// The hero: the island in every state, in turn.
switcher({
  stage: document.querySelector('[data-tour]'),
  chips: [...document.querySelectorAll('[data-tour-chips] .chip')],
  caption: document.querySelector('[data-tour-caption]'),
  interval: 3400,
});

// The chips of the sections: AirPods, models, glass, sizes.
for (const group of document.querySelectorAll('[data-switch]')) {
  switcher({
    stage: document.querySelector(`[data-switch-stage="${group.dataset.switch}"]`),
    chips: [...group.querySelectorAll('.chip')],
    interval: 2600,
  });
}

// The hero's screen leans back a little as the page scrolls past it.
(() => {
  const lid = document.querySelector('[data-lid-zoom]');
  if (!lid || reduce) return;
  let ticking = false;
  const update = () => {
    ticking = false;
    const rect = lid.getBoundingClientRect();
    const progress = Math.min(1, Math.max(0, -rect.top / (rect.height * 1.4)));
    lid.style.transform = `scale(${1 - progress * 0.06})`;
    lid.style.opacity = String(1 - progress * 0.5);
  };
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
})();

// How it works: the screen stays while the three steps scroll by.
(() => {
  const pin = document.querySelector('[data-pin]');
  if (!pin) return;
  const shots = [...pin.querySelectorAll('.shot[data-state]')];
  const steps = [...pin.querySelectorAll('.pin-step')];
  const dots = [...pin.querySelectorAll('.pin-progress i')];
  let current = -1;
  const show = (index) => {
    if (index === current) return;
    current = index;
    shots.forEach((shot) => shot.classList.toggle('on', Number(shot.dataset.state) === index));
    steps.forEach((step) => step.classList.toggle('now', Number(step.dataset.step) === index));
    dots.forEach((dot, i) => dot.classList.toggle('now', i === index));
  };
  let ticking = false;
  const update = () => {
    ticking = false;
    const rect = pin.getBoundingClientRect();
    const travel = rect.height - innerHeight;
    const progress = travel > 0 ? Math.min(0.999, Math.max(0, -rect.top / travel)) : 0;
    show(Math.floor(progress * steps.length));
  };
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
  addEventListener('resize', update);
  update();
})();

// The films play while they are on screen, and stop when they leave or when asked.
for (const film of document.querySelectorAll('[data-film]')) {
  const video = film.querySelector('video');
  const button = film.querySelector('.film-toggle');
  let paused = reduce;
  const sync = () => {
    film.toggleAttribute('data-paused', paused);
    button.setAttribute('aria-label', paused ? 'Play the film' : 'Pause the film');
  };
  let visible = false;
  const apply = () => {
    if (visible && !paused) { video.preload = 'auto'; video.play().catch(() => {}); } else video.pause();
  };
  button.addEventListener('click', () => { paused = !paused; sync(); apply(); });
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; apply(); }, { threshold: 0.35 }).observe(film);
  sync();
}

// Claude Code asks; the visitor answers from the notch.
(() => {
  const stage = document.querySelector('[data-ask]');
  if (!stage) return;
  const shots = [...stage.querySelectorAll('.shot[data-state]')];
  const toast = stage.querySelector('.toast');
  const label = toast.querySelector('span');
  const state = (name) => shots.forEach((shot) => shot.classList.toggle('on', shot.dataset.state === name));
  let timers = [];
  for (const button of stage.querySelectorAll('[data-answer]')) {
    button.addEventListener('click', () => {
      timers.forEach(clearTimeout);
      const allowed = button.dataset.answer === 'allow';
      sound.play(allowed ? 'allow' : 'deny');
      stage.setAttribute('data-answered', '');
      toast.classList.toggle('deny', !allowed);
      label.textContent = allowed ? 'Allowed. Claude Code pushes the release.' : 'Denied. Claude Code stops and asks you why.';
      toast.classList.add('show');
      timers = [
        setTimeout(() => state(allowed ? 'working' : null), 380),
        setTimeout(() => toast.classList.remove('show'), 2600),
        setTimeout(() => { state('request'); stage.removeAttribute('data-answered'); }, 3400),
      ];
    });
  }
})();

// Setup: the welcome's steps, in turn, or the one chosen.
(() => {
  const deck = document.querySelector('[data-deck]');
  const buttons = [...document.querySelectorAll('[data-deck-steps] button')];
  if (!deck || !buttons.length) return;
  const images = [...deck.querySelectorAll('img')];
  let current = 0;
  let tour = null;
  let chosen = false;
  const show = (index) => {
    current = index;
    images.forEach((img, i) => img.classList.toggle('on', i === index));
    buttons.forEach((button, i) => button.setAttribute('aria-pressed', String(i === index)));
  };
  buttons.forEach((button, i) => button.addEventListener('click', () => { chosen = true; clearInterval(tour); show(i); }));
  if (!reduce) {
    new IntersectionObserver(([entry]) => {
      clearInterval(tour);
      if (entry.isIntersecting && !chosen) tour = setInterval(() => show((current + 1) % images.length), 3600);
    }, { threshold: 0.4 }).observe(deck);
  }
})();

// The terminal types the command; the island answers.
(() => {
  const terminal = document.querySelector('[data-terminal]');
  const stage = document.querySelector('[data-terminal-stage]');
  if (!terminal || !stage) return;
  const typed = terminal.querySelector('[data-type]');
  const shot = stage.querySelector('.shot[data-state]');
  const command = typed.textContent;
  if (reduce) { shot.classList.add('on'); return; }
  let timers = [];
  const run = () => {
    timers.forEach(clearTimeout);
    timers = [];
    typed.textContent = '';
    shot.classList.remove('on');
    let at = 500;
    for (let i = 1; i <= command.length; i++) {
      at += 28 + Math.random() * 46;
      timers.push(setTimeout(() => { typed.textContent = command.slice(0, i); }, at));
    }
    timers.push(setTimeout(() => shot.classList.add('on'), at + 420));
    timers.push(setTimeout(run, at + 5200));
  };
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) run();
    else { timers.forEach(clearTimeout); typed.textContent = command; shot.classList.add('on'); }
  }, { threshold: 0.5 }).observe(terminal);
})();

// Numbers count up once.
(() => {
  if (reduce) return;
  const numbers = document.querySelectorAll('[data-count]');
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      const node = entry.target.firstChild;
      const goal = Number(entry.target.dataset.count);
      const begin = performance.now();
      const step = (now) => {
        const t = Math.min(1, (now - begin) / 1100);
        node.textContent = String(Math.round(goal * (1 - Math.pow(1 - t, 3))));
        if (t < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }
  }, { threshold: 0.6 });
  numbers.forEach((n) => observer.observe(n));
})();

// The MacBook at the end opens as it comes into view.
(() => {
  const mac = document.querySelector('[data-mac]');
  if (!mac) return;
  mac.setAttribute('data-lid', 'scroll');
  if (reduce) { mac.style.setProperty('--lid-angle', 110); return; }
  let ticking = false;
  const update = () => {
    ticking = false;
    const rect = mac.getBoundingClientRect();
    const progress = Math.min(1, Math.max(0, (innerHeight - rect.top) / (innerHeight * 0.75)));
    const eased = 1 - Math.pow(1 - progress, 3);
    mac.style.setProperty('--lid-angle', (8 + eased * 102).toFixed(2));
  };
  addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
  update();
})();

// The bar shows where the page is.
(() => {
  const links = [...document.querySelectorAll('.nav-links a')];
  const sections = links.map((link) => document.querySelector(link.getAttribute('href'))).filter(Boolean);
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      links.forEach((link) => link.setAttribute('aria-current', String(link.getAttribute('href') === `#${entry.target.id}`)));
    }
  }, { rootMargin: '-45% 0px -50% 0px' });
  sections.forEach((section) => observer.observe(section));
})();

/* Scenes: real captures of Col and real pieces of macOS (the arrow cursor, a file's Finder icon, a TextEdit window),
   moved in time like a short film. Each plays while it is on screen; with reduced motion it rests on its last frame. */
(() => {
  // Where things sit, in points of the scene: a wide view on computers, a closer one on phones, so the island stays
  // as large as a phone allows. The notch is at the centre of each view.
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
      a.move(flyer, ...L.flyer); a.style(flyer, { opacity: 0, transform: 'none' });
      a.move(cursor, ...L.cursorStart); a.style(cursor, { opacity: 0 });
      a.at(500, () => a.style(keys, { opacity: 1, transform: 'translate(-50%, 0) scale(1)' }));
      a.at(950, () => keys.classList.add('down'));
      a.at(1200, () => keys.classList.remove('down'));
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
})();

// Ruben's own page counter (ruben-analytics): one anonymous page view, no cookie, no identifier, sent only from the
// published site.
addEventListener('load', () => {
  if (!/^get(col|islet)\.vercel\.app$/.test(location.hostname)) return;
  const endpoint = 'https://ruben-analytics.vercel.app/api/hit';
  const body = JSON.stringify({ site: 'islet', path: location.pathname, ref: document.referrer });
  try { if (!navigator.sendBeacon(endpoint, body)) throw new Error('beacon'); }
  catch { fetch(endpoint, { method: 'POST', body, keepalive: true }).catch(() => {}); }
});
