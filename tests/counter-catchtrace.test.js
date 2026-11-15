// Browser test of the CatchTrace parts of counter.html, offline (recorded answers
// in place of the shop database). Checks the QR code by decoding it.
// Usage: SUPABASE_BUNDLE=... PLAYWRIGHT=... JSQR=/path/to/jsqr node tests/counter-catchtrace.test.js
const path = require('path'), fs = require('fs'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const ROOT = path.resolve(__dirname, '..');
let n = 0, failed = 0;
const ok = (c, name, extra) => { n++; if (c) console.log('ok ' + n + ' - ' + name); else { failed++; console.log('not ok ' + n + ' - ' + name + (extra !== undefined ? '   # got: ' + JSON.stringify(extra) : '')); } };
const TOKEN = 'abcdefabcdefabcdefabcdefabcdef12';
const PRODUCTS = [{ id: 1, name: 'Rabbitfish', sw_name: 'Tafi', price: 900, sale_unit: 'kg', catch_weight: true, stock_qty: 10, in_stock: true, sort_order: 1, active: true },
                  { id: 2, name: 'Octopus', sw_name: 'Pweza', price: 1200, sale_unit: 'kg', catch_weight: true, stock_qty: 3, in_stock: true, sort_order: 2, active: true }];
(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html' : 'text/javascript' }); res.end(fs.readFileSync(f));
  }).listen(0);
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 400, height: 800 } });
  let tracedRows = [{ product_id: 1, trace_token: TOKEN, trace_env: 'staging', batch_ref: 'BAT-1', species: ['Rabbitfish (Tafi)'], landing_sites: ['TEST Shimoni, Kwale'], demonstration_data: false, received_at: '2026-11-15T06:00:00Z' }];
  let tracedFails = false;
  await ctx.route('https://esm.sh/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(process.env.SUPABASE_BUNDLE) }));
  await ctx.route('https://fonts.googleapis.com/**', (r) => r.abort());
  const json = (r, body, status) => r.fulfill({ status: status || 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  await ctx.route('https://tcpqbrchpxpshmqprbkv.supabase.co/**', (r) => {
    const u = new URL(r.request().url());
    if (r.request().method() === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    if (u.pathname === '/auth/v1/token') return json(r, { access_token: 'x.eyJzdWIiOiJ1In0.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'u', email: 'staff@test.invalid', aud: 'authenticated' } });
    if (u.pathname === '/rest/v1/mfm_shop_products') return json(r, PRODUCTS);
    if (u.pathname === '/rest/v1/rpc/shop_traced_now') return tracedFails ? json(r, { message: 'not staff' }, 400) : json(r, tracedRows);
    return json(r, []);
  });
  const pg = await ctx.newPage();
  const errors = []; pg.on('pageerror', (e) => errors.push(String(e))); pg.on('dialog', (d) => { errors.push('dialog ' + d.message()); d.dismiss(); });
  await pg.goto(base + '/counter.html');
  await pg.fill('#email', 'staff@test.invalid'); await pg.fill('#pw', 'x'); await pg.click('#signin');
  await pg.waitForSelector('.prod[data-id="1"] .ptrace');
  ok((await pg.textContent('.prod[data-id="1"] .ptrace')) === '✓ TRACED · TEST' && (await pg.locator('.prod[data-id="2"] .ptrace').count()) === 0, 'C1 traced stock carries a TRACED mark (TEST while on the staging CatchTrace); other stock does not');
  await pg.click('#viewTrace');
  await pg.waitForSelector('#trmodal.show [data-trace="1"] img');
  const card = await pg.textContent('#trList');
  ok(card.includes('Rabbitfish · Tafi') && card.includes('TEST Shimoni, Kwale') && card.includes('BAT-1') && card.includes('TEST code') && !card.includes('Octopus'),
    'C2 TRACE QR lists only traceable fish, with landing site, batch and a test mark', card);
  const src = await pg.getAttribute('#trList img', 'src');
  const png = Buffer.from(src.split(',')[1], 'base64');
  const decoded = await pg.evaluate(async (data) => {
    const img = new Image(); img.src = data; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; const x = c.getContext('2d'); x.drawImage(img, 0, 0);
    return { w: img.width, h: img.height, px: Array.from(x.getImageData(0, 0, img.width, img.height).data) };
  }, src);
  const jsQR = require(process.env.JSQR);
  const qr = jsQR(Uint8ClampedArray.from(decoded.px), decoded.w, decoded.h);
  ok(png.length > 100 && qr && qr.data === 'https://mombasafishcatchtrace.netlify.app/trace/?t=' + TOKEN, 'C3 the QR code decodes to the public trace page of that batch', qr && qr.data);
  await pg.click('#trClose');
  await pg.click('.prod[data-id="1"]');
  ok(await pg.isVisible('#wmodal.show') && (await pg.textContent('#wname')) === 'Rabbitfish · Tafi', 'C4 tapping a traced product still opens the weight keypad as before');
  tracedRows = [];
  await pg.evaluate(() => document.querySelectorAll('.modal.show').forEach((m) => m.classList.remove('show')));
  tracedFails = true;
  await pg.reload(); await pg.waitForSelector('.prod[data-id="1"]');
  await pg.waitForTimeout(500);
  ok((await pg.locator('.ptrace').count()) === 0 && (await pg.locator('.prod').count()) === 2, 'C5 if the trace lookup fails, the counter carries on normally without marks');
  await pg.click('#viewTrace');
  ok((await pg.textContent('#trList')).includes('No fish on sale right now came with a CatchTrace code'), 'C6 with nothing traced, TRACE QR says so');
  ok(errors.length === 0, 'C7 no script errors or pop-ups', errors);
  await browser.close(); server.close();
  console.log('1..' + n); console.log(failed ? '# FAILED ' + failed + ' of ' + n : '# all ' + n + ' passed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('not ok - crashed: ' + (e.stack || e)); process.exit(2); });
