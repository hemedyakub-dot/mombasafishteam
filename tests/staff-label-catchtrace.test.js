// Browser test of the CatchTrace QR on the delivery label (staff.html), offline.
// Usage: SUPABASE_BUNDLE=... PLAYWRIGHT=... JSQR=... node tests/staff-label-catchtrace.test.js
const path = require('path'), fs = require('fs'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const ROOT = path.resolve(__dirname, '..');
let n = 0, failed = 0;
const ok = (c, name, extra) => { n++; if (c) console.log('ok ' + n + ' - ' + name); else { failed++; console.log('not ok ' + n + ' - ' + name + (extra !== undefined ? '   # got: ' + JSON.stringify(extra) : '')); } };
const TOKEN = 'abcdefabcdefabcdefabcdefabcdef12';
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const JWT = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: 'u1', aal: 'aal1', amr: [{ method: 'password', timestamp: 1 }], exp: Math.floor(Date.now() / 1000) + 3600, role: 'authenticated' }) + '.sig';
(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html' : f.endsWith('.jpg') ? 'image/jpeg' : 'text/javascript' }); res.end(fs.readFileSync(f));
  }).listen(0);
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
  let tracedRows = [{ product_id: 1, trace_token: TOKEN, trace_env: 'staging', batch_ref: 'BAT-1', species: ['Rabbitfish (Tafi)'], landing_sites: ['TEST Shimoni, Kwale'], demonstration_data: false, received_at: '2026-11-15T06:00:00Z' }];
  let fail = false;
  await ctx.route('https://esm.sh/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(process.env.SUPABASE_BUNDLE) }));
  await ctx.route('https://cdnjs.cloudflare.com/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: '/* html2canvas not needed here */' }));
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
  const json = (r, body, status) => r.fulfill({ status: status || 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  await ctx.route('https://tcpqbrchpxpshmqprbkv.supabase.co/**', (r) => {
    const u = new URL(r.request().url()), h = r.request().headers();
    if (r.request().method() === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    if (u.pathname === '/auth/v1/token') return json(r, { access_token: JWT, token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'u1', email: 'disp@test.invalid', aud: 'authenticated', factors: [] } });
    if (u.pathname === '/auth/v1/user') return json(r, { id: 'u1', email: 'disp@test.invalid', aud: 'authenticated', factors: [] });
    if (u.pathname === '/rest/v1/rpc/mfm_staff_code_ok') return json(r, true);
    if (u.pathname === '/rest/v1/mfm_staff') return json(r, (h.accept || '').includes('object') ? { full_name: 'TEST Dispatcher', role: 'dispatch' } : [{ full_name: 'TEST Dispatcher', role: 'dispatch' }]);
    if (u.pathname === '/rest/v1/mfm_orders') return json(r, [{ order_number: 'MF-TEST-1', tracking_code: 't', customer_name: 'TEST Customer', contact: '0700000000', county: 'Mombasa', destination: 'Nyali', items: 'Rabbitfish 2kg', stage: 1, status: 'paid', created_at: '2026-11-15T05:00:00Z', stage_changed_at: null, dispatched_at: null, delivery_type: 'delivery', rider_name: null, rider_phone: null, eta_note: null }]);
    if (u.pathname === '/rest/v1/rpc/shop_traced_now') return fail ? json(r, { message: 'not staff' }, 400) : json(r, tracedRows);
    if (u.pathname === '/rest/v1/mfm_shop_products') return json(r, [{ id: 1, name: 'Rabbitfish', sw_name: 'Tafi' }]);
    return json(r, []);
  });
  const pg = await ctx.newPage();
  const errors = []; pg.on('pageerror', (e) => errors.push(String(e))); pg.on('dialog', (d) => { errors.push('dialog ' + d.message()); d.dismiss(); });
  await pg.goto(base + '/staff.html');
  await pg.fill('#em', 'disp@test.invalid'); await pg.fill('#pw', 'x'); await pg.click('#in');
  await pg.waitForSelector('#appView:not(.hidden)', { timeout: 15000 });
  await pg.fill('#search, input[type=search]', 'MF-TEST-1').catch(() => {});
  await pg.waitForSelector('[data-label="MF-TEST-1"]', { timeout: 15000 });
  await pg.click('[data-label="MF-TEST-1"]');
  await pg.waitForFunction(() => document.querySelectorAll('#lfTrace option').length === 2);
  const opt = await pg.textContent('#lfTrace option:nth-child(2)');
  ok(opt === 'Rabbitfish (Tafi) · TEST Shimoni, Kwale · BAT-1 · TEST' && (await pg.inputValue('#lfTrace')) === '' && await pg.isHidden('#lfTraceQr'),
    'D1 the label offers the traced shop stock to choose from, and starts with no code (never picked automatically)', opt);
  await pg.selectOption('#lfTrace', '0');
  await pg.waitForSelector('#lfTraceQr[src^="data:image"]');
  const src = await pg.getAttribute('#lfTraceQr', 'src');
  const d = await pg.evaluate(async (data) => { const img = new Image(); img.src = data; await img.decode(); const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; const x = c.getContext('2d'); x.drawImage(img, 0, 0); return { w: img.width, h: img.height, px: Array.from(x.getImageData(0, 0, img.width, img.height).data) }; }, src);
  const qr = require(process.env.JSQR)(Uint8ClampedArray.from(d.px), d.w, d.h);
  ok(qr && qr.data === 'https://mombasafishcatchtrace.netlify.app/trace/?t=' + TOKEN && await pg.isVisible('#lfTraceCap'), 'D2 picking it puts a QR on the label that opens that batch\'s trace page', qr && qr.data);
  const box = async (sel) => pg.evaluate((s) => { const r = document.querySelector(s).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom]; }, sel);
  const q = await box('#lfTraceQr'), it = await box('#lfItems'), stage = await box('#labelStage');
  ok(it[2] <= q[0] && q[3] <= stage[3] && q[2] <= stage[2], 'D3 the QR sits beside the items text without covering it, inside the label', { q, it, stage });
  if (process.env.SHOT) await pg.locator('#labelStage').screenshot({ path: process.env.SHOT });
  await pg.selectOption('#lfTrace', '');
  ok(await pg.isHidden('#lfTraceQr') && await pg.isHidden('#lfTraceCap'), 'D4 choosing None removes it again');
  await pg.click('#labelClose');
  fail = true;
  await pg.click('[data-label="MF-TEST-1"]');
  await pg.waitForFunction(() => /could not be loaded/.test(document.querySelector('#lfTraceHint').textContent));
  ok((await pg.locator('#lfTrace option').count()) === 1 && (await pg.inputValue('#lfName')) === 'TEST Customer', 'D5 if CatchTrace codes cannot be loaded, the label still works as before');
  ok(errors.length === 0, 'D6 no script errors or pop-ups', errors);
  await browser.close(); server.close();
  console.log('1..' + n); console.log(failed ? '# FAILED ' + failed + ' of ' + n : '# all ' + n + ' passed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('not ok - crashed: ' + (e.stack || e)); process.exit(2); });
