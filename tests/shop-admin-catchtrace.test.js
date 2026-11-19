// Browser test of the CatchTrace link on shop-admin.html. Runs offline: the
// shop database and CatchTrace are replaced by recorded answers, so this tests
// the page's behaviour. The database side is tested by sql/test_catchtrace_link.sh.
// Usage: SUPABASE_BUNDLE=/path/supabase.mjs PLAYWRIGHT=/path/to/node_modules/playwright node tests/shop-admin-catchtrace.test.js
const path = require('path'), fs = require('fs'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const ROOT = path.resolve(__dirname, '..');
let n = 0, failed = 0;
const ok = (c, name, extra) => { n++; if (c) console.log('ok ' + n + ' - ' + name); else { failed++; console.log('not ok ' + n + ' - ' + name + (extra !== undefined ? '   # got: ' + JSON.stringify(extra) : '')); } };

const TOKEN = '0123456789abcdef0123456789abcdef';
const TRACE = { found: true, demonstration_data: false,
  product: { batch_ref: 'BAT-261115-0001', product_form: 'whole, chilled', product_name: 'Rabbitfish whole', packed_by: 'TEST Coop', packaged_on: '2026-11-15' },
  sources: [{ catch_ref: 'CAT-1', species: 'Rabbitfish', species_sw: 'Tafi', landing_site: 'TEST Shimoni', county: 'Kwale', catch_date: '2026-11-14',
              verification: { community: true, document: false, official: false, disputed: false, label: 'Community verified' } },
            { catch_ref: 'CAT-2', species: 'Rabbitfish', species_sw: 'Tafi', landing_site: 'TEST Shimoni', county: 'Kwale', catch_date: '2026-11-15',
              verification: { community: false, document: false, official: false, disputed: false, label: 'Not yet verified' } }],
  supplier_sources: [] };
const PRODUCTS = [{ id: 1, name: 'Rabbitfish', sw_name: 'Tafi', price: 900, sale_unit: 'kg', catch_weight: true, stock_qty: 10, in_stock: true, sort_order: 1, active: true },
                  { id: 2, name: 'Octopus', sw_name: 'Pweza', price: 1200, sale_unit: 'kg', catch_weight: true, stock_qty: 0, in_stock: false, sort_order: 2, active: true }];

(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html' : 'application/octet-stream' }); res.end(fs.readFileSync(f));
  }).listen(0);
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 400, height: 800 } });
  const calls = [], ctCalls = [];
  let honey = null, used = { times: 0, qty: 0 }, trace = TRACE, ctStatus = 200, saveError = null;
  const bundle = fs.readFileSync(process.env.SUPABASE_BUNDLE);
  await ctx.route('https://esm.sh/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: bundle }));
  await ctx.route('https://fonts.googleapis.com/**', (r) => r.abort());
  const json = (r, body, status) => r.fulfill({ status: status || 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  await ctx.route('https://tcpqbrchpxpshmqprbkv.supabase.co/**', async (r) => {
    const u = new URL(r.request().url()), m = r.request().method();
    if (m === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    const body = r.request().postData() ? JSON.parse(r.request().postData()) : null;
    calls.push({ path: u.pathname, body });
    if (u.pathname === '/auth/v1/token') return json(r, { access_token: 'x.eyJzdWIiOiJ1In0.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'u', email: 'owner@test.invalid', aud: 'authenticated' } });
    if (u.pathname === '/rest/v1/mfm_shop_products') return json(r, PRODUCTS);
    if (u.pathname === '/rest/v1/rpc/shop_trace_code_used') return json(r, used);
    if (u.pathname === '/rest/v1/rpc/add_shop_stock_traced') return saveError ? json(r, { message: saveError, code: 'P0001' }, 400) : json(r, { intake_id: 99, earlier_qty_on_this_code: 0 });
    if (u.pathname === '/rest/v1/rpc/shop_trace_coverage') return json(r, [{ product_id: 1, product_name: 'Rabbitfish', sale_unit: 'kg', received: 20, traced: 5, traced_test: 4.5 }]);
    if (u.pathname === '/rest/v1/rpc/shop_trace_links_recent') return json(r, [{ id: 7, created_at: '2026-11-15T06:00:00Z', product_id: 1, product_name: 'Rabbitfish', sw_name: 'Tafi', sale_unit: 'kg', qty: 4.5,
      trace_token: TOKEN, trace_env: 'staging', batch_ref: 'BAT-261115-0001', summary: { species: ['Rabbitfish (Tafi)'], landing_sites: ['<img src=x onerror=alert(1)>'] }, demonstration_data: false, staff_name: 'owner' }]);
    if (u.pathname === '/rest/v1/rpc/shop_today_summary') return json(r, [{ total: 0, cnt: 0, mpesa: 0, cash: 0 }]);
    return json(r, []);
  });
  await ctx.route('https://ekahacxukzxalbgwtixm.supabase.co/**', async (r) => {
    if (r.request().method() === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    ctCalls.push({ url: r.request().url(), headers: r.request().headers(), body: JSON.parse(r.request().postData() || 'null') });
    if (ctStatus !== 200) return json(r, { code: 'PT429', message: 'busy' }, ctStatus);
    if (honey) return json(r, r.request().url().endsWith('/rpc/honey_passport') ? honey : { found: false });
    return json(r, trace);
  });
  const pg = await ctx.newPage();
  const errors = []; pg.on('pageerror', (e) => errors.push(String(e)));
  pg.on('dialog', (d) => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  await pg.goto(base + '/shop-admin.html');
  await pg.fill('#email', 'owner@test.invalid'); await pg.fill('#pw', 'x'); await pg.click('#signin');
  await pg.waitForSelector('#traced [data-traced]');

  const cards = await pg.locator('#traced b').allTextContents();
  ok(cards[0] === '25%' && cards[1] === '5' && cards[2] === '4.5', 'T1 the traceable-stock section shows the share of kg traced, kg traced and kg on test codes, kept apart', cards);
  const row = await pg.textContent('#traced [data-traced="7"]');
  ok(row.includes('Rabbitfish · 4.5kg') && row.includes('TEST') && row.includes('BAT-261115-0001') && (await pg.locator('#traced img').count()) === 0,
    'T2 each traced intake is listed with batch and a TEST mark; text from CatchTrace is shown as text, never as page code', row);
  ok((await pg.getAttribute('#traced [data-traced="7"] a', 'href')) === 'https://mombasafishcatchtrace.netlify.app/trace/?t=' + TOKEN, 'T3 each one links to its public trace page');

  await pg.click('#addTraced');
  await pg.selectOption('#tProduct', '1');
  await pg.fill('#tCode', 'hello');
  await pg.click('#tCheck');
  ok((await pg.textContent('#tResult')).includes('not a CatchTrace code') && ctCalls.length === 0 && await pg.isHidden('#tSave'), 'T4 something that is not a CatchTrace code is refused without asking CatchTrace');

  await pg.fill('#tCode', 'https://mombasafishcatchtrace.netlify.app/trace/?t=' + TOKEN.toUpperCase());
  await pg.click('#tCheck');
  await pg.waitForSelector('#tSave:not(.hide)');
  const res = await pg.textContent('#tResult');
  ok(ctCalls.length === 1 && ctCalls[0].url.endsWith('/rest/v1/rpc/public_trace') && ctCalls[0].body.p_token === TOKEN && !ctCalls[0].headers.authorization?.includes('x.eyJ'),
    'T5 the pasted link is read, and only the public trace function is asked - the shop sign-in is never sent to CatchTrace', ctCalls[0] && { url: ctCalls[0].url, auth: ctCalls[0].headers.authorization });
  ok(res.includes('BAT-261115-0001') && res.includes('Rabbitfish (Tafi)') && res.includes('Landed at TEST Shimoni, Kwale') && res.includes('Caught 2026-11-14 to 2026-11-15')
     && res.includes('Verified: 1 by the community (BMU) — of 2 catch records'), 'T6 the check shows the batch, fish, landing site, catch dates and how much is verified', res);
  ok(!res.includes('TEST system'), 'T7 linked to the live CatchTrace, a real code is not marked as test');

  await pg.fill('#tQty', '4.5');
  await pg.click('#tSave');
  await pg.waitForFunction(() => !document.querySelector('#tmodal').classList.contains('show'));
  const save = calls.filter((c) => c.path === '/rest/v1/rpc/add_shop_stock_traced').pop();
  ok(save && save.body.p_product === 1 && save.body.p_qty === 4.5 && save.body.p_trace_token === TOKEN && save.body.p_trace_env === 'production' && save.body.p_batch_ref === 'BAT-261115-0001'
     && save.body.p_demo === false && save.body.p_summary.landing_sites[0] === 'TEST Shimoni, Kwale' && save.body.p_summary.verified.community === 1,
    'T8 saving sends product, amount, code, system, batch and the summary in one call', save && save.body);
  ok((await pg.textContent('#toast')).includes('traced'), 'T9 the owner is told it was added as traced stock');

  await pg.click('#addTraced');
  await pg.selectOption('#tProduct', '2');
  used = { times: 1, qty: 4.5 };
  await pg.fill('#tCode', TOKEN);
  await pg.click('#tCheck');
  await pg.waitForSelector('#tSave:not(.hide)');
  const r2 = await pg.textContent('#tResult');
  ok(r2.includes('already used 1 time(s) for 4.5') && r2.includes('does not obviously match Octopus'), 'T10 a code used before, or for a different fish, gets a warning', r2);
  await pg.fill('#tCode', 'ffffffffffffffffffffffffffffffff');
  ok(await pg.isHidden('#tSave'), 'T11 changing the code after checking it hides Save until it is checked again');

  trace = { found: false };
  await pg.click('#tCheck');
  await pg.waitForFunction(() => /does not recognise/.test(document.querySelector('#tResult').textContent));
  ok(await pg.isHidden('#tSave'), 'T12 an unknown or withdrawn code cannot be linked');
  ctStatus = 429;
  await pg.click('#tCheck');
  await pg.waitForFunction(() => /busy/.test(document.querySelector('#tResult').textContent));
  ok(await pg.isHidden('#tSave'), 'T13 when CatchTrace is busy the page says so and nothing can be saved');
  ctStatus = 200; trace = Object.assign({}, TRACE, { demonstration_data: true });
  await pg.selectOption('#tProduct', '1');
  await pg.click('#tCheck');
  await pg.waitForSelector('#tSave:not(.hide)');
  ok((await pg.textContent('#tResult')).includes('DEMONSTRATION data'), 'T14 demonstration codes are flagged');
  saveError = 'owner only — adding stock is restricted to the owner';
  await pg.fill('#tQty', '1');
  await pg.click('#tSave');
  await pg.waitForFunction(() => /owner only/.test(document.querySelector('#toast').textContent));
  ok(await pg.isVisible('#tmodal'), 'T15 a refusal from the shop database is shown and the form stays open');
  // ---- honey jars (HoneyTrace)
  saveError = null; await pg.click('#tCancel');
  const HTOKEN = 'abcdefabcdefabcdefabcdefabcdef12';
  const HONEY = { found: true, kind: 'honey', scope: 'package', package_code: 'HPK-261120-000001-0007', package_status: 'ok', demonstration_data: false,
    honey_type: 'mangrove', composition: [{ honey_class: 'mangrove', share_pct: 100 }], recall: null,
    packaging: { pack_ref: 'HPK-261120-000001', packed_on: '2026-11-20', packed_by: 'TEST MombasaFish', package: { kind: 'jar', material: 'glass', net_g: 250 } },
    origins: [{ honey_class: 'mangrove', community: 'Pongwe-Kidimu', county: 'Kwale', habitat: 'mangrove', producer: null, producer_group: 'TEST Pongwe-Kidimu Beekeepers',
                from: '2026-11-18', to: '2026-11-18', harvests: 1, community_verified: 1, document_verified: 0, disputed: 0 }],
    harvest_period: { from: '2026-11-18', to: '2026-11-18' } };
  honey = HONEY; ctCalls.length = 0;
  await pg.click('#addTraced'); await pg.selectOption('#tProduct', '1');
  await pg.fill('#tCode', 'https://mombasafishcatchtrace.netlify.app/trace/?h=' + HTOKEN);
  await pg.click('#tCheck'); await pg.waitForSelector('#tSave:not(.hide)');
  const hr = await pg.textContent('#tResult');
  ok(ctCalls.map((c) => c.url.split('/rpc/')[1]).join(',') === 'public_trace,honey_passport' && ctCalls[1].body.p_token === HTOKEN,
    'T17 a honey jar QR (?h=) is read; not being a fish code, it is looked up in HoneyTrace', ctCalls.map((c) => c.url));
  ok(hr.includes('HPK-261120-000001 · Mangrove honey') && hr.includes('Jar HPK-261120-000001-0007') && hr.includes('TEST Pongwe-Kidimu Beekeepers · Pongwe-Kidimu, Kwale')
     && hr.includes('Harvested 2026-11-18') && hr.includes('Verified: 1 by the beekeepers\' community'), 'T18 the check shows the honey, jar, beekeepers\' community, harvest date and verification', hr);
  await pg.fill('#tQty', '12'); await pg.click('#tSave');
  await pg.waitForFunction(() => !document.querySelector('#tmodal').classList.contains('show'));
  const hs = calls.filter((c) => c.path === '/rest/v1/rpc/add_shop_stock_traced').pop();
  ok(hs && hs.body.p_trace_token === HTOKEN && hs.body.p_batch_ref === 'HPK-261120-000001' && hs.body.p_summary.kind === 'honey' && hs.body.p_summary.package_code === 'HPK-261120-000001-0007',
    'T19 saving links the stock to the honey packing batch, with a honey summary', hs && hs.body);
  honey = Object.assign({}, HONEY, { recall: { recall_ref: 'HRC-261120-000001', notice: 'TEST return for refund.', status: 'open', opened_on: '2026-11-20' } });
  await pg.click('#addTraced'); await pg.fill('#tCode', HTOKEN); await pg.click('#tCheck');
  await pg.waitForFunction(() => /UNDER RECALL/.test(document.querySelector('#tResult').textContent));
  ok(await pg.isHidden('#tSave'), 'T20 honey under recall cannot be put on sale');
  ok(errors.length === 0, 'T16 no script errors or pop-ups', errors);

  await browser.close(); server.close();
  console.log('1..' + n); console.log(failed ? '# FAILED ' + failed + ' of ' + n : '# all ' + n + ' passed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('not ok - crashed: ' + (e.stack || e)); process.exit(2); });
