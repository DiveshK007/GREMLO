// The 1.0 website script, ported from docs/design/1.0/web/notchi.html. Waits for GSAP, ScrollTrigger and Lenis
// (loaded by app/(site)/page.tsx), then runs unchanged. Every section still reads with no motion.
(function start(tries) {
  if ((!window.gsap || !window.ScrollTrigger || !window.Lenis) && tries < 100) return setTimeout(function () { start(tries + 1); }, 30);
(() => {
const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
const ROWS = [6,8,8,4,5,8,6,6,6,4,6,4,6,6,4, 4,6,5,4,4,4,4,4,6,6,6,4,4,6, 6,8, 6,6,4,4,6,4,4,4];
const R = { eat:0, walk:1, climb:2, greet:3, celebrate:4, idle:5, sign:6, flag:7, fail:8, hover:9, annoy:10, special:11, evolve:12, wardrobe:13, peek:14,
  turn:15, startstop:16, gaze:17, sit:18, edgepeek:19, yawn:20, grabbed:21, thrown:22, land:23, social:24, tools:25, night:26, focus:27, hold:28, wardrobe2:29, hatch:30,
  chase:31, gulp:32, covereyes:33, tangled:34, backflip:35, juggle:36, moonwalk:37, wrist:38 };
/* props.png: 256x128, 1px per unit. [x, y, w, h] */
const PROP = { bug:[8,22,15,10], squash:[136,26,15,6], paw:[108,121,7,7],
  'd-wrench':[203,23,9,9], 'd-flask':[235,23,9,9], 'd-bug':[11,55,9,9], 'd-star':[43,55,9,9], 'd-moon':[75,55,9,9], 'd-heart':[107,56,9,8], 'd-check':[139,56,9,8], 'd-merge':[171,55,9,9],
  rug:[67,89,26,7], lamp:[106,80,11,16], plant:[137,82,13,14], shelf:[168,80,16,16], beanbag:[200,86,16,10], poster:[234,83,12,13], fishbowl:[9,117,13,11], lights:[32,121,31,7], records:[73,116,14,12] };
function propStyle(el, id, z) { const [x, y, w, h] = PROP[id]; Object.assign(el.style, { width: w * z + 'px', height: h * z + 'px', backgroundSize: 256 * z + 'px ' + 128 * z + 'px', backgroundPosition: (-x * z) + 'px ' + (-y * z) + 'px' }); return el; }
const SPECIES = [
  { id:'notchi', name:'Notchi', kind:'bean', c:'#FF5A3C', voice:'on it.', unlock:'Starter', move:'Big stretch after a long run', head:[[96,33],[96,33],[96,33],[96,33]], u:7, plate:26 },
  { id:'pip', name:'Pip', kind:'bird', c:'#FFC93C', voice:'tests passed!', unlock:'Starter', move:'Chirps when tests pass', head:[[96,54],[96,54],[96,54],[96,54]], u:7, plate:47 },
  { id:'moss', name:'Moss', kind:'sprout', c:'#8FD14F', voice:'slow and steady.', unlock:'Starter', move:'Blooms every tenth meal', head:[[96,54],[96,54],[96,54],[96,54]], u:7, plate:47 },
  { id:'gloop', name:'Gloop', kind:'slime', c:'#2ED3B7', voice:'mhm. still here.', unlock:'A session over an hour', move:'Splits in two on a clean run', head:[[96,110],[96,110],[96,110],[96,110]], u:6, plate:104 },
  { id:'byte', name:'Byte', kind:'robot', c:'#4CC9FF', voice:'EXEC OK.', unlock:'1,000 tool calls watched', move:'Glitches when tests fail', head:[[96,61],[96,61],[96,61],[96,61]], u:7, plate:54 },
  { id:'puff', name:'Puff', kind:'cloud', c:'#8FA8FF', voice:'it rained a bit. that’s ok.', unlock:'Your agent’s first failed run', move:'Rains on a failure', head:[[96,68],[96,68],[96,68],[96,68]], u:6, plate:62 },
  { id:'wisp', name:'Wisp', kind:'flame', c:'#B48CFF', voice:'the build burns bright.', unlock:'Any pet thriving 7 days', move:'Flares on a good meal', head:[[96,26],[96,26],[96,26],[96,26]], u:7, plate:26 },
  { id:'tako', name:'Tako', kind:'octopus', c:'#FF7AB6', voice:'boop. again?', unlock:'Secret. Poke a pet to a stomp, 50 times', move:'Squirts ink on the fifth click', head:[[96,68],[96,61],[96,68],[96,68]], u:7, plate:61 }
];
const SP = Object.fromEntries(SPECIES.map(s => [s.id, s]));
const ACC = ['beanie','crown','headphones','party','wizard','glasses','bow','flower','scarf','shades','cap','star'];

/* ------------------------------------------------ sprite renderer ---- */
const PETS = [];
class Pet {
  constructor(cv, sp, scale) { this.cv = cv; this.ctx = cv.getContext('2d'); this.sp = SP[sp]; this.scale = scale; this.acc = []; this.size(); this.play(R.idle, { frames:[0,1,2,3], fps:2.4 }); PETS.push(this); }
  size() { const d = Math.min(2, window.devicePixelRatio || 1); this.d = d; this.cv.width = Math.round(192 * this.scale * d); this.cv.height = Math.round(208 * this.scale * d); this.cv.style.width = (192 * this.scale) + 'px'; this.cv.style.height = (208 * this.scale) + 'px'; this.last = null; }
  setSpecies(id) { this.sp = SP[id]; this.last = null; }
  play(row, o = {}) { this.row = row; this.frames = o.frames || [...Array(ROWS[row]).keys()]; this.fps = o.fps || 8; this.loop = o.loop !== false; this.t0 = performance.now(); this.onend = o.onend || null; this.fixed = null; this.last = null; return this; }
  show(row, f) { this.row = row; this.fixed = f; this.onend = null; return this; }
  tick(now) {
    let f;
    if (this.fixed != null) f = this.fixed;
    else {
      let i = RM ? 0 : Math.floor((now - this.t0) / 1000 * this.fps);
      if (!this.loop && i >= this.frames.length) { i = this.frames.length - 1; if (this.onend) { const cb = this.onend; this.onend = null; cb(); } }
      f = this.frames[i % this.frames.length];
    }
    const key = this.sp.id + this.row + '.' + f + this.acc.join();
    if (key === this.last) return; this.last = key; this.draw(f);
  }
  draw(f) {
    const c = this.ctx, k = this.scale * this.d;
    c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, this.cv.width, this.cv.height); c.imageSmoothingEnabled = false;
    const img = IMG[this.sp.id]; if (!img) return;
    c.drawImage(img, f * 192, this.row * 208, 192, 208, 0, 0, 192 * k, 208 * k);
    if (this.acc.length && this.row === R.idle && f < 4) {
      const a = ACCIMG[this.sp.id]; const [hx, hy] = this.sp.head[f]; const u = this.sp.u;
      const order = ['scarf','glasses','shades','beanie','crown','headphones','party','wizard','bow','flower','cap','star'];
      for (const name of order) if (this.acc.includes(name)) {
        const i = ACC.indexOf(name);
        c.drawImage(a, i * 40, 0, 40, 40, (hx - 20 * u) * k, (hy - 12 * u) * k, 40 * u * k, 40 * u * k);
      }
    }
  }
}
const IMG = {}, ACCIMG = {}, KIT = {};
/* haptics: Android browsers only (iPhone Safari has no vibration API). Same names as the app's vocabulary. */
const HAPT = { tick: 8, snap: 16, boop: 12, knock: [14, 106, 12], thud: [22, 30, 10], stomp: [18, 52, 18, 52, 18], hatch: [8, 142, 8, 142, 8, 292, 30] };
let lastBuzz = 0;
function buzz(name) { if (RM || !navigator.vibrate) return; const now = performance.now(); if (now - lastBuzz < 100) return; lastBuzz = now; try { navigator.vibrate(HAPT[name]); } catch (e) {} }
function load(src) { return new Promise(res => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; }); }
function tickAll(now) { for (const p of PETS) p.tick(now); }

/* ------------------------------------------------ the notch ---------- */
const NOTCHES = [];
function makeNotch(host, eyesScale) {
  const n = document.getElementById('notchTpl').content.firstElementChild.cloneNode(true);
  host.appendChild(n);
  const pets = [];
  n.querySelectorAll('[data-eyes]').forEach(h => { const cv = document.createElement('canvas'); h.appendChild(cv); pets.push(new Pet(cv, 'notchi', eyesScale).play(R.peek, { fps: 2 })); });
  const sh = n.querySelector('[data-sleep]'); const scv = document.createElement('canvas'); sh.appendChild(scv); pets.push(new Pet(scv, 'notchi', eyesScale).show(R.peek, 2));
  const eh = n.querySelector('[data-egg]'); const ecv = document.createElement('canvas'); eh.appendChild(ecv); const egg = new Pet(ecv, 'moss', .14).play(R.hatch, { frames:[0,1,0,2], fps: 4 });
  const rh = n.querySelector('[data-room]'); const rcv = document.createElement('canvas'); rh.appendChild(rcv); pets.push(new Pet(rcv, 'notchi', .55).play(R.sit, { fps: 3 }));
  const obj = { el: n, pets, egg, state: 'rest' };
  NOTCHES.push(obj);
  return obj;
}
function setNotch(o, s) {
  if (o.state === s) return; o.state = s; o.el.dataset.state = s;
  if (s === 'knock' && !RM) { o.el.classList.remove('shake'); void o.el.offsetWidth; o.el.classList.add('shake'); buzz('knock'); }
}
function setNotchPet(id) { for (const o of NOTCHES) o.pets.forEach(p => p.setSpecies(id)); }

/* ------------------------------------------------ confetti ----------- */
function confetti(x, y, n = 46) {
  if (RM || !window.gsap) return;
  const cols = [getComputedStyle(document.body).getPropertyValue('--accent').trim(), '#F4F2ED', '#FFC93C', '#4CC9FF', '#FF7AB6'];
  for (let i = 0; i < n; i++) {
    const d = document.createElement('i'); d.className = 'confetti'; d.style.left = x + 'px'; d.style.top = y + 'px'; d.style.background = cols[i % cols.length];
    document.body.appendChild(d);
    const vx = (Math.random() - .5) * 520, up = 80 + Math.random() * 160, dur = 1.4 + Math.random() * .9;
    gsap.timeline({ onComplete: () => d.remove() })
      .to(d, { x: vx * .6, y: -up * .4, rotation: Math.random() * 360, duration: .35, ease: 'power2.out' })
      .to(d, { x: vx, y: 300 + Math.random() * 260, rotation: '+=' + (Math.random() * 720 - 360), opacity: 0, duration: dur, ease: 'power1.in' });
  }
}

/* ------------------------------------------------ init --------------- */
async function init() {
  await Promise.all(SPECIES.map(async s => {
    IMG[s.id] = await load('/site/sprites/' + s.id + '.webp');
    ACCIMG[s.id] = await load('/site/sprites/' + s.id + '-acc.png');
    KIT[s.id] = '/site/sprites/' + s.id + '-kit.png';
  }));

  const hasGsap = !!(window.gsap && window.ScrollTrigger);
  if (hasGsap) gsap.registerPlugin(ScrollTrigger);

  /* smooth scroll */
  let lenis = null;
  if (!RM && window.Lenis && hasGsap) {
    lenis = new Lenis({ lerp: 0.09, wheelMultiplier: 1, smoothWheel: true });
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add(t => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
    document.querySelectorAll('a[href^="#"]').forEach(a => a.addEventListener('click', e => {
      const id = a.getAttribute('href'); const t = id === '#top' ? 0 : document.querySelector(id);
      if (t !== null) { e.preventDefault(); lenis.scrollTo(t, { offset: -40, duration: 1.4 }); }
    }));
  }
  const loop = now => { tickAll(now); heroStep(now); marqueeStep(now); parkStep(now); requestAnimationFrame(loop); };

  /* notches */
  const top = makeNotch(document.getElementById('topNotch'), .19);
  const big = makeNotch(document.getElementById('bigNotchWrap'), .19);
  setNotch(top, 'rest');
  const screen = document.getElementById('screen');
  const fitBig = () => { const w = screen.clientWidth; screen.style.setProperty('--sz', Math.min(1, (w - 24) / 680).toFixed(3)); };
  fitBig(); addEventListener('resize', fitBig);

  /* hero title */
  if (hasGsap && !RM) gsap.from('.hero h1 .ln > span', { yPercent: 105, duration: 1, ease: 'power4.out', stagger: .09, delay: .15 });

  /* hero pet */
  heroInit(top);

  /* marquee */
  marqueeInit();

  /* section accents + top notch director */
  const accentTo = c => document.body.style.setProperty('--accent', c);
  const directors = [];
  const reDirect = () => { const t = directors.find(d => d.isActive); if (t) setNotch(top, t.trigger.dataset.notch); };

  /* ---------- Notch Live scrub ---------- */
  const steps = [...document.querySelectorAll('#steps li')];
  const order = ['rest','think','peek','live','knock','done','room','sleep'];
  const cuts = [0, .08, .2, .32, .56, .7, .82, .93, 1.01];
  const tools = [['Read','src/vault.ts'],['Grep','"withdraw("'],['Edit','src/vault.ts · +14 −3'],['Bash','forge test --match-contract Vault']];
  const termL = document.getElementById('termLines');
  const termText = ['⏺ <b>Read</b> src/vault.ts', '⏺ <b>Grep</b> "withdraw("', '⏺ <b>Edit</b> src/vault.ts <span class="ac">+14 −3</span>', '⏺ <b>Bash</b> forge test --match-contract Vault', '  <span class="ac">needs your approval…</span>', '✓ 12 passed · done in 4m 12s'];
  let lastTerm = -1, burstDone = false;
  const liveUpdate = p => {
    let i = 0; while (i < order.length - 1 && p >= cuts[i + 1]) i++;
    const s = order[i];
    setNotch(big, s); if (s !== 'rest') { top.lock = true; setNotch(top, ['live','knock','done','room'].includes(s) ? 'peek' : s); }
    steps.forEach((li, k) => li.classList.toggle('on', k === i));
    const lp = Math.max(0, Math.min(.999, (p - cuts[3]) / (cuts[4] - cuts[3])));
    const ti = Math.floor(lp * tools.length);
    big.el.querySelector('[data-tool]').textContent = tools[ti][0];
    big.el.querySelector('[data-sub]').textContent = tools[ti][1];
    big.el.querySelector('[data-chips]').innerHTML = tools.slice(0, ti + 1).map((t, k) => '<span class="' + (k === ti ? 'on' : '') + '">' + t[0] + '</span>').join('');
    const secs = Math.round(12 + p * 240); big.el.querySelector('[data-tm]').textContent = Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0');
    const tl = p < cuts[3] ? 0 : p < cuts[4] ? 1 + ti : p < cuts[5] ? 5 : 6;
    if (tl !== lastTerm) { lastTerm = tl; termL.innerHTML = termText.slice(0, tl).map(t => '<div>' + t + '</div>').join(''); }
    if (s === 'done' && !burstDone) { burstDone = true; const r = big.el.getBoundingClientRect(); confetti(r.left + r.width / 2, r.bottom - 10); }
    if (s !== 'done') burstDone = false;
  };
  liveUpdate(0);
  if (hasGsap) ScrollTrigger.create({ trigger: '#liveScene', start: 'top top', end: '+=320%', pin: true, scrub: true, onUpdate: self => liveUpdate(self.progress), onLeave: () => { top.lock = false; reDirect(); }, onLeaveBack: () => { top.lock = false; reDirect(); } });

  /* ---------- Hatch scrub ---------- */
  const eggPet = new Pet(document.getElementById('eggCv'), 'moss', 1.45).show(R.hatch, 0);
  const caps = document.getElementById('caps'), capEls = [...caps.querySelectorAll('.cp')];
  const callsEl = document.getElementById('calls'), cracks = [...document.querySelectorAll('#cracks i')], glow = document.getElementById('glow');
  let hatched = false;
  const hatchUpdate = p => {
    const calls = Math.round(Math.min(1, p / .8) * 50);
    callsEl.textContent = calls;
    top.el.querySelector('[data-eggn]').textContent = calls;
    let f, ci;
    if (p < .12) { f = 0; ci = 0; }
    else if (p < .32) { f = 1 + (Math.floor(p * 60) % 2); ci = 1; }
    else if (p < .48) { f = 3; ci = 2; }
    else if (p < .64) { f = 4; ci = 3; }
    else if (p < .8) { f = 5; ci = 4; }
    else if (p < .88) { f = 6; ci = 5; }
    else { f = 7; ci = 5; }
    eggPet.show(R.hatch, f);
    const drop = Math.max(0, 1 - p / .1);
    eggPet.cv.style.transform = 'translateY(' + (-drop * 160).toFixed(1) + 'px) rotate(' + (f === 1 ? -4 : f === 2 ? 4 : 0) + 'deg)';
    caps.classList.toggle('started', ci > 0);
    capEls.forEach((c, k) => c.classList.toggle('on', k === ci));
    cracks.forEach((c, k) => c.classList.toggle('on', calls >= [12, 25, 50][k]));
    glow.style.setProperty('--g', (.08 + Math.min(1, p / .8) * .5 + (f >= 5 ? .2 : 0)).toFixed(2));
    if (f >= 6 && !hatched) { hatched = true; buzz('hatch'); const r = eggPet.cv.getBoundingClientRect(); confetti(r.left + r.width / 2, r.top + r.height * .4, 60); }
    if (f < 6) hatched = false;
  };
  hatchUpdate(0);
  if (hasGsap) ScrollTrigger.create({ trigger: '#hatchScene', start: 'top top', end: '+=360%', pin: true, scrub: true, onUpdate: self => hatchUpdate(self.progress) });

  /* ---------- certificate ---------- */
  const certPet = new Pet(document.getElementById('certCv'), 'notchi', .75).show(R.evolve, 3);
  const starters = ['notchi', 'pip', 'moss']; let starter = 'notchi';
  const stBox = document.getElementById('starter');
  starters.forEach(id => { const b = document.createElement('button'); b.type = 'button'; b.textContent = SP[id].name; b.setAttribute('aria-pressed', id === starter); b.onclick = () => { starter = id; [...stBox.children].forEach(x => x.setAttribute('aria-pressed', x === b)); certPet.setSpecies(id); document.getElementById('certSp').textContent = SP[id].name; accentTo(SP[id].c); }; stBox.appendChild(b); });
  const nameIn = document.getElementById('petName');
  const syncName = () => { const v = nameIn.value.trim() || 'Mochi'; document.getElementById('certName').textContent = v; document.querySelector('.nl-room .room-cap').textContent = v + '’s room'; document.querySelectorAll('.nl-done .em b').forEach(b => b.textContent = v + ' earned 0.03'); document.getElementById('roomName').textContent = v + '’s room'; };
  nameIn.addEventListener('input', syncName);
  const now = new Date();
  document.getElementById('certDate').textContent = now.toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' }) + ' · ' + now.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  setInterval(() => certPet.show(R.evolve, certPet.fixed === 3 ? 4 : 3), 1600);

  /* ---------- eggs + growth ---------- */
  const eggsBox = document.getElementById('eggs');
  SPECIES.forEach(s => { const d = document.createElement('div'); d.className = 'egg'; const cv = document.createElement('canvas'); d.appendChild(cv); d.insertAdjacentHTML('beforeend', '<b>' + s.name + '</b><small>' + s.unlock + '</small>'); eggsBox.appendChild(d); const p = new Pet(cv, s.id, .42).show(R.hatch, 0); d.addEventListener('mouseenter', () => p.play(R.hatch, { frames: [1, 2, 1, 2, 0], fps: 8, loop: false })); });
  const gs = document.querySelectorAll('#grow canvas');
  new Pet(gs[0], 'notchi', .55).play(R.hatch, { frames: [0, 1, 0, 2], fps: 3 });
  new Pet(gs[1], 'notchi', .55).play(R.evolve, { frames: [3, 4], fps: 1.5 });
  new Pet(gs[2], 'notchi', .55);
  new Pet(gs[3], 'notchi', .55).show(R.evolve, 5);
  if (hasGsap) gsap.fromTo('#mealsBar', { scaleX: .12 }, { scaleX: 1, ease: 'none', scrollTrigger: { trigger: '#grow', start: 'top 85%', end: 'bottom 60%', scrub: true } });

  /* ---------- pets rail ---------- */
  const rail = document.getElementById('rail');
  const railPets = [];
  SPECIES.forEach((s, i) => {
    const c = document.createElement('article'); c.className = 'card'; c.style.setProperty('--c', s.c);
    c.innerHTML = '<div class="bg"></div><div class="stage"></div><div class="kind">' + s.kind + ' · ' + String(i + 1).padStart(2, '0') + '</div><h3 class="dsp">' + s.name + '</h3><q>' + s.voice + '</q><div class="un"><b style="color: var(--paper)">' + s.move + '.</b><br>Unlock: ' + s.unlock + '</div>';
    const cv = document.createElement('canvas'); c.querySelector('.stage').appendChild(cv); rail.appendChild(c);
    const p = new Pet(cv, s.id, 1.15).play(R.special, { fps: 4 });
    c.addEventListener('mouseenter', () => p.play(R.hover, { fps: 4 }));
    c.addEventListener('mouseleave', () => p.play(R.special, { fps: 4 }));
    c.addEventListener('click', () => p.play(R.celebrate, { fps: 10, loop: false, onend: () => p.play(R.special, { fps: 4 }) }));
    railPets.push(p);
  });
  const railIdx = document.getElementById('railIdx');
  if (hasGsap) {
    const dist = () => Math.max(0, rail.scrollWidth - innerWidth + 40);
    gsap.to(rail, { x: () => -dist(), ease: 'none', scrollTrigger: { trigger: '#railScene', start: 'top top', end: () => '+=' + dist(), pin: true, scrub: true, invalidateOnRefresh: true,
      onUpdate: self => { const i = Math.min(7, Math.round(self.progress * 7)); railIdx.textContent = String(i + 1).padStart(2, '0') + ' / 08'; accentTo(SPECIES[i].c); setNotchPet(SPECIES[i].id); },
      onLeave: () => setNotchPet('notchi'), onLeaveBack: () => setNotchPet('notchi') } });
  }

  /* ---------- closet ---------- */
  closetInit(accentTo);

  /* ---------- room + dreams ---------- */
  roomInit();

  /* ---------- park ---------- */
  parkInit();

  /* ---------- money parade ---------- */
  const lines = [['notchi','Ship faster with Acme CI'],['pip','Tests in three seconds'],['byte','Logs you can read'],['tako','Ship it'],['moss','Deploys on push'],['puff','Fewer flaky tests'],['wisp','Docs that keep up'],['gloop','Errors, explained']];
  const prow = document.getElementById('paradeRow');
  lines.concat(lines).forEach(([id, t]) => {
    const s = SP[id]; const h = document.createElement('span'); h.className = 'held'; const sc = .5714;
    const cv = document.createElement('canvas'); h.appendChild(cv);
    const sg = document.createElement('span'); sg.className = 'sign'; sg.style.setProperty('--k', '4px'); sg.style.borderImageSource = 'url(' + KIT[id] + ')'; sg.style.top = Math.round(s.plate * sc) + 'px';
    sg.innerHTML = t + '<span class="ad">AD</span>'; h.appendChild(sg); prow.appendChild(h);
    new Pet(cv, id, sc).play(R.hold, { fps: 4.5 });
  });
  if (hasGsap) gsap.fromTo(prow, { x: 0 }, { x: () => -(prow.scrollWidth / 2), ease: 'none', scrollTrigger: { trigger: '#money', start: 'top bottom', end: 'bottom top', scrub: .6, invalidateOnRefresh: true } });

  /* ---------- words ---------- */
  const words = document.getElementById('words');
  const hl = ['never', 'ducks', 'open', 'source,'];
  words.innerHTML = words.textContent.trim().split(/\s+/).map(w => '<span class="w' + (hl.includes(w) ? ' hl' : '') + '">' + w + '</span>').join(' ');
  if (hasGsap) {
    const ws = words.querySelectorAll('.w');
    gsap.to(ws, { opacity: 1, ease: 'none', stagger: .1, scrollTrigger: { trigger: words, start: 'top 80%', end: 'bottom 45%', scrub: true } });
  } else words.querySelectorAll('.w').forEach(w => w.style.opacity = 1);

  /* ---------- end ---------- */
  new Pet(document.getElementById('endCv'), 'notchi', .9).play(R.hatch, { frames: [0, 0, 1, 2, 0], fps: 3 });
  if (hasGsap) {
    // created last, so their positions include every pinned scene above them
    document.querySelectorAll('section[data-accent]').forEach(s => ScrollTrigger.create({ trigger: s, start: 'top 55%', end: 'bottom 55%', onToggle: self => { if (self.isActive) accentTo(s.dataset.accent); } }));
    document.querySelectorAll('section[data-notch]').forEach(s => directors.push(ScrollTrigger.create({ trigger: s, start: 'top 50%', end: 'bottom 50%', onToggle: self => { if (self.isActive && !top.lock) setNotch(top, s.dataset.notch); } })));
  }

  requestAnimationFrame(loop);
  if (hasGsap) { addEventListener('load', () => ScrollTrigger.refresh()); setTimeout(() => ScrollTrigger.refresh(), 600); }
}

/* ------------------------------------------------ hero playground ---- */
let H = null;
function heroInit(topNotch) {
  const yard = document.getElementById('yard'), hp = document.getElementById('hp'), cv = document.getElementById('heroCv'), bub = document.getElementById('bub');
  const sc = innerWidth < 600 ? .62 : .8;
  const pet = new Pet(cv, 'notchi', sc);
  const W = () => yard.clientWidth, PW = 192 * sc;
  H = { yard, hp, cv, bub, pet, sc, W, PW, x: Math.min(W() * .5, W() - PW), y: RM ? 0 : yard.clientHeight + 120, vx: 0, vy: 0, mode: RM ? 'idle' : 'fall', dir: 1, bounces: 0, peak: 0, clicks: 0, lastClick: 0, until: 0, last: performance.now(), mx: -1e4, my: -1e4, top: topNotch };
  const drop = () => { if (H.mode !== 'wait') return; H.mode = 'fall'; H.hp.style.visibility = ''; setNotch(topNotch, 'door'); pet.play(R.thrown, { fps: 12 }); setTimeout(() => setNotch(topNotch, 'peek'), 1400); };
  if (!RM) {
    H.mode = 'wait'; hp.style.visibility = 'hidden';
    const io = new IntersectionObserver(es => { if (es[0].isIntersecting) { io.disconnect(); setTimeout(drop, 350); } }, { threshold: .55 });
    io.observe(yard);
  } else pet.play(R.idle, { frames: [0, 1, 2, 3], fps: 2.4 });

  let down = null, samples = [];
  hp.addEventListener('pointerdown', e => {
    hp.setPointerCapture(e.pointerId);
    down = { t: performance.now(), x: e.clientX, y: e.clientY, moved: false };
    samples = [{ t: performance.now(), x: e.clientX, y: e.clientY }];
  });
  hp.addEventListener('pointermove', e => {
    if (!down) return;
    const dx = e.clientX - down.x, dy = e.clientY - down.y;
    if (!down.moved && (Math.hypot(dx, dy) > 6 || performance.now() - down.t > 150)) { down.moved = true; grab(); }
    if (H.mode === 'held') {
      const r = yard.getBoundingClientRect();
      H.x = Math.max(-PW * .2, Math.min(W() - PW * .8, e.clientX - r.left - PW / 2));
      H.y = Math.max(0, r.bottom - e.clientY - 208 * sc * .75);
      samples.push({ t: performance.now(), x: e.clientX, y: e.clientY }); if (samples.length > 6) samples.shift();
    }
  });
  const up = e => {
    if (!down) return;
    if (H.mode === 'held') {
      const a = samples[0], b = samples[samples.length - 1], dt = Math.max(16, b.t - a.t) / 1000;
      H.vx = Math.max(-3000, Math.min(3000, (b.x - a.x) / dt)); H.vy = Math.max(-3000, Math.min(3000, -(b.y - a.y) / dt));
      H.mode = 'fly'; H.bounces = 0; H.peak = 0; hp.classList.remove('held'); pet.play(R.thrown, { fps: 16 });
    } else if (!down.moved) poke();
    down = null;
  };
  hp.addEventListener('pointerup', up); hp.addEventListener('pointercancel', up);
  hp.addEventListener('pointerenter', () => { if (H.mode === 'idle' || H.mode === 'walk') { H.mode = 'hover'; pet.play(R.hover, { fps: 3.5 }); say('hi!'); } });
  hp.addEventListener('pointerleave', () => { if (H.mode === 'hover') toIdle(); });
  addEventListener('pointermove', e => { H.mx = e.clientX; H.my = e.clientY; }, { passive: true });
  function grab() { if (RM) return; buzz('snap'); H.mode = 'held'; hp.classList.add('held'); pet.play(R.grabbed, { fps: 8 }); say('whoa whoa whoa'); }
  function poke() {
    const now = performance.now(); if (now - H.lastClick > 6000) H.clicks = 0; H.clicks++; H.lastClick = now;
    H.mode = 'annoy'; H.until = now + 1400; buzz(H.clicks >= 5 ? 'stomp' : 'boop');
    const f = H.clicks <= 2 ? [0] : H.clicks <= 4 ? [1, 2] : [3, 4, 5];
    pet.play(R.annoy, { frames: f, fps: 8 });
    say(H.clicks <= 2 ? 'hey' : H.clicks <= 4 ? 'HEY' : 'okay that’s it');
  }
  bugInit();
}

/* ------------------------------------------------ bug hunt ----------- */
/* A failed test run drops a bug. Companions chase it; when the tests pass, the pet catches it and eats it. Click a bug to squash it. */
const BUGS = []; let jar = 0;
const liveBugs = () => BUGS.filter(b => !b.dead);
function bugInit() {
  const bar = document.getElementById('bugbar'), fail = document.getElementById('failBtn'), pass = document.getElementById('passBtn'), jarN = document.getElementById('jarN');
  if (RM) { bar.style.display = 'none'; return; }
  H.syncBugs = () => { const n = liveBugs().length; fail.disabled = n >= 3; pass.disabled = n === 0 || !!H.catching; jarN.textContent = jar ? 'bug jar · ' + jar : ''; };
  fail.addEventListener('click', () => {
    if (liveBugs().length >= 3) return;
    const W = H.W(), fromLeft = H.x + H.PW / 2 > W / 2;
    const el = document.createElement('div'); el.className = 'bug'; el.setAttribute('role', 'button'); el.setAttribute('aria-label', 'A bug. Click to squash it.');
    const b = { el, x: fromLeft ? 4 : W - 49, dir: fromLeft ? 1 : -1, v: 55 + Math.random() * 30, dead: false, calm: 0 };
    el.addEventListener('pointerdown', e => { e.stopPropagation(); squash(b); });
    H.yard.appendChild(el); BUGS.push(b); buzz('tick');
    if (['idle', 'walk', 'hover'].includes(H.mode)) startChase();
    say(liveBugs().length > 1 ? 'more bugs!' : 'a bug!');
    H.syncBugs();
  });
  pass.addEventListener('click', () => { if (!liveBugs().length) return; H.catching = true; if (['idle', 'walk', 'hover', 'chase'].includes(H.mode)) startChase(); H.syncBugs(); });
  H.syncBugs();
}
function startChase() { H.mode = 'chase'; H.pet.play(R.chase, { fps: H.catching ? 13 : 10 }); }
function afterBug() { if (liveBugs().length) startChase(); else { H.catching = false; toIdle(); } if (H.syncBugs) H.syncBugs(); }
function squash(b) {
  if (b.dead) return;
  b.dead = true; b.el.classList.add('flat'); buzz('boop');
  setTimeout(() => { b.el.remove(); const i = BUGS.indexOf(b); if (i >= 0) BUGS.splice(i, 1); }, 1100);
  if (['idle', 'walk', 'hover', 'chase'].includes(H.mode)) { H.mode = 'busy'; say('that was my snack'); H.pet.play(R.fail, { fps: 8, loop: false, onend: afterBug }); }
  H.syncBugs();
}
function bugsStep(now, dt) {
  const W = H.W(), pc = H.x + H.PW / 2;
  for (const b of BUGS) {
    if (b.dead) continue;
    const near = Math.abs(b.x + 22 - pc) < 90;
    if (near && !H.catching && H.mode === 'chase' && now > b.calm) b.dir = b.x + 22 > pc ? 1 : -1;
    b.x += b.dir * b.v * (near && !H.catching ? 1.8 : 1) * dt;
    if (b.x < 2) { b.x = 2; b.dir = 1; b.calm = now + 1600; }
    if (b.x > W - 47) { b.x = W - 47; b.dir = -1; b.calm = now + 1600; }
    b.el.style.transform = 'translateX(' + b.x.toFixed(1) + 'px) scaleX(' + b.dir + ')';
  }
}
function chaseStep(dt) {
  const live = liveBugs(), W = H.W(), PW = H.PW;
  if (!live.length) { H.catching = false; toIdle(); if (H.syncBugs) H.syncBugs(); return; }
  const pc = H.x + PW / 2;
  let t = live[0]; for (const b of live) if (Math.abs(b.x + 22 - pc) < Math.abs(t.x + 22 - pc)) t = b;
  const dx = t.x + 22 - pc; H.dir = dx < 0 ? -1 : 1;
  const gap = H.catching ? 0 : 64, sp = H.catching ? 300 : 170;
  if (Math.abs(dx) > gap) H.x += Math.sign(dx) * Math.min(Math.abs(dx) - gap, sp * dt);
  H.x = Math.max(-PW * .15, Math.min(W - PW * .85, H.x));
  if (H.catching && Math.abs(dx) < 16) {
    t.dead = true; t.el.remove(); BUGS.splice(BUGS.indexOf(t), 1); jar++; buzz('boop');
    H.mode = 'busy'; H.pet.play(R.gulp, { fps: 9, loop: false, onend: () => { say(liveBugs().length ? 'next!' : 'yum'); afterBug(); } });
    H.syncBugs();
  }
}
function say(t) { if (!H) return; H.bub.textContent = t; H.bub.classList.add('on'); clearTimeout(H.bt); H.bt = setTimeout(() => H.bub.classList.remove('on'), 1300); }
function toIdle() { H.mode = 'idle'; H.until = performance.now() + 2500 + Math.random() * 2500; H.pet.play(R.idle, { frames: [0, 1, 2, 3], fps: 2.4 }); }
function heroStep(now) {
  if (!H) return;
  const dt = Math.min(.05, (now - H.last) / 1000); H.last = now;
  const W = H.W(), PW = H.PW, g = 2400;
  if (BUGS.length) bugsStep(now, dt);
  switch (H.mode) {
    case 'chase': chaseStep(dt); break;
    case 'fall': case 'fly': {
      H.vy -= g * dt; H.x += H.vx * dt; H.y += H.vy * dt;
      if (H.x < -PW * .15) { H.x = -PW * .15; H.vx = -H.vx * .6; }
      if (H.x > W - PW * .85) { H.x = W - PW * .85; H.vx = -H.vx * .6; }
      if (H.y <= 0) {
        const imp = -H.vy; H.peak = Math.max(H.peak, imp); H.y = 0;
        if (imp > 420 && H.bounces < 3) { H.vy = imp * .35; H.vx *= .7; H.bounces++; }
        else {
          H.vx = 0; H.vy = 0; const hard = H.peak > 1500; buzz('thud');
          H.mode = 'land';
          H.pet.play(R.land, { frames: hard ? [0, 1, 2, 3, 2, 3, 2, 3, 4, 5] : [0, 1, 4, 5], fps: hard ? 7 : 9, loop: false, onend: () => { if (hard) say('the room is spinning'); toIdle(); } });
        }
      }
      break;
    }
    case 'annoy': if (now > H.until) toIdle(); break;
    case 'idle': {
      if (liveBugs().length) { startChase(); break; }
      const r = H.cv.getBoundingClientRect(); const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      const dx = H.mx - cx, near = Math.hypot(dx, H.my - cy) < 320;
      if (near) { const f = dx < -150 ? 0 : dx < -40 ? 1 : dx < 40 ? 2 : dx < 150 ? 3 : 4; H.pet.show(R.gaze, f); H.until = Math.max(H.until, now + 1200); }
      else if (H.pet.fixed != null) H.pet.play(R.idle, { frames: [0, 1, 2, 3], fps: 2.4 });
      if (now > H.until && !near) {
        const roll = Math.random();
        if (roll < .62) { H.mode = 'walk'; H.dir = H.x > W / 2 ? -1 : (Math.random() < .5 ? -1 : 1); H.until = now + 2500 + Math.random() * 3500; H.pet.play(R.walk, { fps: 9 }); }
        else if (roll < .8) { H.mode = 'busy'; H.pet.play(R.yawn, { fps: 3, loop: false, onend: toIdle }); }
        else { H.mode = 'busy'; H.pet.play(R.sit, { fps: 3 }); setTimeout(() => { if (H.mode === 'busy') toIdle(); }, 3600); }
      }
      break;
    }
    case 'walk': {
      H.x += H.dir * 46 * H.sc * 1.6 * dt;
      if (H.x < 4 || H.x > W - PW - 4) { H.x = Math.max(4, Math.min(W - PW - 4, H.x)); H.mode = 'busy'; H.pet.play(R.turn, { frames: [0, 2, 1, 0], fps: 10, loop: false, onend: () => { H.dir *= -1; H.mode = 'walk'; H.pet.play(R.walk, { fps: 9 }); } }); }
      if (now > H.until) { H.mode = 'busy'; H.pet.play(R.startstop, { frames: [4, 5], fps: 8, loop: false, onend: toIdle }); }
      break;
    }
  }
  const flip = (H.mode === 'walk' || H.mode === 'busy' || H.mode === 'chase') && H.dir < 0 ? -1 : 1;
  H.cv.style.transform = 'scaleX(' + flip + ')';
  H.hp.style.transform = 'translate(' + H.x.toFixed(1) + 'px,' + (-H.y).toFixed(1) + 'px)';
}

/* ------------------------------------------------ marquee ------------ */
let MQ = null;
function marqueeInit() {
  const t = document.getElementById('mq');
  const names = SPECIES.map(s => s.name);
  let html = '';
  for (let k = 0; k < 2; k++) names.forEach((n, i) => { html += '<span class="' + (i % 3 === 0 ? 'f' : i % 3 === 1 ? '' : 'a') + '">' + n + '</span><span>·</span>'; });
  t.innerHTML = html;
  MQ = { t, x: 0, v: 0, last: performance.now(), lastY: scrollY };
}
function marqueeStep(now) {
  if (!MQ || RM) return;
  const dt = Math.min(.05, (now - MQ.last) / 1000); MQ.last = now;
  const dy = scrollY - MQ.lastY; MQ.lastY = scrollY;
  MQ.v += (dy / Math.max(dt, .001) - MQ.v) * .1;
  const speed = 60 + Math.min(900, Math.abs(MQ.v) * .6);
  MQ.x -= speed * dt * (MQ.v < -50 ? -1 : 1);
  const half = MQ.t.scrollWidth / 2; if (MQ.x < -half) MQ.x += half; if (MQ.x > 0) MQ.x -= half;
  const skew = Math.max(-12, Math.min(12, MQ.v * -.01));
  MQ.t.style.transform = 'translateX(' + MQ.x.toFixed(1) + 'px) skewX(' + skew.toFixed(2) + 'deg)';
}

/* ------------------------------------------------ closet ------------- */
function closetInit(accentTo) {
  const ITEMS = [
    { id: 'beanie', name: 'Beanie', slot: 'head', price: 10, own: true },
    { id: 'party', name: 'Party hat', slot: 'head', price: 5, own: true },
    { id: 'glasses', name: 'Reading glasses', slot: 'face', price: 20, own: true },
    { id: 'headphones', name: 'Headphones', slot: 'head', price: 20 },
    { id: 'bow', name: 'Bow', slot: 'head', price: 15 },
    { id: 'cap', name: 'Cap', slot: 'head', price: 15 },
    { id: 'flower', name: 'Flower crown', slot: 'head', price: 25 },
    { id: 'star', name: 'Star clip', slot: 'head', price: 12 },
    { id: 'shades', name: 'Shades', slot: 'face', price: 25 },
    { id: 'scarf', name: 'Scarf', slot: 'neck', price: 10 },
    { id: 'crown', name: 'Crown', slot: 'head', lock: '100 meals', have: 34, need: 100 },
    { id: 'wizard', name: 'Wizard hat', slot: 'head', lock: 'Reach Elder', have: 34, need: 50 }
  ];
  let stars = 34, sp = 'notchi';
  const eq = { head: 'beanie', face: null, neck: null };
  const cv = document.getElementById('closetCv');
  const pet = new Pet(cv, sp, 1.45);
  const shelf = document.getElementById('shelf'), slots = document.getElementById('slots'), starsEl = document.getElementById('stars'), toast = document.getElementById('toast');
  const spBox = document.getElementById('closetSp');
  ['notchi', 'pip', 'moss', 'gloop', 'byte', 'puff', 'wisp', 'tako'].forEach(id => { const b = document.createElement('button'); b.type = 'button'; b.textContent = SP[id].name; b.setAttribute('aria-pressed', id === sp); b.onclick = () => { sp = id; [...spBox.children].forEach(x => x.setAttribute('aria-pressed', x === b)); pet.setSpecies(id); icons(); accentTo(SP[id].c); }; spBox.appendChild(b); });
  const icCvs = [];
  ITEMS.forEach(it => {
    const b = document.createElement('div'); b.className = 'item'; b.dataset.id = it.id; b.setAttribute('role', 'button'); b.tabIndex = 0;
    b.addEventListener('keydown', e => { if ((e.key === 'Enter' || e.key === ' ') && e.target === b) { e.preventDefault(); wear(it); } });
    b.innerHTML = '<div class="ic"><canvas width="80" height="80"></canvas></div><b>' + it.name + '</b><div class="meta"><span class="pr"></span><span class="tag"></span></div>' + (it.lock ? '<div class="bar2"><i style="width:' + Math.round(it.have / it.need * 100) + '%"></i></div>' : '') + '<span class="buyline"></span>';
    b.onclick = e => { if (e.target.closest('.buy')) return; wear(it); };
    shelf.appendChild(b); icCvs.push([it, b.querySelector('canvas')]);
  });
  function icons() {
    const a = ACCIMG[sp]; if (!a) return;
    const tmp = document.createElement('canvas'); tmp.width = 40; tmp.height = 40; const tx = tmp.getContext('2d');
    icCvs.forEach(([it, c]) => {
      const x = c.getContext('2d'); x.clearRect(0, 0, 80, 80); x.imageSmoothingEnabled = false; const i = ACC.indexOf(it.id);
      tx.clearRect(0, 0, 40, 40); tx.drawImage(a, i * 40, 0, 40, 40, 0, 0, 40, 40);
      let d; try { d = tx.getImageData(0, 0, 40, 40).data; } catch (e) { d = null; }
      let x0 = 0, y0 = 0, x1 = 39, y1 = 39;
      if (d) { x0 = 40; y0 = 40; x1 = -1; y1 = -1; for (let yy = 0; yy < 40; yy++) for (let xx = 0; xx < 40; xx++) if (d[(yy * 40 + xx) * 4 + 3] > 0) { x0 = Math.min(x0, xx); x1 = Math.max(x1, xx); y0 = Math.min(y0, yy); y1 = Math.max(y1, yy); } if (x1 < 0) { x0 = 0; y0 = 0; x1 = 39; y1 = 39; } }
      const w = x1 - x0 + 1, h = y1 - y0 + 1, k = Math.max(1, Math.floor(64 / Math.max(w, h)));
      x.drawImage(tmp, x0, y0, w, h, Math.round((80 - w * k) / 2), Math.round((80 - h * k) / 2), w * k, h * k);
    });
  }
  function wear(it) {
    eq[it.slot] = eq[it.slot] === it.id ? null : it.id;
    render();
    if (eq[it.slot] === it.id) {
      buzz('tick');
      toast.textContent = it.own ? 'Wearing the ' + it.name.toLowerCase() + '.' : it.lock ? 'Trying it on. Unlocks at ' + it.lock.toLowerCase() + '.' : 'Trying it on. Get it for ★' + it.price + '.';
      if (!RM) { pet.play(R.celebrate, { fps: 10, loop: false, onend: () => pet.play(R.idle, { frames: [0, 1, 2, 3], fps: 2.4 }) }); }
    } else toast.textContent = '';
  }
  function render() {
    pet.acc = Object.values(eq).filter(Boolean); pet.last = null;
    starsEl.textContent = stars;
    slots.innerHTML = ['head', 'face', 'neck'].map(s => '<span>' + s + ' · <b>' + (eq[s] ? ITEMS.find(i => i.id === eq[s]).name : 'nothing') + '</b></span>').join('');
    [...shelf.children].forEach(b => {
      const it = ITEMS.find(i => i.id === b.dataset.id);
      b.setAttribute('aria-pressed', Object.values(eq).includes(it.id));
      b.querySelector('.pr').textContent = it.lock ? it.lock : '★ ' + it.price;
      const tag = b.querySelector('.tag'); tag.textContent = it.own ? 'owned' : it.lock ? it.have + ' / ' + it.need : 'try on'; tag.classList.toggle('own', !!it.own);
      const bl = b.querySelector('.buyline'); bl.innerHTML = '';
      if (!it.own && !it.lock && Object.values(eq).includes(it.id)) {
        const btn = document.createElement('button'); btn.type = 'button'; btn.className = 'buy'; btn.disabled = stars < it.price;
        btn.textContent = stars < it.price ? 'Need ★' + (it.price - stars) + ' more' : 'Get it · ★' + it.price;
        btn.onclick = e => { e.stopPropagation(); if (stars < it.price) return; stars -= it.price; it.own = true; toast.textContent = 'It’s yours. ★' + stars + ' left. (Demo: resets on reload.)'; render(); };
        bl.appendChild(btn);
      }
    });
    // idle loop needs row 5 for the overlay
    if (pet.row !== R.idle && pet.loop) pet.play(R.idle, { frames: [0, 1, 2, 3], fps: 2.4 });
  }
  icons(); render();
}

/* ------------------------------------------------ room + dreams ------ */
/* Room is laid out in props units: 180 x 104, floor from y = 69. --z is px per unit. */
function roomInit() {
  const box = document.getElementById('roomBox'), list = document.getElementById('decor'), starsEl = document.getElementById('roomStars');
  // id, name, price, left, top (units)
  const F = [['lights', 'Fairy lights', 9, 74, 6], ['poster', 'Poster', 5, 120, 20], ['shelf', 'Shelf', 12, 18, 26], ['rug', 'Rug', 8, 77, 90], ['lamp', 'Lamp', 10, 36, 76],
    ['records', 'Radio', 10, 52, 81], ['beanbag', 'Beanbag', 14, 112, 84], ['fishbowl', 'Fishbowl', 15, 136, 82], ['plant', 'Plant', 6, 158, 79]];
  const START = ['rug', 'lamp', 'plant'];
  let stars = 40; const owned = new Set(START), placed = new Set(START);
  const fx = {};
  F.forEach(f => { const w = document.createElement('span'); w.className = 'fx'; const p = document.createElement('span'); p.className = 'prop'; w.appendChild(p); box.appendChild(w); fx[f[0]] = { w, p }; });
  const at = document.createElement('span'); at.className = 'pet-at'; const cv = document.createElement('canvas'); at.appendChild(cv); box.appendChild(at);
  let z = 4;
  const pet = new Pet(cv, 'notchi', z * .1);
  // where the pet goes to use each piece: [left, top] in units, row, options
  const SPOT = { home: [80.4, 74.4], beanbag: [110.4, 70.5], fishbowl: [118, 74.4], records: [64, 74.4] };
  let spot = 'home', moving = false;
  const put = (k, instant) => {
    const [l, t] = SPOT[k];
    at.style.transition = instant || RM ? 'none' : 'left 1.4s linear, top 1.4s linear';
    at.style.left = (l * z) + 'px'; at.style.top = (t * z) + 'px';
  };
  const doThing = k => {
    cv.style.transform = '';
    if (k === 'beanbag') pet.play(R.night, { fps: 2 });
    else if (k === 'fishbowl') pet.show(R.gaze, 4);
    else if (k === 'records') pet.play(R.celebrate, { fps: 5 });
    else pet.play(R.idle, { fps: 6 });
  };
  const goTo = k => {
    if (k === spot) { doThing(k); return; }
    const from = SPOT[spot][0], to = SPOT[k][0]; spot = k;
    if (RM) { put(k, true); doThing(k); return; }
    moving = true; cv.style.transform = to < from ? 'scaleX(-1)' : ''; pet.play(R.walk, { fps: 9 }); put(k);
    clearTimeout(goTo.t); goTo.t = setTimeout(() => { moving = false; doThing(k); }, 1450);
  };
  const layout = () => {
    z = box.clientWidth / 180; box.style.setProperty('--z', z.toFixed(3));
    F.forEach(f => { const o = fx[f[0]]; propStyle(o.p, f[0], z); o.w.style.left = (f[3] * z) + 'px'; o.w.style.top = (f[4] * z) + 'px'; });
    pet.scale = z * .1; pet.size(); put(spot, true);
  };
  const sync = () => {
    starsEl.textContent = stars;
    F.forEach(f => fx[f[0]].w.classList.toggle('off', !placed.has(f[0])));
    [...list.children].forEach((b, i) => {
      const f = F[i], own = owned.has(f[0]), on = placed.has(f[0]);
      b.setAttribute('aria-pressed', on);
      b.querySelector('small').textContent = on ? 'in the room' : own ? 'yours · put out' : '★ ' + f[2];
    });
    box.setAttribute('aria-label', 'The pet’s room with ' + (F.filter(f => placed.has(f[0])).map(f => f[1].toLowerCase()).join(', ') || 'nothing yet'));
    if (!placed.has(spot) && spot !== 'home') goTo('home');
  };
  F.forEach(f => {
    const b = document.createElement('button'); b.type = 'button';
    const ic = document.createElement('span'); ic.className = 'ic'; const p = document.createElement('span'); p.className = 'prop';
    const [, , pw, ph] = PROP[f[0]];
    propStyle(p, f[0], Math.max(1, Math.min(3, Math.floor(Math.min(42 / pw, 36 / ph)))));
    ic.appendChild(p); b.appendChild(ic);
    b.insertAdjacentHTML('beforeend', '<span><b>' + f[1] + '</b><small></small></span>');
    b.addEventListener('click', () => {
      const id = f[0];
      if (owned.has(id)) { if (placed.has(id)) placed.delete(id); else { placed.add(id); buzz('tick'); } }
      else if (stars >= f[2]) { stars -= f[2]; owned.add(id); placed.add(id); buzz('snap'); }
      else { b.querySelector('small').textContent = 'need ★ ' + (f[2] - stars) + ' more'; return; }
      sync();
      if (placed.has(id) && SPOT[id]) goTo(id);
    });
    list.appendChild(b);
  });
  layout(); sync(); doThing('home');
  addEventListener('resize', layout);
  // wander between the things it likes, every few seconds
  if (!RM) setInterval(() => {
    if (moving) return;
    const opts = ['home'].concat(['beanbag', 'fishbowl', 'records'].filter(k => placed.has(k)));
    const next = opts[(opts.indexOf(spot) + 1) % opts.length];
    goTo(next);
  }, 5200);

  /* dreams */
  const D = [['d-wrench', 'edits'], ['d-flask', 'tests'], ['d-bug', 'a bug'], ['d-merge', 'a merge'], ['d-check', 'a pass'], ['d-star', 'a party'], ['d-heart', 'you said thanks'], ['d-moon', 'bedtime']];
  const tl = document.getElementById('dreamTl'), ic = document.getElementById('dreamIc');
  new Pet(document.getElementById('dreamCv'), 'notchi', .19).show(R.peek, 2);
  D.forEach(([id, label]) => { const s = document.createElement('span'); const p = document.createElement('i'); p.className = 'prop'; propStyle(p, id, 1.5); s.appendChild(p); s.appendChild(document.createTextNode(label)); tl.appendChild(s); });
  let di = 0;
  const showDream = i => { propStyle(ic, D[i][0], 6); [...tl.children].forEach((s, k) => s.classList.toggle('on', k === i)); };
  showDream(0);
  if (!RM) setInterval(() => { di = (di + 1) % D.length; ic.classList.add('swap'); setTimeout(() => { showDream(di); ic.classList.remove('swap'); }, 280); }, 1700);
}

/* ------------------------------------------------ pet park ----------- */
let PK = null;
function parkInit() {
  const el = document.getElementById('parkYard');
  [[5, 1], [33, 1.3], [64, .9], [86, 1.15]].forEach(([l, s]) => { const t = document.createElement('i'); t.className = 'tree'; t.style.left = l + '%'; t.style.transform = 'scale(' + s + ')'; el.appendChild(t); });
  for (let i = 0; i < 24; i++) { const s = document.createElement('i'); s.className = 'star'; s.style.left = ((i * 37) % 100) + '%'; s.style.top = ((i * 17) % 46) + '%'; el.appendChild(s); }
  const SAMPLE = [['Mochi', 'notchi', 'teen'], ['Biscuit', 'pip', 'adult'], ['Jelly', 'gloop', 'baby'], ['Fog', 'wisp', 'elder'], ['Bolt', 'byte', 'teen'], ['Inky', 'tako', 'adult'], ['Sprig', 'moss', 'baby'], ['Nimbus', 'puff', 'teen']];
  const lanes = [.30, .06, .22, .0, .16, .11, .26, .03];
  const sc = innerWidth < 600 ? .34 : .44;
  const W = () => el.clientWidth;
  const walkers = SAMPLE.slice(0, innerWidth < 600 ? 4 : 8).map(([name, id, stage], i, all) => {
    const w = document.createElement('div'); w.className = 'walker';
    const b = Math.round(lanes[i] * 100); w.style.bottom = b + '%'; w.style.zIndex = 100 - b;
    w.setAttribute('role', 'button'); w.setAttribute('tabindex', '0'); w.setAttribute('aria-label', name + ', a ' + SP[id].name + '. Tap for a trick.');
    w.innerHTML = '<span class="tag">' + name + ' <em>· ' + SP[id].name + ' · ' + stage + '</em></span>';
    const cv = document.createElement('canvas'); w.appendChild(cv); el.appendChild(w);
    const pet = new Pet(cv, id, sc).play(R.walk, { fps: 8 }); pet.t0 -= Math.random() * 1000;
    const o = { w, cv, pet, x: (i / all.length) * (W() + 140) - 100, dir: i % 3 === 1 ? -1 : 1, v: 28 + (i * 7) % 22, busy: null, n: i };
    const trick = () => {
      if (o.busy) return; buzz('tick');
      const k = [R.backflip, R.juggle, R.moonwalk][o.n++ % 3];
      const frames = k === R.backflip ? [0, 1, 2, 3, 4, 5] : k === R.juggle ? [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3] : [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3];
      o.busy = { k, t0: performance.now() };
      pet.play(k, { frames, fps: k === R.backflip ? 8 : 7, loop: false, onend: () => { o.busy = null; pet.play(R.walk, { fps: 8 }); } });
    };
    w.addEventListener('click', trick);
    w.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); trick(); } });
    return o;
  });
  PK = { el, walkers, W, sc, on: false, last: performance.now() };
  new IntersectionObserver(es => { PK.on = es[0].isIntersecting; }).observe(el);
  parkStep(performance.now(), true);
}
function parkStep(now, force) {
  if (!PK || (!PK.on && !force)) { if (PK) PK.last = now; return; }
  const dt = Math.min(.05, (now - PK.last) / 1000); PK.last = now;
  const W = PK.W(), body = 208 * PK.sc;
  for (const o of PK.walkers) {
    let y = 0;
    if (!RM) {
      if (!o.busy) o.x += o.dir * o.v * dt;
      else if (o.busy.k === R.moonwalk) o.x -= o.dir * o.v * 1.4 * dt;     // slides backwards while facing forwards
      else if (o.busy.k === R.backflip) {                                      // frames 1-4 are airborne: add the jump arc
        const t = (now - o.busy.t0) / 1000, a = (t - .125) / .5;
        if (a > 0 && a < 1) y = Math.sin(Math.PI * a) * body * .8;
      }
      if (o.x > W + 30) o.x = -150; if (o.x < -150) o.x = W + 30;
    }
    o.w.style.transform = 'translate(' + o.x.toFixed(1) + 'px,' + (-y).toFixed(1) + 'px)';
    o.cv.style.transform = o.dir < 0 ? 'scaleX(-1)' : '';
  }
}

init();
})();
})(0);
