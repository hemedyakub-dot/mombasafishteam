// Browser test of honey-orders.html (Honey Orders section of the team app). Runs offline:
// the shop database is replaced by recorded answers, so this tests the page. The database
// functions are tested by sql/test_honey_01.sql (rolled back on the live project).
// Usage: SUPABASE_BUNDLE=/path/supabase.mjs PLAYWRIGHT=/path/to/node_modules/playwright node tests/honey-orders.test.js
const path = require('path'), fs = require('fs'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const ROOT = path.resolve(__dirname, '..');
let n = 0, failed = 0;
const ok = (c, name, extra) => { n++; if (c) console.log('ok ' + n + ' - ' + name); else { failed++; console.log('not ok ' + n + ' - ' + name + (extra !== undefined ? '   # got: ' + JSON.stringify(extra) : '')); } };

const O = (num, x) => Object.assign({ order_number: num, tracking_code: 'TRK' + num.slice(-3), created_at: '2026-11-21T10:00:00Z', customer_name: 'Asha', phone: '0712345678', email: null,
  county: 'Mombasa', town: 'Nyali', address: 'Links Rd', fulfilment: 'delivery', total_kg: 1, pricing: 'retail', subtotal_kes: 1800, delivery_kes: null, paid_kes: null,
  stage: 1, status: 'pending', notes: 'Honey order.', is_test: false, extracted_kg: 1, extracted_pricing: 'retail', honeycomb_kg: 0, honeycomb_pricing: null,
  items: [{ product: 'Mangrove Honey', slug: 'mangrove', kg: 1, unit_kes_per_kg: 1800, line_kes: 1800, pricing: 'retail', pricing_group: 'extracted_honey' }] }, x);
const ORDERS = [
  O('MSA-NOV 240'),
  O('NRB-NOV 241', { customer_name: 'Juma Ltd', phone: '0722000111', county: 'Nairobi', town: 'Westlands', total_kg: 7, pricing: 'wholesale', subtotal_kes: 7800, status: 'awaiting_payment', delivery_kes: 600,
    extracted_kg: 7, extracted_pricing: 'wholesale', honeycomb_kg: 2, honeycomb_pricing: 'retail', total_kg: 9, pricing: 'mixed', subtotal_kes: 12200,
    items: [{ product: 'Mangrove Honey', slug: 'mangrove', kg: 4, unit_kes_per_kg: 1200, line_kes: 4800, pricing: 'wholesale' }, { product: 'Wild Forest Honey', slug: 'wild-forest', kg: 3, unit_kes_per_kg: 1000, line_kes: 3000, pricing: 'wholesale' },
            { product: 'Natural Honeycomb', slug: 'honeycomb', kg: 2, unit_kes_per_kg: 2200, line_kes: 4400, pricing: 'retail', pricing_group: 'honeycomb' }] }),
  O('KWL-NOV 242', { customer_name: 'Mama Pickup', fulfilment: 'pickup', status: 'paid', paid_kes: 1600, subtotal_kes: 1600, items: [{ product: 'Wild Forest Honey', slug: 'wild-forest', kg: 1, unit_kes_per_kg: 1600, line_kes: 1600, pricing: 'retail' }] }),
  O('MSA-NOV 239', { customer_name: 'Gone', status: 'cancelled', stage: -1, cancel_reason: 'Customer cancelled' }),
  O('MSA-NOV 238', { customer_name: 'Done', status: 'completed', stage: 4 })];

(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html' : 'application/octet-stream' }); res.end(fs.readFileSync(f));
  }).listen(0);
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 400, height: 900 } });
  const bundle = fs.readFileSync(process.env.SUPABASE_BUNDLE);
  const calls = []; let codeOk = false, role = 'dispatch', rpcError = null;
  await ctx.route('https://esm.sh/**', (r) => r.fulfill({ status: 200, contentType: 'text/javascript', body: bundle }));
  const json = (r, body, status) => r.fulfill({ status: status || 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  await ctx.route('https://tcpqbrchpxpshmqprbkv.supabase.co/**', async (r) => {
    const u = new URL(r.request().url()), m = r.request().method();
    if (m === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    let body = null; try { body = r.request().postData() ? JSON.parse(r.request().postData()) : null; } catch (e) { body = null; }
    if (u.pathname === '/auth/v1/token') return json(r, { access_token: 'x.eyJzdWIiOiJ1In0.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'u', email: 'staff@test.invalid', aud: 'authenticated' } });
    if (u.pathname === '/auth/v1/logout') return r.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
    const fn = u.pathname.split('/rpc/')[1];
    calls.push({ fn: fn || u.pathname, body });
    if (u.pathname.endsWith('/mfm_staff')) return json(r, { full_name: 'Team B', role });
    if (fn === 'mfm_staff_code_ok') return json(r, codeOk);
    if (fn === 'mfm_staff_send_login_code') return json(r, { sent_to: 'st***@test.invalid' });
    if (fn === 'mfm_w_verify_login_code') { codeOk = body.p_code === '123456'; return json(r, codeOk); }
    if (fn === 'mfm_honey_admin_orders') return json(r, body.p_include_test ? ORDERS.concat([O('MSA-NOV 237', { customer_name: 'TEST x', is_test: true })]) : ORDERS);
    if (fn === 'mfm_honey_admin_products') return json(r, { groups: [{ code: 'extracted_honey', label: 'Extracted honey', wholesale_min_kg: 7 }, { code: 'honeycomb', label: 'Natural honeycomb', wholesale_min_kg: 7 }],
      products: [{ slug: 'mangrove', name: 'Mangrove Honey', swahili_name: 'Asali ya Mikoko', description: 'd', image_url: 'images/asali-mikoko.jpg', retail_kes_per_kg: 1800, wholesale_kes_per_kg: 1200, min_qty_kg: 0.25, step_kg: 0.25, pricing_group: 'extracted_honey', active: true },
                 { slug: 'honeycomb', name: 'Natural Honeycomb', swahili_name: 'Sega la Asali', description: 'Comb', image_url: 'images/honey-comb.jpg', retail_kes_per_kg: 2200, wholesale_kes_per_kg: 1500, min_qty_kg: 0.25, step_kg: 0.25, pricing_group: 'honeycomb', active: true }] });
    if (u.pathname.startsWith('/storage/v1/object/honey-products/')) { calls.push({ fn: 'upload', body: u.pathname }); return json(r, { Key: 'honey-products/x' }); }
    if (fn === 'mfm_honey_catalogue') return json(r, { wholesale_min_kg: 7, products: [{ slug: 'mangrove', name: 'Mangrove Honey', swahili_name: 'Asali ya Mikoko', retail_kes_per_kg: 1800, wholesale_kes_per_kg: 1200 }, { slug: 'wild-forest', name: 'Wild Forest Honey', retail_kes_per_kg: 1600, wholesale_kes_per_kg: 1000 }] });
    if (rpcError) { const e = rpcError; rpcError = null; return json(r, { message: e }, 400); }
    return json(r, {});
  });
  const page = await ctx.newPage();
  const errors = []; page.on('pageerror', (e) => errors.push(e.message));
  page.on('dialog', (d) => d.accept());
  await page.goto(base + '/honey-orders.html');
  await page.waitForSelector('#loginView:not(.hidden)');
  ok(!(await page.isVisible('#appView')), 'A1 signed out: only the sign-in form');
  await page.fill('#em', 'staff@test.invalid'); await page.fill('#pw', 'x'); await page.click('#in');
  await page.waitForSelector('#codeView:not(.hidden)');
  ok(calls.some((c) => c.fn === 'mfm_staff_send_login_code') && !calls.some((c) => c.fn === 'mfm_honey_admin_orders'), 'A2 after the password: the emailed code is sent and no orders load yet');
  await page.fill('#codeIn', '000000'); await page.click('#codeGo'); await page.waitForTimeout(200);
  ok(await page.isVisible('#codeView'), 'A3 a wrong code keeps the page locked');
  await page.fill('#codeIn', '123456'); await page.click('#codeGo');
  await page.waitForSelector('#appView:not(.hidden)'); await page.waitForSelector('.ord');
  const st = (await page.textContent('#stats')).replace(/\s+/g, ' ');
  ok(st.includes('Honey orders4') && st.includes('1 cancelled not counted') && st.includes('Total ordered12 kg') && st.includes('Mangrove6 kg') && st.includes('Wild Forest4 kg') && st.includes('Honeycomb2 kg'),
    'A4 totals: 4 orders (cancelled left out), 12 kg, Mangrove 6, Wild Forest 4, Honeycomb 2', st);
  ok(st.includes('Retail valueKES 9,600') && st.includes('Wholesale valueKES 7,800') && st.includes('Outstanding paymentsKES 14,600') && st.includes('Average orderKES 4,350'),
    'A5 retail 1,800 + 4,400 comb + 1,600 + 1,800 = 9,600; wholesale 7,800; outstanding 1,800 + 12,800; average 17,400 / 4', st);
  const rp = (await page.textContent('#prodReport')).replace(/\s+/g, ' ');
  ok(rp.includes('Natural Honeycombcounted on its own2 kg') && rp.includes('KES 4,400'), 'A5b product report keeps honeycomb apart', rp);
  ok((await page.$$('.ord')).length === 3, 'A6 "Open" shows the 3 orders still in progress');
  ok(!(await page.isVisible('#tabPrices')), 'A7 a dispatcher does not see the price tab');
  // filters
  await page.fill('#q', '0722 000'); ok((await page.$$('.ord')).length === 1 && (await page.textContent('.ord')).includes('Juma Ltd'), 'A8 search by phone');
  await page.fill('#q', 'msa-nov 240'); ok((await page.$$('.ord')).length === 1, 'A8b search by order reference');
  await page.fill('#q', ''); await page.selectOption('#fPrice', 'wholesale'); ok((await page.$$('.ord')).length === 1, 'A9 filter wholesale');
  ok((await page.textContent('.ord')).includes('Honey wholesale') && (await page.textContent('.ord')).includes('Comb retail'), 'A9b a mixed order shows each group\'s price');
  await page.selectOption('#fPrice', ''); await page.selectOption('#fProd', 'wild-forest'); ok((await page.$$('.ord')).length === 2, 'A10 filter by product (Wild Forest)');
  await page.selectOption('#fProd', 'honeycomb'); ok((await page.$$('.ord')).length === 1, 'A10b filter by product (Honeycomb)');
  await page.selectOption('#fProd', ''); await page.click('[data-st="all"]'); ok((await page.$$('.ord')).length === 5, 'A11 "All" shows completed and cancelled too');
  await page.click('[data-st="cancelled"]'); ok((await page.textContent('#list')).includes('Gone'), 'A11b status filter: cancelled');
  await page.check('#fTest'); await page.waitForTimeout(200);
  ok(calls.filter((c) => c.fn === 'mfm_honey_admin_orders').pop().body.p_include_test === true, 'A12 TEST orders only on request');
  await page.uncheck('#fTest'); await page.waitForTimeout(200);
  await page.fill('#from', '2026-11-20'); await page.dispatchEvent('#from', 'change'); await page.waitForTimeout(200);
  ok(calls.filter((c) => c.fn === 'mfm_honey_admin_orders').pop().body.p_from === '2026-11-20', 'A13 date filter goes to the database');
  await page.click('[data-st="open"]');
  // confirm with delivery
  await page.click('.ord[data-ord="MSA-NOV 240"] [data-toggle]');
  const det = await page.textContent('.ord[data-ord="MSA-NOV 240"] .det');
  ok(det.includes('Not confirmed yet') && det.includes('Confirm order') && det.includes('Mark paid') && !det.includes('Ready for collection'), 'A14 a new delivery order offers Confirm and Mark paid');
  await page.click('[data-act="confirm"]'); await page.fill('#shDel', '300'); await page.click('[data-go="confirm"]'); await page.waitForTimeout(200);
  let c = calls.filter((x) => x.fn === 'mfm_honey_confirm').pop();
  ok(c && c.body.p_order === 'MSA-NOV 240' && c.body.p_delivery_kes === 300, 'A15 confirm sends the delivery cost', c && c.body);
  // mark paid uses the existing function with the total
  await page.click('.ord[data-ord="NRB-NOV 241"] [data-toggle]');
  await page.click('[data-act="paid"]');
  ok((await page.inputValue('#shAmt')) === '12800', 'A16 Mark paid is prefilled with honey + delivery (12,200 + 600)');
  await page.click('[data-go="paid"]'); await page.waitForTimeout(200);
  c = calls.filter((x) => x.fn === 'mark_order_paid').pop();
  ok(c && c.body.p_order === 'NRB-NOV 241' && c.body.p_amount === 12800 && c.body.p_staff === 'Team B', 'A17 payment recorded through mark_order_paid', c && c.body);
  // pickup: ready for collection, then cancel with a database refusal shown
  await page.click('.ord[data-ord="KWL-NOV 242"] [data-toggle]');
  const d3 = await page.textContent('.ord[data-ord="KWL-NOV 242"] .det');
  ok(d3.includes('Ready for collection') && !d3.includes('Mark dispatched') && d3.includes('Start processing'), 'A18 a paid pickup order offers Ready for collection, not dispatch');
  await page.click('.ord[data-ord="KWL-NOV 242"] [data-act="ready"]'); await page.waitForTimeout(200);
  ok(calls.filter((x) => x.fn === 'mfm_honey_mark_ready').pop().body.p_order === 'KWL-NOV 242', 'A19 ready for collection');
  ok(await page.isVisible('.ord[data-ord="KWL-NOV 242"] .det'), 'A19b the order stays open after an action');
  await page.click('.ord[data-ord="KWL-NOV 242"] [data-act="cancel"]');
  ok(await page.isVisible('#shRefund'), 'A20 cancelling a paid order asks how much money went back');
  rpcError = 'Write a short note for "Other".';
  await page.selectOption('#shWhy', 'Other'); await page.click('[data-go="cancel"]'); await page.waitForTimeout(250);
  ok((await page.textContent('#msg')).includes('Write a short note'), 'A21 the database message is shown when it refuses');
  await page.fill('#shNote', 'Wrong honey'); await page.fill('#shRefund', '1600'); await page.click('[data-go="cancel"]'); await page.waitForTimeout(200);
  c = calls.filter((x) => x.fn === 'mfm_cancel_dispatch_order').pop();
  ok(c && c.body.p_reason === 'Other' && c.body.p_note === 'Wrong honey' && c.body.p_refund_kes === 1600, 'A22 cancel through the existing function with reason, note and refund', c && c.body);
  // WhatsApp message
  await page.evaluate(() => { window.open = (u) => { window.__opened = u; }; });
  await page.click('.ord[data-ord="NRB-NOV 241"] [data-toggle]');
  await page.click('.ord[data-ord="NRB-NOV 241"] [data-act="wa"]');
  const wurl = decodeURIComponent(await page.evaluate(() => window.__opened || ''));
  ok(wurl.includes('wa.me/254722000111') && wurl.includes('NRB-NOV 241') && wurl.includes('KES 12,800') && wurl.includes('Till 9948037') && wurl.includes('honey wholesale, honeycomb retail'),
    'A23 WhatsApp to the customer with the groups, total and the Till number', wurl.slice(0, 240));
  ok(errors.length === 0, 'A24 no script errors', errors);
  // owner prices
  role = 'owner';
  const p2 = await ctx.newPage(); p2.on('dialog', (d) => d.accept());
  await p2.goto(base + '/honey-orders.html'); await p2.waitForSelector('#appView:not(.hidden)');
  ok(await p2.isVisible('#tabPrices'), 'A25 the owner sees Prices');
  await p2.click('#tabPrices'); await p2.waitForSelector('[data-slug="honeycomb"]');
  ok((await p2.textContent('#groupRows')).includes('Natural honeycomb (on its own)'), 'A26 two thresholds: extracted honey and honeycomb');
  await p2.fill('[data-slug="honeycomb"] .pr-r', '2300'); await p2.click('[data-slug="honeycomb"] [data-save]'); await p2.waitForTimeout(200);
  let c2 = calls.filter((x) => x.fn === 'mfm_honey_set_prices').pop();
  ok(c2 && c2.body.p_slug === 'honeycomb' && c2.body.p_retail === 2300 && c2.body.p_wholesale === 1500, 'A27 owner changes the honeycomb retail price', c2 && c2.body);
  await p2.fill('[data-group="honeycomb"] .g-min', '5'); await p2.click('[data-group="honeycomb"] [data-gsave]'); await p2.waitForTimeout(200);
  c2 = calls.filter((x) => x.fn === 'mfm_honey_set_group_min').pop();
  ok(c2 && c2.body.p_group === 'honeycomb' && c2.body.p_kg === 5, 'A28 owner changes the honeycomb wholesale minimum on its own', c2 && c2.body);
  await p2.setInputFiles('[data-slug="honeycomb"] .pd-file', { name: 'comb.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]) });
  await p2.fill('[data-slug="honeycomb"] .pd-desc', 'New words'); await p2.uncheck('[data-slug="honeycomb"] .pd-on');
  await p2.click('[data-slug="honeycomb"] [data-psave]'); await p2.waitForTimeout(400);
  c2 = calls.filter((x) => x.fn === 'mfm_honey_update_product').pop();
  ok(calls.some((x) => x.fn === 'upload' && x.body.includes('/honey-products/honeycomb-')) && c2 && /storage\/v1\/object\/public\/honey-products\/honeycomb-/.test(c2.body.p_image_url)
     && c2.body.p_description === 'New words' && c2.body.p_active === false, 'A29 owner uploads a new photo, edits the description and takes the product off sale', c2 && c2.body);
  await browser.close(); server.close();
  console.log((failed ? '# ' + failed + ' FAILED of ' : '# all ') + n + (failed ? '' : ' passed'));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('not ok - test crashed: ' + e.message); process.exit(1); });
