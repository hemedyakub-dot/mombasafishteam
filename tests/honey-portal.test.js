// Browser test of mombasafish.com/honey (honey.html in the website repo). Runs offline:
// the shop database is replaced by answers worked out here with the same rule as the
// database (combined 7 kg -> wholesale). The database itself is tested by
// sql/test_honey_01.sql (rolled back on the live project).
// Usage: SITE=/path/to/mombasafish PLAYWRIGHT=/path/to/node_modules/playwright node tests/honey-portal.test.js
const path = require('path'), fs = require('fs'), http = require('http');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');
const SITE = path.resolve(process.env.SITE || path.join(__dirname, '..', '..', 'mombasafish'));
let n = 0, failed = 0;
const ok = (c, name, extra) => { n++; if (c) console.log('ok ' + n + ' - ' + name); else { failed++; console.log('not ok ' + n + ' - ' + name + (extra !== undefined ? '   # got: ' + JSON.stringify(extra) : '')); } };

const CAT = { wholesale_min_kg: 7, groups: [{ code: 'extracted_honey', label: 'Extracted honey', wholesale_min_kg: 7 }, { code: 'honeycomb', label: 'Natural honeycomb', wholesale_min_kg: 7 }], products: [
  { slug: 'mangrove', name: 'Mangrove Honey', swahili_name: 'Asali ya Mikoko', description: 'Dark, rich honey.', image_url: 'images/asali-mikoko.jpg', retail_kes_per_kg: 1800, wholesale_kes_per_kg: 1200, min_qty_kg: 0.25, step_kg: 0.25, pricing_group: 'extracted_honey', wholesale_min_kg: 7 },
  { slug: 'wild-forest', name: 'Wild Forest Honey', swahili_name: 'Asali ya Msituni', description: 'Golden honey.', image_url: null, retail_kes_per_kg: 1600, wholesale_kes_per_kg: 1000, min_qty_kg: 0.25, step_kg: 0.25, pricing_group: 'extracted_honey', wholesale_min_kg: 7 },
  { slug: 'honeycomb', name: 'Natural Honeycomb', swahili_name: 'Sega la Asali', description: 'Pure natural honey retained within its original beeswax comb.', image_url: 'images/honey-comb.jpg', retail_kes_per_kg: 2200, wholesale_kes_per_kg: 1500, min_qty_kg: 0.25, step_kg: 0.25, pricing_group: 'honeycomb', wholesale_min_kg: 7 }] };
function serverPrice(lines) {
  const prod = (l) => CAT.products.find((x) => x.slug === l.slug), gk = {}, groups = {};
  lines.forEach((l) => { const g = prod(l).pricing_group; gk[g] = (gk[g] || 0) + Number(l.kg); });
  Object.keys(gk).forEach((g) => { groups[g] = { kg: gk[g], pricing: gk[g] >= 7 ? 'wholesale' : 'retail' }; });
  const sub = lines.reduce((a, l) => { const p = prod(l); return a + Number(l.kg) * (groups[p.pricing_group].pricing === 'wholesale' ? p.wholesale_kes_per_kg : p.retail_kes_per_kg); }, 0);
  const cats = [...new Set(Object.values(groups).map((g) => g.pricing))];
  return { total_kg: Object.values(gk).reduce((a, b) => a + b, 0), pricing: cats.length === 1 ? cats[0] : 'mixed', groups, subtotal_kes: sub };
}

(async () => {
  const server = http.createServer((req, res) => {
    let u = decodeURIComponent(req.url.split('?')[0]); if (u === '/honey') u = '/honey.html';
    const f = path.join(SITE, u);
    if (!f.startsWith(SITE) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    const type = f.endsWith('.html') ? 'text/html' : f.endsWith('.css') ? 'text/css' : f.endsWith('.js') ? 'text/javascript' : f.endsWith('.jpg') ? 'image/jpeg' : 'application/octet-stream';
    res.writeHead(200, { 'content-type': type }); res.end(fs.readFileSync(f));
  }).listen(0);
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const calls = []; let mode = 'ok', catMode = 'ok', seq = 230;
  const errors = [];
  await ctx.route('https://fonts.googleapis.com/**', (r) => r.abort());
  await ctx.route('https://static.cloudflareinsights.com/**', (r) => r.abort());
  const json = (r, body, status) => r.fulfill({ status: status || 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  const seen = {};
  await ctx.route('https://tcpqbrchpxpshmqprbkv.supabase.co/**', async (r) => {
    const u = new URL(r.request().url());
    if (r.request().method() === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    const body = r.request().postData() ? JSON.parse(r.request().postData()) : null;
    calls.push({ path: u.pathname, body });
    if (u.pathname.endsWith('/mfm_honey_catalogue')) return catMode === 'ok' ? json(r, CAT) : r.abort();
    if (u.pathname.endsWith('/mfm_honey_place_order')) {
      if (mode === 'offline') return r.abort();
      if (mode === 'limit') return json(r, { message: 'That is several orders in a short time. Message us on WhatsApp 0787 668 888 and we will take it from there.' }, 400);
      await new Promise((res) => setTimeout(res, 300));
      const p = body.p, q = serverPrice(p.lines);
      if (!seen[p.client_id]) seen[p.client_id] = 'MSA-NOV ' + (++seq);
      return json(r, { order_number: seen[p.client_id], tracking_code: 'ABCDEFGH' + (seq % 10), ...q, fulfilment: p.fulfilment, replayed: false });
    }
    return json(r, {}, 404);
  });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_FAILED|net::/.test(m.text())) errors.push(m.text()); });
  await page.goto(base + '/honey');
  await page.waitForSelector('#card-mangrove');

  const txt = async (sel) => (await page.textContent(sel)).replace(/\s+/g, ' ').trim();
  const setKg = async (slug, v) => { await page.fill('#q-' + slug, String(v)); await page.dispatchEvent('#q-' + slug, 'change'); };
  const sum = async () => txt('#sumBody');

  // catalogue
  const c1 = await txt('#card-mangrove'), c2 = await txt('#card-wild-forest');
  ok(c1.includes('Mangrove Honey') && c1.includes('KES 1,800') && c1.includes('KES 1,200') && c1.includes('Minimum 0.25 kg'), 'H1 Mangrove card: retail 1,800, wholesale 1,200, minimum 0.25 kg', c1);
  ok(c2.includes('Wild Forest Honey') && c2.includes('KES 1,600') && c2.includes('KES 1,000'), 'H1b Wild Forest card: retail 1,600, wholesale 1,000', c2);
  ok((await page.getAttribute('#card-wild-forest img', 'src')) === 'images/honey-bee-flower.jpg', 'H1c Wild Forest uses the bee photo until it has its own');
  const c3 = await txt('#card-honeycomb');
  ok(c3.includes('Natural Honeycomb') && c3.includes('KES 2,200') && c3.includes('KES 1,500') && c3.includes('of honeycomb') && (await page.getAttribute('#card-honeycomb img', 'src')) === 'images/honey-comb.jpg',
    'H1f Honeycomb card: photo, retail 2,200, wholesale 1,500, its own 7 kg rule', c3);
  ok(c1.includes('Mangrove + Wild Forest together') && c1.includes('Order Mangrove Honey'), 'H1g extracted honey cards explain the shared rule and have an Order button');
  const coastBg = await page.$eval('.hy-band.coast', (e) => getComputedStyle(e).backgroundImage);
  ok(coastBg.includes('honey-comb-coast.jpg'), 'H1h the coastal honeycomb photo is a section background');
  ok((await txt('.hy-hero h1')).toUpperCase().includes('HONEY CATALOGUE') && (await txt('.hy-tag')) === 'Natural Honey. Coastal Heritage. Quality You Can Trust.' && await page.isVisible('#btnOrderNow'),
    'H1d landing: title, tagline and ORDER NOW');
  const heroBg = await page.$eval('.hy-hero', (e) => getComputedStyle(e).backgroundImage), bandBg = await page.$eval('.hy-band', (e) => getComputedStyle(e).backgroundImage);
  ok(heroBg.includes('honey-bees-flying.jpg') && bandBg.includes('honey-bee-flower.jpg'), 'H1e the two bee photos are the hero and section backgrounds');
  ok(!(await page.isVisible('#details')) && (await sum()).includes('No honey chosen'), 'H2 nothing chosen: no form yet');

  // T5 / T6 with the + buttons
  await page.click('#card-mangrove [data-d="1"]');
  ok((await page.inputValue('#q-mangrove')) === '0.25' && (await sum()).includes('KES 450'), 'T5 one tap on + = 0.25 kg Mangrove = KES 450', await sum());
  await page.click('#card-mangrove [data-d="-1"]');
  await page.click('#card-wild-forest [data-d="1"]');
  ok((await sum()).includes('KES 400') && !(await sum()).includes('Mangrove Honey'), 'T6 0.25 kg Wild Forest = KES 400 (Mangrove back to 0 and left out)', await sum());
  await setKg('wild-forest', 0);
  await setKg('mangrove', 1);
  ok((await sum()).includes('KES 1,800') && (await sum()).includes('Retail price'), 'T1 1 kg Mangrove = KES 1,800 retail');
  await setKg('mangrove', 0); await setKg('wild-forest', 1);
  ok((await sum()).includes('KES 1,600'), 'T2 1 kg Wild Forest = KES 1,600');
  await setKg('mangrove', 4); await setKg('wild-forest', 3);
  let s = await sum();
  ok(s.includes('KES 4,800') && s.includes('KES 3,000') && s.includes('KES 7,800') && s.includes('Wholesale price') && s.includes('Your combined extracted honey quantity qualifies for wholesale pricing at 7 kg.'),
    'T3 4 kg + 3 kg = wholesale 4,800 + 3,000 = KES 7,800 with the congratulations message', s);
  await setKg('mangrove', 5); await setKg('wild-forest', 1);
  s = await sum();
  ok(s.includes('KES 9,000') && s.includes('KES 1,600') && s.includes('KES 10,600') && s.includes('Retail price') && s.includes('Add 1 kg more Mangrove or Wild Forest honey to reach the 7 kg extracted honey wholesale price.'),
    'T4 5 kg + 1 kg = retail KES 10,600, with "add more honey" and 1 kg to go', s);
  await setKg('mangrove', 3.75); await setKg('wild-forest', 3);
  s = await sum();
  ok(s.includes('6.75 kg') && s.includes('Retail price') && s.includes('Add 0.25 kg more') && s.includes('KES 11,550'), 'T7 6.75 kg combined = retail (KES 11,550), 0.25 kg to go', s);
  await page.click('#card-mangrove [data-d="1"]');
  s = await sum();
  ok(s.includes('7 kg') && s.includes('Wholesale price') && s.includes('KES 7,800'), 'T8 one more tap to 7 kg: the whole order is recalculated at wholesale (4 × 1,200 + 3 × 1,000)', s);
  await setKg('mangrove', 10); await setKg('wild-forest', 2);
  ok((await sum()).includes('KES 14,000'), 'H3 10 kg + 2 kg = wholesale KES 14,000');
  // honeycomb on its own
  await setKg('mangrove', 0); await setKg('wild-forest', 0);
  await page.click('#card-honeycomb [data-add]');
  ok((await page.inputValue('#q-honeycomb')) === '0.25' && (await sum()).includes('KES 550'), 'C5 "Order Natural Honeycomb" adds 0.25 kg = KES 550', await sum());
  await setKg('honeycomb', 1); ok((await sum()).includes('KES 2,200'), 'C6 1 kg honeycomb = KES 2,200');
  await setKg('honeycomb', 6.75); s = await sum();
  ok(s.includes('KES 14,850') && s.includes('Add 0.25 kg more honeycomb'), 'C7 6.75 kg honeycomb = KES 14,850 retail, 0.25 kg to go', s);
  await setKg('honeycomb', 7); s = await sum();
  ok(s.includes('KES 10,500') && s.includes('Your honeycomb order qualifies for wholesale pricing at 7 kg.'), 'C8 7 kg honeycomb = KES 10,500 wholesale with its message', s);
  await setKg('honeycomb', 10); ok((await sum()).includes('KES 15,000'), 'C9 10 kg honeycomb = KES 15,000');
  // independent groups
  await setKg('mangrove', 2); await setKg('wild-forest', 1); await setKg('honeycomb', 4); s = await sum();
  ok(s.includes('KES 14,000') && !s.includes('qualifies') && (s.match(/Retail price/g) || []).length === 2, 'C10 3 kg extracted + 4 kg comb (7 kg in all): both stay retail, KES 14,000', s);
  await setKg('mangrove', 4); await setKg('wild-forest', 3); await setKg('honeycomb', 2); s = await sum();
  ok(s.includes('KES 12,200') && s.includes('Your combined extracted honey quantity qualifies') && s.includes('Add 5 kg more honeycomb'), 'C11 7 kg extracted + 2 kg comb: extracted wholesale, comb retail, KES 12,200', s);
  await setKg('mangrove', 3); await setKg('wild-forest', 0); await setKg('honeycomb', 7); s = await sum();
  ok(s.includes('KES 15,900') && s.includes('Your honeycomb order qualifies') && s.includes('Add 4 kg more Mangrove'), 'C12 3 kg extracted + 7 kg comb: extracted retail, comb wholesale, KES 15,900', s);
  await setKg('mangrove', 2); await setKg('wild-forest', 5); s = await sum();
  ok(s.includes('KES 17,900') && (s.match(/Wholesale price/g) || []).length === 2, 'C13 7 kg extracted + 7 kg comb: both wholesale, KES 17,900', s);
  ok(s.includes('Extracted honey (Mangrove + Wild Forest)') && s.includes('Natural honeycomb') && s.includes('Extracted honey combined'), 'C13b the summary shows the two groups separately', s);
  await setKg('honeycomb', 0);
  await setKg('mangrove', 0.5); await setKg('wild-forest', 0.5);
  ok((await sum()).includes('KES 1,700') && (await sum()).includes('Retail'), 'H4 0.5 kg + 0.5 kg = retail KES 1,700', await sum());
  // typed amounts
  await setKg('mangrove', '0.3');
  ok((await page.inputValue('#q-mangrove')) === '0.25', 'H5 a typed 0.3 kg becomes 0.25 kg (steps of 0.25)', await page.inputValue('#q-mangrove'));
  await setKg('mangrove', '0.1');
  ok((await page.inputValue('#q-mangrove')) === '0.25', 'H5b a typed 0.1 kg becomes the 0.25 kg minimum');
  await setKg('mangrove', '1,5');
  ok((await page.inputValue('#q-mangrove')) === '1.5', 'H5c "1,5" is read as 1.5 kg');
  await page.click('#card-mangrove [data-set="2"]');
  ok((await page.inputValue('#q-mangrove')) === '2', 'H5d quick button sets 2 kg');
  // sticky bar
  ok((await page.$eval('#sticky', (e) => e.classList.contains('show'))) && (await txt('#stTotal')) === 'KES 4,400', 'H6 the bar at the bottom of the phone shows the total (2 + 0.5 kg = 4,400)', await txt('#stTotal'));

  // T9 details form validation
  ok(await page.isVisible('#details'), 'H7 the details form appears once honey is chosen');
  await page.click('#btnReview');
  let e = await txt('#formErr');
  ok(e.includes('name') && e.includes('phone') && e.includes('county') && e.includes('town') && e.includes('delivery address'), 'T9 missing details are listed', e);
  await page.fill('#fName', 'TEST Asha'); await page.fill('#fPhone', '12345'); await page.selectOption('#fCounty', 'Mombasa'); await page.fill('#fTown', 'Nyali');
  await page.fill('#fAddr', 'Links Road, house 4'); await page.click('#btnReview');
  ok((await txt('#formErr')).includes('phone number does not look right') && (await page.getAttribute('#fPhone', 'aria-invalid')) === 'true', 'T9b an invalid phone number is refused');
  await page.fill('#fPhone', '0712 345 678'); await page.fill('#fEmail', 'nope'); await page.click('#btnReview');
  ok((await txt('#formErr')).includes('email'), 'T9c an invalid email is refused');
  await page.fill('#fEmail', 'asha@example.com');
  await page.click('label.hy-opt:has(input[value=pickup]) span');
  ok((await txt('#addrLbl')).includes('collect'), 'H8 pickup asks where to collect');
  await page.click('label.hy-opt:has(input[value=delivery]) span');
  await page.fill('#fNote', 'Call at the gate');
  await page.click('#btnReview');
  await page.waitForSelector('#review:not([hidden])');
  const rv = await txt('#review');
  ok(rv.includes('TEST Asha') && rv.includes('0712345678') && rv.includes('asha@example.com') && rv.includes('Mombasa') && rv.includes('Nyali') && rv.includes('Links Road, house 4')
     && rv.includes('Delivery') && rv.includes('To be confirmed') && rv.includes('KES 4,400') && rv.includes('Retail price') && rv.includes('Call at the gate'),
    'H9 review shows details, honey, retail status, delivery "to be confirmed" and the amount', rv);
  ok(await page.isDisabled('#btnPlace'), 'H10 "Place my order" waits for the confirmation tick');
  // changing quantity sends the customer back
  await setKg('wild-forest', 1); await setKg('honeycomb', 1);
  ok(!(await page.isVisible('#review')), 'H11 changing the honey after review goes back for a new review');
  await page.click('#btnReview'); await page.waitForSelector('#review:not([hidden])');
  // network failure then retry with the same client id
  mode = 'offline';
  await page.check('#fConfirm'); await page.click('#btnPlace');
  await page.waitForSelector('#revErr:not([hidden])');
  ok((await txt('#revErr')).includes('No connection') && (await txt('#revErr')).includes('WhatsApp'), 'H12 no connection: told to try again, with a WhatsApp fallback');
  mode = 'limit'; await page.click('#btnPlace'); await page.waitForTimeout(400);
  ok((await txt('#revErr')).includes('several orders in a short time'), 'H13 a message from the database is shown as it is');
  mode = 'ok';
  const before = calls.filter((c) => c.path.endsWith('place_order')).length;
  await page.evaluate(() => { const b = document.getElementById('btnPlace'); b.click(); b.click(); b.click(); });
  await page.waitForSelector('#done:not([hidden])');
  const placed = calls.filter((c) => c.path.endsWith('place_order'));
  ok(placed.length - before === 1, 'T11 three quick taps send one order', placed.length - before);
  const ids = new Set(placed.map((c) => c.body.p.client_id));
  ok(ids.size === 1, 'T11b every try of this order carries the same submission id (the database returns the first order)', [...ids]);
  const p = placed[placed.length - 1].body.p;
  ok(JSON.stringify(p.lines) === JSON.stringify([{ slug: 'mangrove', kg: 2 }, { slug: 'wild-forest', kg: 1 }, { slug: 'honeycomb', kg: 1 }]) && !('pricing' in p) && !('subtotal_kes' in p) && !JSON.stringify(p.lines).includes('price'),
    'T10 the page sends only honey and kg — no prices, totals or category for the database to trust', p);
  ok(p.name === 'TEST Asha' && p.phone === '0712345678' && p.county === 'Mombasa' && p.town === 'Nyali' && p.address === 'Links Road, house 4' && p.fulfilment === 'delivery' && p.email === 'asha@example.com' && p.notes === 'Call at the gate',
    'H14 details sent as typed', p);
  const dn = await txt('#done');
  ok(dn.includes('Thank you for ordering from MombasaFish!') && dn.includes('Your order has been received. Our team will contact you to confirm payment and fulfilment.')
     && (await txt('#doneRef')) === 'MSA-NOV 231' && dn.includes('KES 7,400') && dn.includes('extracted honey retail') && dn.includes('honeycomb retail'),
    'H15 confirmation: thank-you message, reference and amount (2 + 1 kg honey 5,200 + 1 kg comb 2,200 = 7,400)', dn);
  const wa = await page.getAttribute('#doneWa', 'href');
  ok(wa.startsWith('https://wa.me/254787668888') && decodeURIComponent(wa).includes('MSA-NOV 231'), 'H16 WhatsApp help link carries the order reference');
  ok((await page.getAttribute('#doneTrack', 'href')).includes('order=MSA-NOV%20231'), 'H16b tracking link opens this order');
  ok(!(await page.$eval('#sticky', (e) => e.classList.contains('show'))) && (await page.getAttribute('#sticky', 'aria-hidden')) === 'true', 'H17 the total bar goes away after ordering');
  await page.screenshot({ path: '/tmp/honey_done.png' });

  // remembered details + overflow + catalogue failure
  const p2 = await ctx.newPage();
  await p2.goto(base + '/honey'); await p2.waitForSelector('#card-mangrove');
  ok((await p2.inputValue('#fName')) === 'TEST Asha' && (await p2.inputValue('#fCounty')) === 'Mombasa', 'H18 details remembered on this phone for next time');
  const over = await p2.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  ok(over <= 0, 'H19 nothing sticks out sideways on a phone', over);
  await p2.screenshot({ path: '/tmp/honey_top.png' });
  await p2.click('#card-mangrove [data-set="5"]'); await p2.click('#card-wild-forest [data-set="2"]'); await p2.click('#card-honeycomb [data-set="2"]');
  await p2.evaluate(() => document.getElementById('card-honeycomb').scrollIntoView()); await p2.screenshot({ path: '/tmp/honey_comb_card.png' });
  await p2.evaluate(() => document.getElementById('summary').scrollIntoView());
  await p2.screenshot({ path: '/tmp/honey_summary.png' });
  catMode = 'down';
  const p3 = await ctx.newPage();
  await p3.goto(base + '/honey'); await p3.waitForTimeout(800);
  ok((await p3.textContent('#grid')).includes('could not load') && (await p3.$('#grid a[href*="wa.me"]')), 'H20 if prices cannot load, the page offers WhatsApp instead of wrong prices');
  ok(errors.length === 0, 'H21 no script errors', errors);

  await browser.close(); server.close();
  console.log((failed ? '# ' + failed + ' FAILED of ' : '# all ') + n + (failed ? '' : ' passed'));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('not ok - test crashed: ' + e.message); process.exit(1); });
