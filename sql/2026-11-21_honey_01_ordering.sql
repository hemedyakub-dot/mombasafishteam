-- honey_01_ordering — MombasaFish honey self-service ordering (mombasafish.com/honey)
-- Asked for by Hemed, 21 Nov 2026 (master prompt "Honey self-service ordering portal").
--
-- A honey order is a normal shop order: it is created through mfm_place_order, so
-- it gets the same order number, tracking code, 72-hour duplicate flag, rate limit,
-- new-order email, Notion sync, order values and Dispatch / tracker handling as a
-- website fish order. The honey layer adds what fish orders do not have:
--   * mfm_honey_products   — the honey catalogue with retail and wholesale price per kg
--   * mfm_honey_orders     — per order: pricing applied (retail / wholesale), total kg,
--                            subtotal, delivery or pickup, town, address, email,
--                            confirmed / ready-for-collection marks
--   * mfm_honey_order_items — product, kg, unit price and line total at the time of order
-- Pricing rule (Hemed): all honey in one order counts together. 7 kg or more in total
-- -> wholesale price for every honey line; under 7 kg -> retail for every line.
-- The page sends only products and kg. The database works out every price; prices,
-- totals and the pricing category sent by a browser are ignored.
-- Delivery cost is not added: it is confirmed by the team (as for fish orders).
-- Nothing here changes existing tables, functions or the fish checkout.

-- ---------------------------------------------------------------- catalogue
create table public.mfm_honey_products (
  id                   smallint generated always as identity primary key,
  slug                 text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name                 text not null check (length(btrim(name)) between 2 and 80),
  swahili_name         text,
  description          text,
  image_url            text,
  retail_kes_per_kg    numeric(10,2) not null check (retail_kes_per_kg > 0),
  wholesale_kes_per_kg numeric(10,2) not null check (wholesale_kes_per_kg > 0),
  min_qty_kg           numeric(6,2) not null default 0.25 check (min_qty_kg > 0),
  step_kg              numeric(6,2) not null default 0.25 check (step_kg > 0),
  sort_order           smallint not null default 0,
  active               boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           text,
  constraint mfm_honey_products_wholesale_le_retail check (wholesale_kes_per_kg <= retail_kes_per_kg)
);
comment on table public.mfm_honey_products is 'Honey sold on mombasafish.com/honey. Prices per kg; wholesale applies to the whole order when all honey in it reaches app_settings honey_wholesale_min_kg.';

create table public.mfm_honey_price_history (
  id                   bigint generated always as identity primary key,
  product_id           smallint not null references public.mfm_honey_products (id),
  retail_kes_per_kg    numeric(10,2) not null,
  wholesale_kes_per_kg numeric(10,2) not null,
  changed_by           text not null,
  changed_at           timestamptz not null default now()
);
create index mfm_honey_price_history_product_idx on public.mfm_honey_price_history (product_id, changed_at);

insert into public.mfm_honey_products (slug, name, swahili_name, description, image_url, retail_kes_per_kg, wholesale_kes_per_kg, min_qty_kg, step_kg, sort_order, updated_by) values
 ('mangrove', 'Mangrove Honey', 'Asali ya Mikoko',
  'Dark, rich honey from the coastal mangrove forests of Kwale, gathered by community beekeepers. A deep flavour ordinary honey cannot match.',
  'images/asali-mikoko.jpg', 1800, 1200, 0.25, 0.25, 1, 'Hemed (master prompt 21 Nov 2026)'),
 ('wild-forest', 'Wild Forest Honey', 'Asali ya Msituni',
  'Golden honey from bees foraging the wild coastal forest and bush. Bright and floral, for the table, tea and cooking.',
  null, 1600, 1000, 0.25, 0.25, 2, 'Hemed (master prompt 21 Nov 2026)');
insert into public.mfm_honey_price_history (product_id, retail_kes_per_kg, wholesale_kes_per_kg, changed_by)
select id, retail_kes_per_kg, wholesale_kes_per_kg, updated_by from public.mfm_honey_products;

insert into public.app_settings (key, value) values ('honey_wholesale_min_kg', '7') on conflict (key) do nothing;

-- ------------------------------------------------------------------ orders
create table public.mfm_honey_orders (
  id                bigint generated always as identity primary key,
  order_number      text not null unique references public.mfm_orders (order_number) on update cascade,
  client_id         uuid not null unique,
  customer_email    text check (customer_email is null or customer_email ~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'),
  town              text not null check (length(btrim(town)) between 2 and 80),
  address           text not null check (length(btrim(address)) between 2 and 200),
  fulfilment        text not null check (fulfilment in ('delivery', 'pickup')),
  total_kg          numeric(8,2) not null check (total_kg > 0),
  pricing           text not null check (pricing in ('retail', 'wholesale')),
  wholesale_min_kg  numeric(8,2) not null,
  subtotal_kes      numeric(12,2) not null check (subtotal_kes > 0),
  delivery_kes      numeric(12,2) check (delivery_kes is null or delivery_kes >= 0),
  confirmed_at      timestamptz,
  confirmed_by      text,
  ready_at          timestamptz,
  ready_by          text,
  created_at        timestamptz not null default now()
);
comment on table public.mfm_honey_orders is 'The honey part of a shop order placed on mombasafish.com/honey: pricing applied at the time of order. Status, payment and dispatch live on mfm_orders as for every order.';
comment on column public.mfm_honey_orders.delivery_kes is 'Empty = delivery cost still to be confirmed by the team.';

create table public.mfm_honey_order_items (
  id               bigint generated always as identity primary key,
  honey_order_id   bigint not null references public.mfm_honey_orders (id),
  product_id       smallint not null references public.mfm_honey_products (id),
  product_name     text not null,
  qty_kg           numeric(8,2) not null check (qty_kg > 0),
  unit_kes_per_kg  numeric(10,2) not null check (unit_kes_per_kg > 0),
  line_kes         numeric(12,2) not null check (line_kes > 0),
  created_at       timestamptz not null default now(),
  unique (honey_order_id, product_id)
);
create index mfm_honey_order_items_product_idx on public.mfm_honey_order_items (product_id);

-- ------------------------------------------------------------- access rules
alter table public.mfm_honey_products enable row level security;
alter table public.mfm_honey_price_history enable row level security;
alter table public.mfm_honey_orders enable row level security;
alter table public.mfm_honey_order_items enable row level security;
revoke all on table public.mfm_honey_products, public.mfm_honey_price_history, public.mfm_honey_orders, public.mfm_honey_order_items
  from public, anon, authenticated;
-- staff read; all writes go through the functions below
grant select on table public.mfm_honey_products, public.mfm_honey_price_history, public.mfm_honey_orders, public.mfm_honey_order_items to authenticated;
create policy honey_products_staff_read on public.mfm_honey_products for select to authenticated using (public.mfm_is_staff());
create policy honey_price_history_staff_read on public.mfm_honey_price_history for select to authenticated using (public.mfm_is_staff());
create policy honey_orders_staff_read on public.mfm_honey_orders for select to authenticated using (public.mfm_is_staff());
create policy honey_order_items_staff_read on public.mfm_honey_order_items for select to authenticated using (public.mfm_is_staff());

-- ----------------------------------------------------------- helpers
create function public.mfm_honey_kes(p numeric) returns text
language sql immutable set search_path = '' as $$
  select case when p = trunc(p) then to_char(p, 'FM999,999,999,990') else to_char(p, 'FM999,999,999,990.00') end
$$;

create function public.mfm_honey_kg(p numeric) returns text
language sql immutable set search_path = '' as $$
  select rtrim(rtrim(to_char(p, 'FM999990.00'), '0'), '.')
$$;

-- The pricing engine. p_lines: [{"slug": "mangrove", "kg": 4}, ...]. Lines with 0 kg
-- are left out. Returns lines with unit prices and totals, and the category.
create function public.mfm_honey_price(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_min_total numeric := coalesce(nullif((select value from public.app_settings where key = 'honey_wholesale_min_kg'), '')::numeric, 7);
  l jsonb;
  v_slug text;
  v_kg numeric;
  p public.mfm_honey_products;
  v_seen text[] := '{}';
  v_items jsonb := '[]';
  v_total_kg numeric := 0;
  v_cat text;
  v_out jsonb := '[]';
  v_sub numeric := 0;
  v_unit numeric;
  v_line numeric;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Choose the honey you would like.' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_lines) > 10 then raise exception 'Too many lines in one order.' using errcode = 'P0001'; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    v_slug := l ->> 'slug';
    begin
      v_kg := (l ->> 'kg')::numeric;
    exception when others then
      raise exception 'Quantities are in kg, for example 0.25, 1 or 7.5.' using errcode = 'P0001';
    end;
    if v_kg is null or v_kg < 0 then raise exception 'Quantities are in kg, for example 0.25, 1 or 7.5.' using errcode = 'P0001'; end if;
    select * into p from public.mfm_honey_products where slug = v_slug and active;
    if p.id is null then raise exception 'That honey is not available.' using errcode = 'P0001'; end if;
    if v_slug = any (v_seen) then raise exception 'Each honey can appear once in an order.' using errcode = 'P0001'; end if;
    v_seen := v_seen || v_slug;
    continue when v_kg = 0;
    if v_kg < p.min_qty_kg then
      raise exception 'The smallest amount of % is % kg.', p.name, public.mfm_honey_kg(p.min_qty_kg) using errcode = 'P0001';
    end if;
    if mod(v_kg, p.step_kg) <> 0 then
      raise exception '% is sold in steps of % kg.', p.name, public.mfm_honey_kg(p.step_kg) using errcode = 'P0001';
    end if;
    if v_kg > 500 then raise exception 'For more than 500 kg of % please message us on WhatsApp.', p.name using errcode = 'P0001'; end if;
    v_total_kg := v_total_kg + v_kg;
    v_items := v_items || jsonb_build_object('id', p.id, 'slug', p.slug, 'name', p.name, 'swahili_name', p.swahili_name, 'kg', v_kg,
                                             'retail', p.retail_kes_per_kg, 'wholesale', p.wholesale_kes_per_kg, 'sort', p.sort_order);
  end loop;
  if v_total_kg = 0 then raise exception 'Choose at least one honey and how many kg.' using errcode = 'P0001'; end if;
  v_cat := case when v_total_kg >= v_min_total then 'wholesale' else 'retail' end;
  for l in select * from jsonb_array_elements(v_items) e order by (e ->> 'sort')::int loop
    v_unit := case v_cat when 'wholesale' then (l ->> 'wholesale')::numeric else (l ->> 'retail')::numeric end;
    v_line := round((l ->> 'kg')::numeric * v_unit, 2);
    v_sub := v_sub + v_line;
    v_out := v_out || jsonb_build_object('product_id', (l ->> 'id')::int, 'slug', l ->> 'slug', 'name', l ->> 'name', 'swahili_name', l ->> 'swahili_name',
                                         'kg', (l ->> 'kg')::numeric, 'unit_kes_per_kg', v_unit, 'line_kes', v_line);
  end loop;
  return jsonb_build_object('lines', v_out, 'total_kg', v_total_kg, 'pricing', v_cat, 'wholesale_min_kg', v_min_total,
                            'kg_to_wholesale', greatest(v_min_total - v_total_kg, 0), 'subtotal_kes', v_sub);
end $$;

-- ------------------------------------------------------ public: catalogue
create function public.mfm_honey_catalogue() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'wholesale_min_kg', coalesce(nullif((select value from public.app_settings where key = 'honey_wholesale_min_kg'), '')::numeric, 7),
    'products', coalesce((select jsonb_agg(jsonb_build_object('slug', slug, 'name', name, 'swahili_name', swahili_name, 'description', description,
                     'image_url', image_url, 'retail_kes_per_kg', retail_kes_per_kg, 'wholesale_kes_per_kg', wholesale_kes_per_kg,
                     'min_qty_kg', min_qty_kg, 'step_kg', step_kg) order by sort_order, id)
                   from public.mfm_honey_products where active), '[]'::jsonb))
$$;

-- ------------------------------------------------------ public: place an order
-- p: {client_id, name, phone, email, county, town, address, fulfilment, notes, source, lines:[{slug,kg}]}
create function public.mfm_honey_place_order(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_client uuid;
  v_prev public.mfm_honey_orders;
  v_q jsonb;
  v_name text := btrim(coalesce(p ->> 'name', ''));
  v_phone text := regexp_replace(coalesce(p ->> 'phone', ''), '[\s-]', '', 'g');
  v_email text := nullif(lower(btrim(coalesce(p ->> 'email', ''))), '');
  v_county text := btrim(coalesce(p ->> 'county', ''));
  v_town text := btrim(coalesce(p ->> 'town', ''));
  v_addr text := btrim(coalesce(p ->> 'address', ''));
  v_ful text := lower(btrim(coalesce(p ->> 'fulfilment', '')));
  v_note text := nullif(left(btrim(coalesce(p ->> 'notes', '')), 250), '');
  v_src text := nullif(left(regexp_replace(btrim(coalesce(p ->> 'source', '')), '[|\[\]]', '', 'g'), 120), '');
  v_items text;
  v_notes text;
  v_order text;
  v_code text;
  v_hid bigint;
  l jsonb;
begin
  begin
    v_client := (p ->> 'client_id')::uuid;
  exception when others then v_client := null;
  end;
  if v_client is null then raise exception 'Please reload the page and try again.' using errcode = 'P0001'; end if;
  -- the same submission sent twice (double tap, slow network) returns the first order
  perform pg_advisory_xact_lock(hashtext('mfm_honey_order:' || v_client::text));
  select * into v_prev from public.mfm_honey_orders where client_id = v_client;
  if v_prev.id is not null then
    return jsonb_build_object('order_number', v_prev.order_number, 'tracking_code', (select tracking_code from public.mfm_orders where order_number = v_prev.order_number),
      'pricing', v_prev.pricing, 'total_kg', v_prev.total_kg, 'subtotal_kes', v_prev.subtotal_kes, 'replayed', true);
  end if;

  if length(v_name) < 2 or length(v_name) > 80 then raise exception 'Please give the name for the order.' using errcode = 'P0001'; end if;
  if v_phone !~ '^(\+?254|0)[17][0-9]{8}$' then
    raise exception 'That phone number does not look right. Use 07xx xxx xxx or 01xx xxx xxx.' using errcode = 'P0001';
  end if;
  if v_email is not null and (length(v_email) > 120 or v_email !~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$') then
    raise exception 'That email address does not look right (or leave it empty).' using errcode = 'P0001';
  end if;
  if length(v_county) < 2 or length(v_county) > 60 then raise exception 'Please choose your county.' using errcode = 'P0001'; end if;
  if length(v_town) < 2 or length(v_town) > 80 then raise exception 'Please write your town or area.' using errcode = 'P0001'; end if;
  if v_ful not in ('delivery', 'pickup') then raise exception 'Choose delivery or pickup.' using errcode = 'P0001'; end if;
  if length(v_addr) < 2 or length(v_addr) > 200 then
    raise exception '%', case v_ful when 'pickup' then 'Write where you would like to collect the honey.' else 'Write the delivery address.' end using errcode = 'P0001';
  end if;

  v_q := public.mfm_honey_price(p -> 'lines');

  select string_agg(format('%s (%s) — %s kg — KES %s', x ->> 'name', x ->> 'swahili_name', public.mfm_honey_kg((x ->> 'kg')::numeric),
                           public.mfm_honey_kes((x ->> 'line_kes')::numeric)), '; ')
    into v_items from jsonb_array_elements(v_q -> 'lines') x;
  v_items := v_items || ' | Items total: KES ' || public.mfm_honey_kes((v_q ->> 'subtotal_kes')::numeric)
          || ' | Honey ' || (v_q ->> 'pricing') || ' price' || case when v_q ->> 'pricing' = 'wholesale'
               then ' (' || public.mfm_honey_kg((v_q ->> 'total_kg')::numeric) || ' kg in one order)' else '' end
          || ' | ' || case v_ful when 'pickup' then 'Customer collects' else 'Delivery cost to be confirmed' end
          || ' | Placed on honey page';
  v_notes := 'Honey order. ' || case v_ful when 'pickup' then 'Collect at: ' else 'Deliver to: ' end || v_addr || ', ' || v_town
          || coalesce('. Email: ' || v_email, '') || coalesce('. Customer note: ' || v_note, '');
  v_notes := left(replace(v_notes, 'via:', 'via -'), 400) || coalesce('  |  via: ' || v_src, '');

  select o.order_number, o.tracking_code into v_order, v_code
    from public.mfm_place_order(v_name, v_phone, v_county, v_items,
           case when v_ful = 'pickup' then 'pickup' when v_county ~* 'mombasa' then 'mombasa' else 'upcountry' end,
           v_town, v_notes) o;

  insert into public.mfm_honey_orders (order_number, client_id, customer_email, town, address, fulfilment, total_kg, pricing,
                                       wholesale_min_kg, subtotal_kes)
  values (v_order, v_client, v_email, v_town, v_addr, v_ful, (v_q ->> 'total_kg')::numeric, v_q ->> 'pricing',
          (v_q ->> 'wholesale_min_kg')::numeric, (v_q ->> 'subtotal_kes')::numeric)
  returning id into v_hid;
  for l in select * from jsonb_array_elements(v_q -> 'lines') loop
    insert into public.mfm_honey_order_items (honey_order_id, product_id, product_name, qty_kg, unit_kes_per_kg, line_kes)
    values (v_hid, (l ->> 'product_id')::smallint, l ->> 'name', (l ->> 'kg')::numeric, (l ->> 'unit_kes_per_kg')::numeric, (l ->> 'line_kes')::numeric);
  end loop;
  insert into public.mfm_order_events (order_number, event_type, to_value, actor_name, source, detail)
  values (v_order, 'honey_order_placed', v_q ->> 'pricing', 'customer', 'mfm_honey_place_order', v_q);

  return jsonb_build_object('order_number', v_order, 'tracking_code', v_code, 'pricing', v_q ->> 'pricing',
                            'total_kg', (v_q ->> 'total_kg')::numeric, 'subtotal_kes', (v_q ->> 'subtotal_kes')::numeric,
                            'lines', v_q -> 'lines', 'fulfilment', v_ful, 'replayed', false);
end $$;

-- ------------------------------------------------------------ staff: list
create function public.mfm_honey_require_staff() returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.mfm_is_staff() then raise exception 'Staff only.' using errcode = '42501'; end if;
  if not public.mfm_staff_code_ok() then raise exception 'Enter the 6-digit sign-in code from your email first.' using errcode = '42501'; end if;
  return coalesce((select full_name from public.mfm_staff where user_id = auth.uid()), 'staff');
end $$;

create function public.mfm_honey_status(o public.mfm_orders, h public.mfm_honey_orders) returns text
language sql stable set search_path = '' as $$
  select case when o.stage = -1 then 'cancelled'
              when o.stage = 4 then 'completed'
              when o.stage = 3 then 'dispatched'
              when o.stage = 2 and h.ready_at is not null then 'ready'
              when o.stage = 2 then 'processing'
              when o.payment_status = 'paid' or o.status = 'Prepaid' then 'paid'
              when h.confirmed_at is not null then 'awaiting_payment'
              else 'pending' end
$$;

create function public.mfm_honey_admin_orders(p_from date default null, p_to date default null, p_include_test boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.mfm_honey_require_staff();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'order_number', o.order_number, 'tracking_code', o.tracking_code, 'created_at', h.created_at,
      'customer_name', o.customer_name, 'phone', o.contact, 'email', h.customer_email, 'county', o.county, 'town', h.town,
      'address', h.address, 'fulfilment', h.fulfilment, 'total_kg', h.total_kg, 'pricing', h.pricing, 'subtotal_kes', h.subtotal_kes,
      'delivery_kes', h.delivery_kes, 'paid_kes', v.paid_kes, 'stage', o.stage, 'order_status', o.status, 'payment_status', o.payment_status,
      'status', public.mfm_honey_status(o, h), 'confirmed_at', h.confirmed_at, 'confirmed_by', h.confirmed_by, 'ready_at', h.ready_at,
      'cancel_reason', o.cancel_reason, 'cancel_note', o.cancel_note, 'notes', o.notes, 'duplicate_of', o.duplicate_of,
      'is_test', o.customer_name ~* '^test',
      'items', (select jsonb_agg(jsonb_build_object('product', i.product_name, 'slug', pr.slug, 'kg', i.qty_kg, 'unit_kes_per_kg', i.unit_kes_per_kg, 'line_kes', i.line_kes) order by pr.sort_order)
                  from public.mfm_honey_order_items i join public.mfm_honey_products pr on pr.id = i.product_id where i.honey_order_id = h.id))
      order by h.created_at desc)
    from public.mfm_honey_orders h
    join public.mfm_orders o on o.order_number = h.order_number
    left join public.mfm_order_values v on v.order_number = h.order_number
    where (p_from is null or (h.created_at at time zone 'Africa/Nairobi')::date >= p_from)
      and (p_to is null or (h.created_at at time zone 'Africa/Nairobi')::date <= p_to)
      and (p_include_test or o.customer_name !~* '^test')), '[]'::jsonb);
end $$;

-- ------------------------------------------------------ staff: honey steps
-- Payment, packing, dispatch, delivery and cancelling use the existing order
-- functions (mark_order_paid, set_stage, dispatch_order, mfm_cancel_dispatch_order),
-- so the Dispatch rules (emailed code, Mombasa check point) apply unchanged.
create function public.mfm_honey_confirm(p_order text, p_delivery_kes numeric default null) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_staff text := public.mfm_honey_require_staff();
  h public.mfm_honey_orders;
  o public.mfm_orders;
begin
  select * into h from public.mfm_honey_orders where order_number = p_order for update;
  if h.id is null then raise exception 'Honey order % not found.', p_order using errcode = 'P0001'; end if;
  select * into o from public.mfm_orders where order_number = p_order;
  if o.stage = -1 then raise exception 'Order % is cancelled.', p_order using errcode = 'P0001'; end if;
  if p_delivery_kes is not null and (p_delivery_kes < 0 or p_delivery_kes > 100000) then
    raise exception 'Delivery cost looks wrong.' using errcode = 'P0001';
  end if;
  update public.mfm_honey_orders set confirmed_at = coalesce(confirmed_at, now()), confirmed_by = coalesce(confirmed_by, v_staff),
         delivery_kes = coalesce(p_delivery_kes, delivery_kes)
   where id = h.id;
  insert into public.mfm_order_events (order_number, event_type, from_value, to_value, actor_uid, actor_name, source, detail)
  values (p_order, 'honey_confirmed', h.delivery_kes::text, coalesce(p_delivery_kes, h.delivery_kes)::text, auth.uid(), v_staff, 'mfm_honey_confirm',
          jsonb_build_object('delivery_kes', coalesce(p_delivery_kes, h.delivery_kes), 'subtotal_kes', h.subtotal_kes));
  return jsonb_build_object('order_number', p_order, 'confirmed', true, 'delivery_kes', coalesce(p_delivery_kes, h.delivery_kes),
                            'total_kes', h.subtotal_kes + coalesce(p_delivery_kes, h.delivery_kes, 0));
end $$;

create function public.mfm_honey_mark_ready(p_order text) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_staff text := public.mfm_honey_require_staff();
  h public.mfm_honey_orders;
  o public.mfm_orders;
begin
  select * into h from public.mfm_honey_orders where order_number = p_order for update;
  if h.id is null then raise exception 'Honey order % not found.', p_order using errcode = 'P0001'; end if;
  if h.fulfilment <> 'pickup' then raise exception 'Only pickup orders are made ready for collection.' using errcode = 'P0001'; end if;
  select * into o from public.mfm_orders where order_number = p_order for update;
  if o.stage not in (1, 2) then raise exception 'Order % is not waiting to be collected.', p_order using errcode = 'P0001'; end if;
  if not (o.payment_status = 'paid' or o.status = 'Prepaid') then raise exception 'Record the payment first.' using errcode = 'P0001'; end if;
  if o.stage = 1 then perform public.set_stage(p_order, 2::smallint); end if;
  update public.mfm_honey_orders set ready_at = now(), ready_by = v_staff where id = h.id;
  insert into public.mfm_order_events (order_number, event_type, to_value, actor_uid, actor_name, source)
  values (p_order, 'honey_ready_for_collection', 'ready', auth.uid(), v_staff, 'mfm_honey_mark_ready');
  return jsonb_build_object('order_number', p_order, 'ready', true);
end $$;

-- ------------------------------------------------------- owner: prices
create function public.mfm_honey_set_prices(p_slug text, p_retail numeric, p_wholesale numeric) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_staff text := public.mfm_honey_require_staff();
  p public.mfm_honey_products;
begin
  if not public.mfm_is_owner() then raise exception 'Only the owner can change honey prices.' using errcode = '42501'; end if;
  select * into p from public.mfm_honey_products where slug = p_slug for update;
  if p.id is null then raise exception 'Unknown honey.' using errcode = 'P0001'; end if;
  if p_retail is null or p_wholesale is null or p_retail <= 0 or p_wholesale <= 0 or p_retail > 100000 then
    raise exception 'Prices are KES per kg, more than 0.' using errcode = 'P0001';
  end if;
  if p_wholesale > p_retail then raise exception 'The wholesale price cannot be higher than retail.' using errcode = 'P0001'; end if;
  update public.mfm_honey_products set retail_kes_per_kg = p_retail, wholesale_kes_per_kg = p_wholesale, updated_at = now(), updated_by = v_staff where id = p.id;
  insert into public.mfm_honey_price_history (product_id, retail_kes_per_kg, wholesale_kes_per_kg, changed_by) values (p.id, p_retail, p_wholesale, v_staff);
  return jsonb_build_object('slug', p_slug, 'retail_kes_per_kg', p_retail, 'wholesale_kes_per_kg', p_wholesale);
end $$;

create function public.mfm_honey_set_wholesale_min(p_kg numeric) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_staff text := public.mfm_honey_require_staff();
begin
  if not public.mfm_is_owner() then raise exception 'Only the owner can change the wholesale minimum.' using errcode = '42501'; end if;
  if p_kg is null or p_kg < 0.25 or p_kg > 1000 then raise exception 'The wholesale minimum is in kg (0.25 to 1000).' using errcode = 'P0001'; end if;
  update public.app_settings set value = public.mfm_honey_kg(p_kg) where key = 'honey_wholesale_min_kg';
  return jsonb_build_object('wholesale_min_kg', p_kg, 'changed_by', v_staff);
end $$;

-- ------------------------------------------------------------ grants
revoke all on function public.mfm_honey_kes(numeric), public.mfm_honey_kg(numeric), public.mfm_honey_price(jsonb), public.mfm_honey_catalogue(),
  public.mfm_honey_place_order(jsonb), public.mfm_honey_require_staff(), public.mfm_honey_status(public.mfm_orders, public.mfm_honey_orders),
  public.mfm_honey_admin_orders(date, date, boolean), public.mfm_honey_confirm(text, numeric), public.mfm_honey_mark_ready(text),
  public.mfm_honey_set_prices(text, numeric, numeric), public.mfm_honey_set_wholesale_min(numeric) from public, anon, authenticated;
grant execute on function public.mfm_honey_catalogue(), public.mfm_honey_place_order(jsonb) to anon, authenticated;
grant execute on function public.mfm_honey_admin_orders(date, date, boolean), public.mfm_honey_confirm(text, numeric), public.mfm_honey_mark_ready(text),
  public.mfm_honey_set_prices(text, numeric, numeric), public.mfm_honey_set_wholesale_min(numeric) to authenticated;
