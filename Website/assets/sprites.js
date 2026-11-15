/* Pixel Deck sprite data + renderer. Each frame is rows of characters; '.' = transparent. */
const FLIPBIT_SPRITES = {"pal":{"k":"#1B1530","w":"#FFF6E0","p":"#FF5C8A","m":"#B8336A","y":"#FFD23F","o":"#FF8B3D","r":"#E63946","g":"#7BE07B","d":"#2E9E5B","l":"#C8B6FF","u":"#9C6B3C","e":"#5E3B22"},"slime":{"w":12,"h":16,"fps":8,"label":"Green slime bouncing","frames":[["............","............","............","............","............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kggkkggkkgdk","kggkwggkwgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk."],["............","............","............","............","............","............","............","............","...kkkkkk...",".kkggggggkk.","kgwwgggggggk","kgkkggggkkdk","kgkwggggkwdk","kggggppgggdk","kddggggggddk","kkkkkkkkkkkk"],["............","............","....kkkk....","...kggggk...","...kgwggk...","..kgwggggk..","..kgggggdk..","..kgkggkdk..","..kgkggkdk..","..kggppgdk..","..kgggggdk..","..kggggddk..","...kgdddk...","....kkkk....","............","............"],["............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kggkkggkkgdk","kggkwggkwgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk.","............","............","............","............"],["............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kggkkggkkgdk","kggkwggkwgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk.","............","............","............","............"],["............","............","....kkkk....","...kggggk...","...kgwggk...","..kgwggggk..","..kgggggdk..","..kgkggkdk..","..kgkggkdk..","..kggppgdk..","..kgggggdk..","..kggggddk..","...kgdddk...","....kkkk....","............","............"],["............","............","............","............","............","............","............","............","...kkkkkk...",".kkggggggkk.","kgwwgggggggk","kgkkggggkkdk","kgkwggggkwdk","kggggppgggdk","kddggggggddk","kkkkkkkkkkkk"],["............","............","............","............","............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kggkkggkkgdk","kggkwggkwgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk."],["............","............","............","............","............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kgggggggggdk","kggkkggkkgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk."],["............","............","............","............","............","............","....kkkk....","..kkggggkk..",".kgwwgggggk.",".kgwgggggdk.","kggggggggddk","kggkkggkkgdk","kggkwggkwgdk","kggggppggddk","kdgggggggddk",".kkkkkkkkkk."]]},"flame":{"w":10,"h":12,"fps":6,"label":"Flickering campfire","frames":[["....r.....","....oo....","...ooyo...","..ooyyo...","..oyyyoo..",".ooyywyo..",".oyywwyoo.",".oyywwyyo.",".ooywwyoo.","..ooyyoo..","euuueeuuue",".ee....ee."],["......r...",".....oo...","..r..oyo..","..oo.oyo..","..oyooyoo.",".ooyyyyyo.",".oyyywyyo.",".oyywwyyo.",".ooywwyoo.","..ooyyoo..","euuueeuuue",".ee....ee."],["...r......","...oo.....","..oyo..r..","..oyoo.oo.",".ooyyooyo.",".oyyyyyyo.",".oyywyyoo.",".oyywwyyo.",".ooywwyoo.","..ooyyoo..","euuueeuuue",".ee....ee."],["......r...",".....oo...","..r..oyo..","..oo.oyo..","..oyooyoo.",".ooyyyyyo.",".oyyywyyo.",".oyywwyyo.",".ooywwyoo.","..ooyyoo..","euuueeuuue",".ee....ee."]]},"coin":{"w":8,"h":8,"fps":8,"label":"Spinning coin","frames":[["..oooo..",".oyyyyo.","oyywyyyo","oywyyyyo","oyyyyyyo","oyyyyyoo",".oyyyyo.","..oooo.."],["...oo...","..oyyo..","..oywo..","..owyo..","..oyyo..","..oyyo..","..oyyo..","...oo..."],["...oo...","...yo...","...yo...","...yo...","...yo...","...yo...","...yo...","...oo..."],["...oo...","..oyyo..","..oywo..","..owyo..","..oyyo..","..oyyo..","..oyyo..","...oo..."]]},"ghost":{"w":10,"h":12,"fps":4,"label":"Floating ghost","frames":[["...kkkk...","..kwwwwk..",".kwwwwwwk.",".kwkwwkwk.",".kwkwwkwk.",".kpwwwwpk.",".kwwwwwlk.",".kwwwwwlk.",".kwwwwwlk.",".kwkwwklk.","..k.kk.k..",".........."],["...kkkk...","..kwwwwk..",".kwwwwwwk.",".kwkwwkwk.",".kwkwwkwk.",".kpwwwwpk.",".kwwwwwlk.",".kwwwwwlk.",".kwwwwwlk.",".kwwkkwlk.",".k.k..k.k.",".........."],["..........","...kkkk...","..kwwwwk..",".kwwwwwwk.",".kwkwwkwk.",".kwkwwkwk.",".kpwwwwpk.",".kwwwwwlk.",".kwwwwwlk.",".kwwwwwlk.",".kwkwwklk.","..k.kk.k.."],["..........","...kkkk...","..kwwwwk..",".kwwwwwwk.",".kwkwwkwk.",".kwkwwkwk.",".kpwwwwpk.",".kwwwwwlk.",".kwwwwwlk.",".kwwwwwlk.",".kwwkkwlk.",".k.k..k.k."]]},"sprout":{"w":8,"h":10,"fps":3,"label":"Sprout growing into a flower","frames":[["........","........","........","........","........","........","....g...",".eeeeee.","..euue..","..eeee.."],["........","........","........","........","....g...","...gg...","....d...",".eeeeee.","..euue..","..eeee.."],["........","........","..gg....","..ggd...","....dgg.","....dg..","....d...",".eeeeee.","..euue..","..eeee.."],["...pp...","..pyyp..","..gppg..",".ggdggg.","..gdgg..","....dg..","....d...",".eeeeee.","..euue..","..eeee.."],["...pp...","..pyyp..","..gppg..",".ggdggg.","..gdgg..","....dg..","....d...",".eeeeee.","..euue..","..eeee.."],["...pp...","..pyyp..","..gppg..",".ggdggg.","..gdgg..","....dg..","....d...",".eeeeee.","..euue..","..eeee.."]]},"moon":{"w":8,"h":8,"fps":1,"label":"Pixel moon","frames":[["..llll..",".lwwwwl.","lwwwlwwl","lwwwwwwl","lwlwwwwl","lwwwwlwl",".lwwwwl.","..llll.."]]}};

(function () {
  const S = FLIPBIT_SPRITES;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const live = [];

  function draw(ctx, sp, fi, onion, tint) {
    const n = sp.frames.length;
    ctx.clearRect(0, 0, sp.w, sp.h);
    if (onion) {
      const prev = sp.frames[(fi - 1 + n) % n];
      ctx.globalAlpha = 0.38;
      ctx.fillStyle = tint;
      for (let y = 0; y < sp.h; y++) for (let x = 0; x < sp.w; x++) if (prev[y][x] !== '.') ctx.fillRect(x, y, 1, 1);
      ctx.globalAlpha = 1;
    }
    const f = sp.frames[fi];
    for (let y = 0; y < sp.h; y++) for (let x = 0; x < sp.w; x++) {
      const c = f[y][x];
      if (c !== '.') { ctx.fillStyle = S.pal[c]; ctx.fillRect(x, y, 1, 1); }
    }
  }

  document.querySelectorAll('canvas[data-sprite]').forEach((cv) => {
    const sp = S[cv.dataset.sprite];
    if (!sp) return;
    cv.width = sp.w; cv.height = sp.h;
    cv.style.setProperty('--w', sp.w); cv.style.setProperty('--h', sp.h);
    const ctx = cv.getContext('2d');
    const item = {
      cv, ctx, sp,
      fps: Number(cv.dataset.fps) || sp.fps,
      fixed: cv.dataset.frame !== undefined ? Number(cv.dataset.frame) : null,
      onion: cv.hasAttribute('data-onion'),
      tint: cv.dataset.tint || '#FF5C8A',
      visible: true, last: -1
    };
    draw(ctx, sp, item.fixed ?? 0, item.onion, item.tint);
    if (item.fixed === null && !reduce && sp.frames.length > 1) live.push(item);
  });

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((es) => es.forEach((e) => {
      const it = live.find((l) => l.cv === e.target); if (it) it.visible = e.isIntersecting;
    }));
    live.forEach((l) => io.observe(l.cv));
  }

  function tick(t) {
    for (const it of live) {
      if (!it.visible) continue;
      const fi = Math.floor(t / 1000 * it.fps) % it.sp.frames.length;
      if (fi !== it.last) { it.last = fi; draw(it.ctx, it.sp, fi, it.onion, it.tint); }
    }
    requestAnimationFrame(tick);
  }
  if (live.length) requestAnimationFrame(tick);
})();
