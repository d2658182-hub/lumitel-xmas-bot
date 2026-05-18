const puppeteer = require('puppeteer');
const LOGIN_URL = 'https://xmas.lumitel.bi/Home/Login';
const GAME_URL = 'https://xmas.lumitel.bi/Game/StartHtmlGameNoView';
const MSISDN = '65107143';
const PASSWORD = '65';

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function extractTurns(text) {
  const u = text.toUpperCase();
  const patterns = ['TOTAL REMAINING PLAY', 'REMAINING PLAY', 'TOTAL PLAY', 'TOURS RESTANTS', 'REMAINING'];
  for (const p of patterns) {
    const idx = u.indexOf(p);
    if (idx !== -1) {
      const after = text.slice(idx + p.length);
      const m = after.match(/(\d+)/);
      if (m) return parseInt(m[1]);
    }
  }
  // fallback: cherche n'importe quel nombre dans le texte
  const all = text.match(/(\d+)/g);
  if (all) return parseInt(all[0]);
  return null;
}

async function playOneGame(page, gameNum, totalGames) {
  console.log(`\n[BOT] === PARTIE ${gameNum}/${totalGames} ===`);

  console.log('[BOT] Chargement du jeu...');
  await page.goto(GAME_URL, { waitUntil: 'networkidle0', timeout: 30000 });
  await sleep(3000);

  if (page.url().includes('Login')) {
    console.log('[BOT] Redirigé vers la connexion - session perdue');
    return 0;
  }

  try { await page.evaluate(() => { s_bFirstPlay = false; s_bAudioActive = false; }); } catch(e) {}

  const cr = await page.evaluate(() => {
    const c = document.querySelector('canvas#canvas');
    if (!c) return null;
    const r = c.getBoundingClientRect();
    return { l: r.left, t: r.top, w: r.width, h: r.height, cw: c.width, ch: c.height };
  });
  if (!cr) { console.log('[BOT] Canvas introuvable'); return 0; }

  await page.mouse.click(cr.l + 960 * (cr.w / cr.cw), cr.t + 1370 * (cr.h / cr.ch));
  await sleep(3000);

  await page.evaluate(() => {
    if (typeof s_oGame === 'undefined') return;
    s_oGame.startUpdate();
    window.__bot = {
      dir: null, score: 0, best: 0, tStart: performance.now(), gameContainer: null, gameOver: false,
      findGameContainer() {
        if (!s_oStage || !s_oStage.children) return null;
        for (const child of s_oStage.children) {
          if (!child.children) continue;
          for (const sub of child.children) {
            if (!sub.children) continue;
            for (const spr of sub.children) {
              if (!(spr instanceof createjs.Sprite) || !spr.spriteSheet) continue;
              try { const fr = spr.spriteSheet.getFrame(0); if (fr && fr.rect && fr.rect.width === 334 && fr.rect.height === 289) return child; } catch(e) {}
            }
          }
        }
        return null;
      },
      getPhase(t) { if (t < 15000) return 'early'; if (t < 35000) return 'mid'; return 'late'; },
      getThresholds(p) { if (p === 'early') return { L: -200, R: 120 }; if (p === 'mid') return { L: -164, R: 86 }; return { L: -120, R: 60 }; },
      move(dir) { if (this.dir === dir) return; s_oGame.moveLeft(dir === 'left'); s_oGame.moveRight(dir === 'right'); this.dir = dir; },
      stop() { if (this.dir === null) return; s_oGame.moveLeft(false); s_oGame.moveRight(false); this.dir = null; },
      tick() {
        if (this.gameOver || !s_oStage || !s_oStage.children) return;
        if (typeof s_iBestScore !== 'undefined' && s_iBestScore > this.best) { this.best = s_iBestScore; this.score = s_iBestScore; }
        if (!this.gameContainer) { this.gameContainer = this.findGameContainer(); if (!this.gameContainer) return; }
        const t = performance.now() - this.tStart, phase = this.getPhase(t);
        let hx = 960, hy = 0; const items = [];
        for (const ch of this.gameContainer.children) {
          if (!ch.children || !ch.children.length) continue;
          const fc = ch.children[0];
          if (!(fc instanceof createjs.Sprite) || !fc.spriteSheet) continue;
          try {
            const fr = fc.spriteSheet.getFrame(0); if (!fr || !fr.rect) continue;
            const w = fr.rect.width, h = fr.rect.height;
            if (w === 334 && h === 289) { hx = ch.x; hy = ch.y; }
            else if (w === 168 && h === 154 && ch.visible) {
              const m = (fc.currentAnimation || '').match(/type_(\d+)/);
              items.push({ x: ch.x, y: ch.y, bad: m && m[1] === '6' });
            }
          } catch(e) {}
        }
        const minY = hy - 242, maxY = hy - 54;
        const c = items.filter(i => !i.bad && i.y >= minY && i.y <= maxY);
        const u = items.filter(i => !i.bad && i.y < minY);
        if (c.length) {
          let wx = 0, ws = 0;
          for (const i of c) { const u2 = (i.y - minY) / (maxY - minY + 1); wx += i.x * (0.3 + 0.7 * u2); ws += 0.3 + 0.7 * u2; }
          const dx = wx / ws - hx; const th = this.getThresholds(phase);
          if (dx < th.L) this.move('left'); else if (dx > th.R) this.move('right'); else this.stop();
        } else if (u.length) {
          const t2 = u.reduce((a, b) => a.y > b.y ? a : b);
          const dx = t2.x - hx; const app = phase === 'early' ? 60 : (phase === 'mid' ? 40 : 30);
          if (dx < -app) this.move('left'); else if (dx > app) this.move('right'); else this.stop();
        } else {
          const dx = 960 - hx;
          if (Math.abs(dx) > 30) this.move(dx > 0 ? 'right' : 'left'); else this.stop();
        }
      }
    };
    window.__bot.botLoopId = setInterval(() => window.__bot.tick(), 16);
  });

  await page.evaluate(() => {
    const orig = window.__bot.tick.bind(window.__bot);
    window.__bot.tick = function() { orig(); if (this.score !== this._lastReported) { this._lastReported = this.score; window.__botReport(this.score); } };
  });

  const START = Date.now();
  let detectedRedirect = false;
  while (Date.now() - START < 120000) {
    await sleep(1000);
    const t = Math.round((Date.now() - START) / 1000);
    if (t % 5 === 0) {
      let url = '?';
      try { url = page.url(); } catch(e) {}
      console.log(`[BOT] t=${t}s score=${monitorScore}`);
    }
    try {
      const u = page.url();
      if (!u.includes('Playgame') && !u.includes('Login')) {
        if (!detectedRedirect) {
          detectedRedirect = true;
          console.log('[BOT] Redirect détecté, pause 6s pour finaliser SaveGame...');
          await sleep(6000);
        }
        break;
      }
    } catch(e) { break; }
  }

  await sleep(2000);
  console.log(`[BOT] Partie ${gameNum} terminée, score=${monitorScore}`);

  try {
    await page.goto('https://xmas.lumitel.bi/Home/Index', { waitUntil: 'networkidle0', timeout: 15000 });
    await sleep(1000);
  } catch(e) {}

  return monitorScore;
}

async function getRemainingTurns(page) {
  await page.goto('https://xmas.lumitel.bi/Game/ViewProfile', { waitUntil: 'networkidle0', timeout: 20000 });
  await sleep(2000);
  const txt = await page.evaluate(() => document.body.innerText);
  const turns = extractTurns(txt);
  console.log('[BOT] Profil:', txt.replace(/\n+/g, ' | '));
  return turns;
}

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-web-security', '--window-size=800,900']
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 800, height: 850 });

  // ─── CHEAT: compress Math.random to bias items near center ───
  await page.evaluateOnNewDocument(() => {
    const _orig = Math.random;
    Math.random = function() { return 0.5 + (_orig() - 0.5) * 0.24; };
  });

  // ─── LOGIN ──────────────────────────────────
  console.log('[BOT] Chargement de la page de connexion...');
  await page.goto(LOGIN_URL, { waitUntil: 'networkidle0', timeout: 30000 });
  await sleep(2000);
  const csrf = await page.evaluate(() => document.querySelector('input[name=__RequestVerificationToken]')?.value);

  await page.type('#msisdn', MSISDN, { delay: 50 });
  await page.type('#password', PASSWORD, { delay: 50 });
  await sleep(500);

  const loginResult = await page.evaluate(async (csrf) => {
    return new Promise((resolve) => {
      $.ajax({
        type: 'POST', url: '/Home/LoginJsonAction',
        headers: { 'RequestVerificationToken': csrf, 'Accept': 'application/json' },
        data: { msisdn: '65107143', password: '65' },
        success: d => resolve(d), error: () => resolve(null)
      });
    });
  }, csrf);

  console.log('[BOT] Connexion:', JSON.stringify(loginResult));
  if (!loginResult || loginResult.errorCode !== '0') {
    console.log('[BOT] Connexion échouée'); await browser.close(); return;
  }

  // ─── BINDING PERSISTANT (exposeFunction dure au-delà des navigations) ──
  let monitorScore = 0;
  await page.exposeFunction('__botReport', (score) => { monitorScore = score; });

  // ─── BOUCLE DE JEU (indéfinie) ──────────────
  let totalScore = 0;
  let gameCount = 0;

  while (true) {
    let turns = await getRemainingTurns(page);

    if (!turns || turns <= 0) {
      console.log('[BOT] Aucun tour. Attente 10 min avant de revérifier...');
      await sleep(600000);
      continue;
    }

    console.log(`[BOT] Tours disponibles: ${turns}`);
    const maxGames = turns;

    for (let i = 1; i <= maxGames; i++) {
      gameCount++;
      const score = await playOneGame(page, gameCount, '∞');
      totalScore += score;

      // Vérifie que le tour a bien été consommé (réessaye 3x)
      let remaining = null;
      for (let attempt = 0; attempt < 3; attempt++) {
        remaining = await getRemainingTurns(page);
        if (remaining !== null && remaining < turns) break;
        console.log('[BOT] Tour pas encore décompté, nouvelle tentative...');
        await sleep(3000);
      }
      turns = remaining || 0;
      console.log(`[BOT] Tours restants: ${turns}, score total: ${totalScore}`);

      if (turns <= 0) {
        console.log('[BOT] Plus de tours dans ce lot.');
        break;
      }
    }

    console.log(`\n[BOT] Lot terminé. Parties: ${gameCount}, score total: ${totalScore}`);
    console.log('[BOT] Attente 10 min avant prochaine vérification...\n');
    await sleep(600000);
  }
})();
