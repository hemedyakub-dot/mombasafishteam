# Database changes for the team app

Applied by hand to the shop database (Supabase project tcpqbrchpxpshmqprbkv).

| File | Applied | What |
|---|---|---|
| 2026-11-15_catchtrace_link.sql | 15 Nov 2026 | Stock received with a CatchTrace QR code (shop-admin.html). Additive only: new table `mfm_shop_trace_links`, new functions `add_shop_stock_traced`, `shop_trace_code_used`, `shop_trace_links_recent`, `shop_trace_coverage`. All owner-only. |
| 2026-11-15b_counter_traced.sql | 15 Nov 2026 | Counter POS: TRACED mark and TRACE QR screen (counter.html). Additive only: new function `shop_traced_now` (any shop staff; returns only what the public trace page shows). |

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
