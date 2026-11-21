-- Tests for honey_02_honeycomb (run after the migration in one batch that ends with an
-- error on purpose, so everything is rolled back). Numbers follow the v2 brief, section 14.
do $t$
declare
  r text := ''; n int := 0; f int := 0;
  q jsonb; o jsonb; o2 jsonb; c uuid; x jsonb;
  staff_claims text := '{"sub":"a307a293-929e-48de-9929-44926708da08","role":"authenticated"}';
  owner_claims text := '{"sub":"5e85ed34-62b0-4fbf-9c16-2c415cb6c13b","role":"authenticated"}';
  procedure_check text;
begin
  -- helper: check one quote
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 1800 and q->>'extracted_pricing' = 'retail' then r := r || 'ok T1 1 kg Mangrove = 1,800' || chr(10); else f := f + 1; r := r || 'NOT OK T1 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"wild-forest","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 1600 then r := r || 'ok T2 1 kg Wild Forest = 1,600' || chr(10); else f := f + 1; r := r || 'NOT OK T2 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":4},{"slug":"wild-forest","kg":3}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 7800 and q->>'extracted_pricing' = 'wholesale' then r := r || 'ok T3 4 + 3 kg extracted = 7,800 wholesale' || chr(10); else f := f + 1; r := r || 'NOT OK T3 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":5},{"slug":"wild-forest","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 10600 and q->>'extracted_pricing' = 'retail' then r := r || 'ok T4 5 + 1 kg extracted = 10,600 retail' || chr(10); else f := f + 1; r := r || 'NOT OK T4 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"honeycomb","kg":0.25}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 550 and q->>'honeycomb_pricing' = 'retail' and q->>'extracted_pricing' is null then r := r || 'ok T5 0.25 kg honeycomb = 550' || chr(10); else f := f + 1; r := r || 'NOT OK T5 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"honeycomb","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 2200 then r := r || 'ok T6 1 kg honeycomb = 2,200' || chr(10); else f := f + 1; r := r || 'NOT OK T6 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"honeycomb","kg":6.75}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 14850 and q->>'honeycomb_pricing' = 'retail' and (q->'groups'->'honeycomb'->>'kg_to_wholesale')::numeric = 0.25 then r := r || 'ok T7 6.75 kg honeycomb = 14,850 retail (0.25 kg to wholesale)' || chr(10); else f := f + 1; r := r || 'NOT OK T7 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"honeycomb","kg":7}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 10500 and q->>'honeycomb_pricing' = 'wholesale' then r := r || 'ok T8 7 kg honeycomb = 10,500 wholesale' || chr(10); else f := f + 1; r := r || 'NOT OK T8 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"honeycomb","kg":10}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 15000 then r := r || 'ok T9 10 kg honeycomb = 15,000 wholesale' || chr(10); else f := f + 1; r := r || 'NOT OK T9 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":2},{"slug":"wild-forest","kg":1},{"slug":"honeycomb","kg":4}]');
  n := n + 1; if q->>'extracted_pricing' = 'retail' and q->>'honeycomb_pricing' = 'retail' and (q->>'subtotal_kes')::numeric = 3600 + 1600 + 8800 and (q->>'total_kg')::numeric = 7 then r := r || 'ok T10 3 kg extracted + 4 kg comb (7 kg in all) = both retail, 14,000' || chr(10); else f := f + 1; r := r || 'NOT OK T10 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":4},{"slug":"wild-forest","kg":3},{"slug":"honeycomb","kg":2}]');
  n := n + 1; if q->>'extracted_pricing' = 'wholesale' and q->>'honeycomb_pricing' = 'retail' and q->>'pricing' = 'mixed' and (q->>'subtotal_kes')::numeric = 7800 + 4400 then r := r || 'ok T11 7 kg extracted + 2 kg comb = extracted wholesale, comb retail (12,200, mixed)' || chr(10); else f := f + 1; r := r || 'NOT OK T11 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":3},{"slug":"honeycomb","kg":7}]');
  n := n + 1; if q->>'extracted_pricing' = 'retail' and q->>'honeycomb_pricing' = 'wholesale' and (q->>'subtotal_kes')::numeric = 5400 + 10500 then r := r || 'ok T12 3 kg extracted + 7 kg comb = extracted retail, comb wholesale (15,900)' || chr(10); else f := f + 1; r := r || 'NOT OK T12 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":2},{"slug":"wild-forest","kg":5},{"slug":"honeycomb","kg":7}]');
  n := n + 1; if q->>'extracted_pricing' = 'wholesale' and q->>'honeycomb_pricing' = 'wholesale' and q->>'pricing' = 'wholesale' and (q->>'subtotal_kes')::numeric = 2400 + 5000 + 10500 then r := r || 'ok T13 7 kg extracted + 7 kg comb = both wholesale (17,900)' || chr(10); else f := f + 1; r := r || 'NOT OK T13 ' || q || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":7},{"slug":"wild-forest","kg":0}]');
  n := n + 1; if q->>'extracted_pricing' = 'wholesale' and (q->>'subtotal_kes')::numeric = 8400 then r := r || 'ok T13b 7 kg Mangrove alone = wholesale 8,400' || chr(10); else f := f + 1; r := r || 'NOT OK T13b ' || q || chr(10); end if;
  begin perform public.mfm_honey_price('[{"slug":"honeycomb","kg":0.3}]'); f := f + 1; r := r || 'NOT OK E1' || chr(10);
  exception when others then r := r || 'ok E1 0.3 kg comb refused (steps of 0.25)' || chr(10); end; n := n + 1;

  -- public key
  perform set_config('request.headers', '{"x-real-ip":"10.99.2.1"}', true);
  execute 'set local role anon';
  x := public.mfm_honey_catalogue();
  n := n + 1; if jsonb_array_length(x->'products') = 3 and x->'products'->2->>'slug' = 'honeycomb' and x->'products'->2->>'pricing_group' = 'honeycomb'
     and (x->'products'->2->>'wholesale_min_kg')::numeric = 7 and jsonb_array_length(x->'groups') = 2 then r := r || 'ok P1 catalogue: 3 products, honeycomb in its own group (7 kg)' || chr(10); else f := f + 1; r := r || 'NOT OK P1 ' || x || chr(10); end if;
  begin perform public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST H', 'phone', '0712345678', 'county', 'Mombasa', 'town', 'Nyali', 'address', '', 'fulfilment', 'delivery', 'lines', '[{"slug":"honeycomb","kg":1}]'::jsonb));
    f := f + 1; r := r || 'NOT OK T15 missing address accepted' || chr(10);
  exception when others then r := r || 'ok T15 incomplete details refused: ' || sqlerrm || chr(10); end; n := n + 1;
  c := gen_random_uuid();
  o := public.mfm_honey_place_order(jsonb_build_object('client_id', c, 'name', 'TEST Honey V2', 'phone', '0711000666', 'county', 'Kilifi', 'town', 'Malindi', 'address', 'Casuarina Rd',
         'fulfilment', 'delivery', 'pricing', 'wholesale', 'subtotal_kes', 100, 'extracted_pricing', 'wholesale', 'honeycomb_pricing', 'wholesale',
         'lines', '[{"slug":"mangrove","kg":4,"unit_kes_per_kg":1},{"slug":"wild-forest","kg":3,"line_kes":1},{"slug":"honeycomb","kg":2,"unit_kes_per_kg":1500}]'::jsonb));
  n := n + 1; if (o->>'subtotal_kes')::numeric = 12200 and o->>'pricing' = 'mixed' and o->'groups'->'honeycomb'->>'pricing' = 'retail' then r := r || 'ok T14 browser prices and categories ignored: 12,200 (extracted wholesale, comb retail at 2,200) ' || (o->>'order_number') || chr(10); else f := f + 1; r := r || 'NOT OK T14 ' || o || chr(10); end if;
  o2 := public.mfm_honey_place_order(jsonb_build_object('client_id', c, 'name', 'TEST Honey V2', 'phone', '0711000666', 'county', 'Kilifi', 'town', 'Malindi', 'address', 'Casuarina Rd', 'fulfilment', 'delivery', 'lines', '[{"slug":"honeycomb","kg":9}]'::jsonb));
  n := n + 1; if o2->>'order_number' = o->>'order_number' and (o2->>'replayed')::boolean and (o2->>'subtotal_kes')::numeric = 12200 then r := r || 'ok T16 the same submission again returns the first order' || chr(10); else f := f + 1; r := r || 'NOT OK T16 ' || o2 || chr(10); end if;
  begin perform 1 from public.mfm_honey_orders limit 1; f := f + 1; r := r || 'NOT OK T17' || chr(10); exception when others then r := r || 'ok T17 public key cannot read orders' || chr(10); end; n := n + 1;
  begin perform 1 from public.mfm_honey_price_groups limit 1; f := f + 1; r := r || 'NOT OK T17b' || chr(10); exception when others then r := r || 'ok T17b public key cannot read the group table' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_admin_products(); f := f + 1; r := r || 'NOT OK T17c' || chr(10); exception when others then r := r || 'ok T17c public key cannot use product admin' || chr(10); end; n := n + 1;
  execute 'reset role';
  n := n + 1;
  if exists (select 1 from public.mfm_orders x where x.order_number = o->>'order_number'
     and x.items = 'Mangrove Honey (Asali ya Mikoko) — 4 kg — KES 4,800; Wild Forest Honey (Asali ya Msituni) — 3 kg — KES 3,000; Natural Honeycomb (Sega la Asali) — 2 kg — KES 4,400 | Items total: KES 12,200 | Honey prices: Extracted honey wholesale (7 kg), Natural honeycomb retail (2 kg) | Delivery cost to be confirmed | Placed on honey page')
  then r := r || 'ok O1 shop order lists both groups and their prices (Dispatch, email, books)' || chr(10);
  else f := f + 1; r := r || 'NOT OK O1 ' || (select items from public.mfm_orders x where x.order_number = o->>'order_number') || chr(10); end if;
  n := n + 1;
  if exists (select 1 from public.mfm_honey_orders h where h.order_number = o->>'order_number' and h.extracted_kg = 7 and h.extracted_pricing = 'wholesale' and h.honeycomb_kg = 2 and h.honeycomb_pricing = 'retail' and h.pricing = 'mixed')
     and (select count(*) from public.mfm_honey_order_items i join public.mfm_honey_orders h on h.id = i.honey_order_id where h.order_number = o->>'order_number' and i.pricing_group is not null and i.pricing is not null) = 3
  then r := r || 'ok O2 honey order keeps each group''s kg and pricing; 3 lines with group and price' || chr(10); else f := f + 1; r := r || 'NOT OK O2' || chr(10); end if;
  n := n + 1;
  if (select items_kes from public.mfm_order_values where order_number = o->>'order_number') = 12200 and exists (select 1 from public.notify_outbox where order_number = o->>'order_number')
  then r := r || 'ok O3 order value 12,200 for the books; new-order email queued' || chr(10); else f := f + 1; r := r || 'NOT OK O3' || chr(10); end if;
  n := n + 1;
  if exists (select 1 from public.mfm_honey_orders where extracted_pricing is null and honeycomb_pricing is null) then f := f + 1; r := r || 'NOT OK O4 older orders not carried over' || chr(10); else r := r || 'ok O4 every honey order has its group pricing' || chr(10); end if;

  -- staff and owner
  update public.app_settings set value = 'false' where key = 'dispatch_code_required';   -- stands in for an entered code
  perform set_config('request.jwt.claims', staff_claims, true);
  execute 'set local role authenticated';
  x := public.mfm_honey_admin_orders(null, null, true);
  select e into x from jsonb_array_elements(x) e where e->>'order_number' = o->>'order_number';
  n := n + 1; if x->>'honeycomb_pricing' = 'retail' and x->>'extracted_pricing' = 'wholesale' and x->'items'->2->>'pricing_group' = 'honeycomb' then r := r || 'ok S1 staff list shows each group''s pricing and line groups' || chr(10); else f := f + 1; r := r || 'NOT OK S1 ' || coalesce(x::text,'') || chr(10); end if;
  begin perform public.mfm_honey_update_product('honeycomb', 'Comb', null, null, null, 0.25, true); f := f + 1; r := r || 'NOT OK S2 staff edited product' || chr(10);
  exception when others then r := r || 'ok S2 staff cannot edit products' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_set_group_min('honeycomb', 5); f := f + 1; r := r || 'NOT OK S3' || chr(10);
  exception when others then r := r || 'ok S3 staff cannot change thresholds' || chr(10); end; n := n + 1;
  execute 'reset role';
  perform set_config('request.jwt.claims', owner_claims, true);
  execute 'set local role authenticated';
  perform public.mfm_honey_set_group_min('honeycomb', 5);
  execute 'reset role';
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":3},{"slug":"honeycomb","kg":5}]');
  n := n + 1; if q->>'honeycomb_pricing' = 'wholesale' and q->>'extracted_pricing' = 'retail' then r := r || 'ok S4 owner sets honeycomb wholesale to 5 kg: 5 kg comb now wholesale, extracted unchanged' || chr(10); else f := f + 1; r := r || 'NOT OK S4 ' || q || chr(10); end if;
  n := n + 1; if (select honeycomb_pricing from public.mfm_honey_orders where order_number = o->>'order_number') = 'retail' and (select subtotal_kes from public.mfm_honey_orders where order_number = o->>'order_number') = 12200 then r := r || 'ok S5 the order already placed keeps its prices' || chr(10); else f := f + 1; r := r || 'NOT OK S5' || chr(10); end if;
  execute 'set local role authenticated';
  perform public.mfm_honey_update_product('honeycomb', 'Natural Honeycomb', 'Sega la Asali', 'Pure natural honey retained within its original beeswax comb.', 'https://tcpqbrchpxpshmqprbkv.supabase.co/storage/v1/object/public/honey-products/comb.jpg', 0.5, true);
  execute 'reset role';
  begin perform public.mfm_honey_price('[{"slug":"honeycomb","kg":0.25}]'); f := f + 1; r := r || 'NOT OK S6 new minimum ignored' || chr(10);
  exception when others then r := r || 'ok S6 owner raises the comb minimum to 0.5 kg: 0.25 kg refused: ' || sqlerrm || chr(10); end; n := n + 1;
  execute 'set local role authenticated';
  begin perform public.mfm_honey_update_product('honeycomb', 'Natural Honeycomb', null, null, 'javascript:alert(1)', 0.5, true); f := f + 1; r := r || 'NOT OK S7 bad link' || chr(10);
  exception when others then r := r || 'ok S7 a photo must be an https link or a website path' || chr(10); end; n := n + 1;
  perform public.mfm_honey_update_product('wild-forest', 'Wild Forest Honey', 'Asali ya Msituni', null, null, 0.25, false);
  n := n + 1; if jsonb_array_length(public.mfm_honey_catalogue()->'products') = 2 then r := r || 'ok S8 owner takes a product off sale: it leaves the catalogue' || chr(10); else f := f + 1; r := r || 'NOT OK S8' || chr(10); end if;
  execute 'reset role';
  begin perform public.mfm_honey_price('[{"slug":"wild-forest","kg":1}]'); f := f + 1; r := r || 'NOT OK S9' || chr(10);
  exception when others then r := r || 'ok S9 and cannot be ordered: ' || sqlerrm || chr(10); end; n := n + 1;
  n := n + 1; if (select count(*) from public.mfm_honey_group_history where group_code = 'honeycomb') = 2 and (select count(*) from public.mfm_honey_product_history) = 2 then r := r || 'ok S10 threshold and product changes are logged' || chr(10); else f := f + 1; r := r || 'NOT OK S10' || chr(10); end if;
  raise exception E'V2 TEST RESULTS (all rolled back) %/% passed\n%', n - f, n, r;
end $t$;
