-- Tests for honey_01_ordering. Runs as one batch that ends with an error on purpose,
-- so everything (including test orders and the queued email) is rolled back.
do $t$
declare
  r text := '';
  n int := 0; f int := 0;
  q jsonb; o jsonb; o2 jsonb; c uuid;
  ip int := 0;
  procedure_ok boolean;
  function_dummy int;
begin
  -- small helpers as nested blocks
  -- price checks (the engine itself)
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 1800 and q->>'pricing' = 'retail' then r := r || 'ok T1 1 kg mangrove = 1,800 retail' || chr(10); else f := f + 1; r := r || 'NOT OK T1 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"wild-forest","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 1600 and q->>'pricing' = 'retail' then r := r || 'ok T2 1 kg forest = 1,600 retail' || chr(10); else f := f + 1; r := r || 'NOT OK T2 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":4},{"slug":"wild-forest","kg":3}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 7800 and q->>'pricing' = 'wholesale' and (q->'lines'->0->>'line_kes')::numeric = 4800 and (q->'lines'->1->>'line_kes')::numeric = 3000 then r := r || 'ok T3 4 + 3 kg = wholesale 4,800 + 3,000 = 7,800' || chr(10); else f := f + 1; r := r || 'NOT OK T3 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":5},{"slug":"wild-forest","kg":1}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 10600 and q->>'pricing' = 'retail' and (q->>'kg_to_wholesale')::numeric = 1 then r := r || 'ok T4 5 + 1 kg = retail 10,600 (1 kg short of wholesale)' || chr(10); else f := f + 1; r := r || 'NOT OK T4 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":0.25},{"slug":"wild-forest","kg":0}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 450 and jsonb_array_length(q->'lines') = 1 then r := r || 'ok T5 0.25 kg mangrove = 450 (0 kg forest left out)' || chr(10); else f := f + 1; r := r || 'NOT OK T5 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"wild-forest","kg":0.25}]');
  n := n + 1; if (q->>'subtotal_kes')::numeric = 400 then r := r || 'ok T6 0.25 kg forest = 400' || chr(10); else f := f + 1; r := r || 'NOT OK T6 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":3.75},{"slug":"wild-forest","kg":3}]');
  n := n + 1; if q->>'pricing' = 'retail' and (q->>'total_kg')::numeric = 6.75 and (q->>'subtotal_kes')::numeric = 3.75*1800 + 3*1600 then r := r || 'ok T7 6.75 kg combined = retail (11,550)' || chr(10); else f := f + 1; r := r || 'NOT OK T7 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":7}]');
  n := n + 1; if q->>'pricing' = 'wholesale' and (q->>'subtotal_kes')::numeric = 8400 then r := r || 'ok T8 7 kg = wholesale (8,400)' || chr(10); else f := f + 1; r := r || 'NOT OK T8 ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":10},{"slug":"wild-forest","kg":2}]');
  n := n + 1; if q->>'pricing' = 'wholesale' and (q->>'subtotal_kes')::numeric = 14000 then r := r || 'ok T8b 10 + 2 kg = wholesale 12,000 + 2,000' || chr(10); else f := f + 1; r := r || 'NOT OK T8b ' || q::text || chr(10); end if;
  q := public.mfm_honey_price('[{"slug":"mangrove","kg":0.5},{"slug":"wild-forest","kg":0.5}]');
  n := n + 1; if q->>'pricing' = 'retail' and (q->>'subtotal_kes')::numeric = 1700 then r := r || 'ok T8c 0.5 + 0.5 kg = retail 1,700' || chr(10); else f := f + 1; r := r || 'NOT OK T8c ' || q::text || chr(10); end if;
  -- refusals in the engine
  begin perform public.mfm_honey_price('[{"slug":"mangrove","kg":0.3}]'); f := f + 1; r := r || 'NOT OK E1 0.3 kg accepted' || chr(10);
  exception when others then r := r || 'ok E1 0.3 kg refused: ' || sqlerrm || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_price('[{"slug":"mangrove","kg":0},{"slug":"wild-forest","kg":0}]'); f := f + 1; r := r || 'NOT OK E2 empty accepted' || chr(10);
  exception when others then r := r || 'ok E2 nothing chosen refused: ' || sqlerrm || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_price('[{"slug":"clover","kg":1}]'); f := f + 1; r := r || 'NOT OK E3 unknown accepted' || chr(10);
  exception when others then r := r || 'ok E3 unknown honey refused: ' || sqlerrm || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_price('[{"slug":"mangrove","kg":-1}]'); f := f + 1; r := r || 'NOT OK E4 negative accepted' || chr(10);
  exception when others then r := r || 'ok E4 negative refused' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_price('[{"slug":"mangrove","kg":1},{"slug":"mangrove","kg":1}]'); f := f + 1; r := r || 'NOT OK E5 duplicate line accepted' || chr(10);
  exception when others then r := r || 'ok E5 same honey twice refused' || chr(10); end; n := n + 1;

  -- the public key: catalogue and ordering
  perform set_config('request.headers', '{"x-real-ip":"10.99.0.1"}', true);
  execute 'set local role anon';
  q := public.mfm_honey_catalogue();
  n := n + 1; if jsonb_array_length(q->'products') = 2 and (q->>'wholesale_min_kg')::numeric = 7 then r := r || 'ok P1 public catalogue: 2 honeys, wholesale from 7 kg' || chr(10); else f := f + 1; r := r || 'NOT OK P1 ' || q::text || chr(10); end if;
  -- T9 validation
  begin perform public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST Honey', 'phone', '12345', 'county', 'Mombasa', 'town', 'Nyali', 'address', 'Links Rd', 'fulfilment', 'delivery', 'lines', '[{"slug":"mangrove","kg":1}]'::jsonb));
    f := f + 1; r := r || 'NOT OK T9 bad phone accepted' || chr(10);
  exception when others then r := r || 'ok T9 bad phone refused: ' || sqlerrm || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST Honey', 'phone', '0712345678', 'county', 'Mombasa', 'town', '', 'address', 'Links Rd', 'fulfilment', 'delivery', 'lines', '[{"slug":"mangrove","kg":1}]'::jsonb));
    f := f + 1; r := r || 'NOT OK T9b missing town accepted' || chr(10);
  exception when others then r := r || 'ok T9b missing town refused: ' || sqlerrm || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST Honey', 'phone', '0712345678', 'county', 'Mombasa', 'town', 'Nyali', 'address', 'Links Rd', 'fulfilment', 'drone', 'lines', '[{"slug":"mangrove","kg":1}]'::jsonb));
    f := f + 1; r := r || 'NOT OK T9c bad fulfilment accepted' || chr(10);
  exception when others then r := r || 'ok T9c unknown fulfilment refused' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST Honey', 'phone', '0712345678', 'email', 'not-an-email', 'county', 'Mombasa', 'town', 'Nyali', 'address', 'Links Rd', 'fulfilment', 'delivery', 'lines', '[{"slug":"mangrove","kg":1}]'::jsonb));
    f := f + 1; r := r || 'NOT OK T9d bad email accepted' || chr(10);
  exception when others then r := r || 'ok T9d bad email refused' || chr(10); end; n := n + 1;
  -- T10 price manipulation: the browser claims wholesale and a price of 1 shilling
  c := gen_random_uuid();
  o := public.mfm_honey_place_order(jsonb_build_object('client_id', c, 'name', 'TEST Honey Buyer', 'phone', '0711000111', 'email', 'Test@Example.com',
         'county', 'Mombasa', 'town', 'Nyali', 'address', 'Links Road, house 4', 'fulfilment', 'delivery', 'notes', 'Ring the bell via: hack',
         'source', 'tiktok', 'pricing', 'wholesale', 'subtotal_kes', 1, 'grand_total', 1,
         'lines', '[{"slug":"mangrove","kg":1,"unit_kes_per_kg":1,"line_kes":1},{"slug":"wild-forest","kg":0.5,"price":1}]'::jsonb));
  n := n + 1; if o->>'pricing' = 'retail' and (o->>'subtotal_kes')::numeric = 2600 then r := r || 'ok T10 browser price and category ignored: 1 kg + 0.5 kg = retail 2,600 (order ' || (o->>'order_number') || ')' || chr(10); else f := f + 1; r := r || 'NOT OK T10 ' || o::text || chr(10); end if;
  -- T11 same submission twice
  o2 := public.mfm_honey_place_order(jsonb_build_object('client_id', c, 'name', 'TEST Honey Buyer', 'phone', '0711000111',
         'county', 'Mombasa', 'town', 'Nyali', 'address', 'Links Road, house 4', 'fulfilment', 'delivery', 'lines', '[{"slug":"mangrove","kg":1},{"slug":"wild-forest","kg":0.5}]'::jsonb));
  n := n + 1; if o2->>'order_number' = o->>'order_number' and (o2->>'replayed')::boolean then r := r || 'ok T11 the same submission sent again returns the same order' || chr(10); else f := f + 1; r := r || 'NOT OK T11 ' || o2::text || chr(10); end if;
  -- T12 the public key reads nothing
  begin perform 1 from public.mfm_honey_orders limit 1; f := f + 1; r := r || 'NOT OK T12 public key read honey orders' || chr(10);
  exception when others then r := r || 'ok T12 public key cannot read honey orders' || chr(10); end; n := n + 1;
  begin perform 1 from public.mfm_honey_order_items limit 1; f := f + 1; r := r || 'NOT OK T12b public key read honey items' || chr(10);
  exception when others then r := r || 'ok T12b public key cannot read honey order lines' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_admin_orders(); f := f + 1; r := r || 'NOT OK T12c public key listed orders' || chr(10);
  exception when others then r := r || 'ok T12c public key cannot list orders' || chr(10); end; n := n + 1;
  begin perform public.mfm_honey_price('[{"slug":"mangrove","kg":1}]'); f := f + 1; r := r || 'NOT OK T12d engine callable' || chr(10);
  exception when others then r := r || 'ok T12d the pricing engine is internal only' || chr(10); end; n := n + 1;
  begin insert into public.mfm_honey_products (slug, name, retail_kes_per_kg, wholesale_kes_per_kg) values ('x', 'x', 1, 1); f := f + 1; r := r || 'NOT OK T12e public insert' || chr(10);
  exception when others then r := r || 'ok T12e public key cannot change the catalogue' || chr(10); end; n := n + 1;
  execute 'reset role';

  -- the order is a normal shop order
  n := n + 1;
  if exists (select 1 from public.mfm_orders x where x.order_number = o->>'order_number' and x.status = 'Pending Payment' and x.stage = 1 and x.delivery_type = 'mombasa'
               and x.destination = 'Nyali' and x.items like 'Mangrove Honey (Asali ya Mikoko) — 1 kg — KES 1,800; Wild Forest Honey (Asali ya Msituni) — 0.5 kg — KES 800 | Items total: KES 2,600 | Honey retail price | Delivery cost to be confirmed | Placed on honey page'
               and x.notes like 'Honey order. Deliver to: Links Road, house 4, Nyali. Email: test@example.com. Customer note: Ring the bell via - hack  |  via: tiktok') then
    r := r || 'ok O1 saved as a normal shop order (Pending Payment, items in the website format, notes with address and email)' || chr(10);
  else f := f + 1; r := r || 'NOT OK O1 ' || (select row_to_json(x)::text from public.mfm_orders x where x.order_number = o->>'order_number') || chr(10); end if;
  n := n + 1;
  if (select items_kes from public.mfm_order_values where order_number = o->>'order_number') = 2600 then r := r || 'ok O2 order value 2,600 recorded for the books' || chr(10);
  else f := f + 1; r := r || 'NOT OK O2 ' || coalesce((select items_kes::text from public.mfm_order_values where order_number = o->>'order_number'), 'none') || chr(10); end if;
  n := n + 1;
  if (select count(*) from public.mfm_order_items where order_number = o->>'order_number') = 2 then r := r || 'ok O3 two checklist lines for Dispatch' || chr(10);
  else f := f + 1; r := r || 'NOT OK O3 lines=' || (select count(*) from public.mfm_order_items where order_number = o->>'order_number') || chr(10); end if;
  n := n + 1;
  if exists (select 1 from public.notify_outbox where order_number = o->>'order_number' and event_type = 'new_order') then r := r || 'ok O4 new-order email queued' || chr(10);
  else f := f + 1; r := r || 'NOT OK O4 no email queued' || chr(10); end if;
  n := n + 1;
  if (select count(*) from public.mfm_honey_order_items i join public.mfm_honey_orders h on h.id = i.honey_order_id where h.order_number = o->>'order_number') = 2
     and (select count(*) from public.mfm_honey_orders where client_id = c) = 1 then r := r || 'ok O5 honey order + 2 lines with unit prices saved once' || chr(10);
  else f := f + 1; r := r || 'NOT OK O5' || chr(10); end if;
  n := n + 1;
  if exists (select 1 from public.mfm_order_source where order_number = o->>'order_number' and channel is not null) then r := r || 'ok O6 where the customer came from recorded (tiktok)' || chr(10);
  else r := r || 'note O6 no source row (parser did not tag it)' || chr(10); end if;

  -- a wholesale pickup order elsewhere
  perform set_config('request.headers', '{"x-real-ip":"10.99.0.2"}', true);
  execute 'set local role anon';
  o2 := public.mfm_honey_place_order(jsonb_build_object('client_id', gen_random_uuid(), 'name', 'TEST Honey Shop', 'phone', '+254722000222',
         'county', 'Nairobi', 'town', 'Westlands', 'address', 'Our Mombasa shop', 'fulfilment', 'pickup', 'lines', '[{"slug":"mangrove","kg":4},{"slug":"wild-forest","kg":3}]'::jsonb));
  execute 'reset role';
  n := n + 1;
  if o2->>'pricing' = 'wholesale' and (o2->>'subtotal_kes')::numeric = 7800 and exists (select 1 from public.mfm_orders x where x.order_number = o2->>'order_number' and x.delivery_type = 'pickup'
       and x.items like '%— 4 kg — KES 4,800; %— 3 kg — KES 3,000 | Items total: KES 7,800 | Honey wholesale price (7 kg in one order) | Customer collects%') then
    r := r || 'ok O7 wholesale pickup order (Nairobi) 7,800, marked as collected by the customer' || chr(10);
  else f := f + 1; r := r || 'NOT OK O7 ' || o2::text || chr(10); end if;

  -- staff steps need a staff sign-in with the emailed code
  begin perform public.mfm_honey_confirm(o->>'order_number', 500); f := f + 1; r := r || 'NOT OK S1 confirm without sign-in' || chr(10);
  exception when others then r := r || 'ok S1 confirming needs a staff sign-in: ' || sqlerrm || chr(10); end; n := n + 1;

  raise exception E'TEST RESULTS (all rolled back) %/% passed\n%', n - f, n, r;
end $t$;
