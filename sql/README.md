# Database changes for the team app

Applied by hand to the shop database (Supabase project tcpqbrchpxpshmqprbkv).

| File | Applied | What |
|---|---|---|
| 2026-11-15_catchtrace_link.sql | 15 Nov 2026 | Stock received with a CatchTrace QR code (shop-admin.html). Additive only: new table `mfm_shop_trace_links`, new functions `add_shop_stock_traced`, `shop_trace_code_used`, `shop_trace_links_recent`, `shop_trace_coverage`. All owner-only. |
| 2026-11-15b_counter_traced.sql | 15 Nov 2026 | Counter POS: TRACED mark and TRACE QR screen (counter.html). Additive only: new function `shop_traced_now` (any shop staff; returns only what the public trace page shows). |
| 2026-11-21_honey_01_ordering.sql | 21 Nov 2026 | Honey self-service ordering (mombasafish.com/honey). Additive: `mfm_honey_products`, `mfm_honey_price_history`, `mfm_honey_orders`, `mfm_honey_order_items`; public `mfm_honey_catalogue`, `mfm_honey_place_order` (prices worked out in the database; creates a normal shop order through `mfm_place_order`); staff `mfm_honey_admin_orders`, `mfm_honey_confirm`, `mfm_honey_mark_ready`; owner `mfm_honey_set_prices`. |
| 2026-11-21_honey_02_honeycomb.sql | 21 Nov 2026 | Version 2.0: Natural Honeycomb; two pricing groups that qualify for wholesale separately (`mfm_honey_price_groups`, 7 kg each); group and price kept on every order and line; owner product management (`mfm_honey_admin_products`, `mfm_honey_update_product`, `mfm_honey_set_group_min`), `mfm_honey_product_history`, `mfm_honey_group_history`; public photo bucket `honey-products` (owner + emailed code to upload). |

Honey tests: `sql/test_honey_01.sql` and `sql/test_honey_02.sql` run with the migration in ONE batch that ends with a deliberate error, so the live database rolls everything back (29 + 18 + 35 checks passed on 21 Nov 2026); `tests/honey-portal.test.js` (56, offline) and `tests/honey-orders.test.js` (35, offline).

Tests (local only, never against the live database):
- `sql/test_catchtrace_link.sh`: 27 tests of the functions, on a local copy of the live definitions
- `tests/shop-admin-catchtrace.test.js`: 16 browser tests of Shop Admin, offline
- `tests/staff-label-catchtrace.test.js`: 6 browser tests of the CatchTrace QR on the delivery label (Dispatch), offline
- `tests/counter-catchtrace.test.js`: 7 browser tests of the Counter (the QR code is decoded and checked), offline

To undo the CatchTrace link (only with the owner's say-so; it deletes the link records, not the stock):
```sql
drop function public.shop_traced_now();
drop function public.shop_trace_coverage(integer);
drop function public.shop_trace_links_recent(integer);
drop function public.shop_trace_code_used(text);
drop function public.add_shop_stock_traced(bigint, numeric, text, text, text, text, jsonb, boolean);
drop table public.mfm_shop_trace_links;
```
