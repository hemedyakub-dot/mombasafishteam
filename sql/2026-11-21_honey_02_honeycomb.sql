-- honey_02_honeycomb — Version 2.0 of the honey ordering portal (Hemed, 21 Nov 2026):
-- three products in two pricing groups that qualify for wholesale separately.
--   * extracted_honey: Mangrove + Wild Forest together; 7 kg or more of the two -> wholesale for both
--   * honeycomb:       Natural Honeycomb on its own;    7 kg or more of comb    -> wholesale for comb
-- Extracted honey and honeycomb are never added together to qualify.
-- Also: owner product management (name, description, photo, minimum, on/off, thresholds),
-- a public bucket for product photos that only the owner can write, and the pricing group
-- recorded on every order and order line so later price or threshold changes never alter
-- past orders. Replaces mfm_honey_price, mfm_honey_catalogue, mfm_honey_place_order and
-- mfm_honey_admin_orders (same signatures); the fish checkout is not touched.

-- ------------------------------------------------------------ pricing groups
create table public.mfm_honey_price_groups (
  code             text primary key check (code in ('extracted_honey', 'honeycomb')),
  label            text not null,
  wholesale_min_kg numeric(8,2) not null check (wholesale_min_kg >= 0.25 and wholesale_min_kg <= 1000),
  sort_order       smallint not null default 0,
  updated_at       timestamptz not null default now(),
  updated_by       text
);
insert into public.mfm_honey_price_groups (code, label, wholesale_min_kg, sort_order, updated_by) values
  ('extracted_honey', 'Extracted honey', coalesce(nullif((select value from public.app_settings where key = 'honey_wholesale_min_kg'), '')::numeric, 7), 1, 'Hemed (master prompt v2, 21 Nov 2026)'),
  ('honeycomb', 'Natural honeycomb', 7, 2, 'Hemed (master prompt v2, 21 Nov 2026)');
alter table public.mfm_honey_price_groups enable row level security;
revoke all on table public.mfm_honey_price_groups from public, anon, authenticated;
grant select on table public.mfm_honey_price_groups to authenticated;
create policy honey_price_groups_staff_read on public.mfm_honey_price_groups for select to authenticated using (public.mfm_is_staff());
create table public.mfm_honey_group_history (
  id bigint generated always as identity primary key,
  group_code text not null references public.mfm_honey_price_groups (code),
  wholesale_min_kg numeric(8,2) not null,
  changed_by text not null,
  changed_at timestamptz not null default now()
);
alter table public.mfm_honey_group_history enable row level security;
revoke all on table public.mfm_honey_group_history from public, anon, authenticated;
grant select on table public.mfm_honey_group_history to authenticated;
create policy honey_group_history_staff_read on public.mfm_honey_group_history for select to authenticated using (public.mfm_is_staff());
insert into public.mfm_honey_group_history (group_code, wholesale_min_kg, changed_by) select code, wholesale_min_kg, updated_by from public.mfm_honey_price_groups;
update public.app_settings set value = 'see mfm_honey_price_groups' where key = 'honey_wholesale_min_kg';

-- ------------------------------------------------------------ products
alter table public.mfm_honey_products add column pricing_group text not null default 'extracted_honey' references public.mfm_honey_price_groups (code);
create index mfm_honey_products_group_idx on public.mfm_honey_products (pricing_group);
alter table public.mfm_honey_products alter column pricing_group drop default;
update public.mfm_honey_products set description = 'Naturally sourced honey from coastal mangrove ecosystems, bringing the distinctive character of Kenya''s coastal environment.', updated_at = now() where slug = 'mangrove';
update public.mfm_honey_products set description = 'Natural honey sourced from forest and terrestrial flowering landscapes.', updated_at = now() where slug = 'wild-forest';
insert into public.mfm_honey_products (slug, name, swahili_name, description, image_url, retail_kes_per_kg, wholesale_kes_per_kg, min_qty_kg, step_kg, sort_order, pricing_group, updated_by)
values ('honeycomb', 'Natural Honeycomb', 'Sega la Asali', 'Pure natural honey retained within its original beeswax comb. Enjoy honey in its natural comb structure.',
        'images/honey-comb.jpg', 2200, 1500, 0.25, 0.25, 3, 'honeycomb', 'Hemed (master prompt v2, 21 Nov 2026)');
insert into public.mfm_honey_price_history (product_id, retail_kes_per_kg, wholesale_kes_per_kg, changed_by)
select id, retail_kes_per_kg, wholesale_kes_per_kg, updated_by from public.mfm_honey_products where slug = 'honeycomb';

-- ------------------------------------------------------------ orders keep their groups
alter table public.mfm_honey_orders drop constraint mfm_honey_orders_pricing_check;
alter table public.mfm_honey_orders add constraint mfm_honey_orders_pricing_check check (pricing in ('retail', 'wholesale', 'mixed'));
alter table public.mfm_honey_orders
  add column extracted_kg numeric(8,2) not null default 0 check (extracted_kg >= 0),
  add column extracted_pricing text check (extracted_pricing in ('retail', 'wholesale')),
  add column honeycomb_kg numeric(8,2) not null default 0 check (honeycomb_kg >= 0),
  add column honeycomb_pricing text check (honeycomb_pricing in ('retail', 'wholesale')),
  add column groups jsonb;
comment on column public.mfm_honey_orders.pricing is 'retail / wholesale when every pricing group in the order got the same; mixed when extracted honey and honeycomb got different prices.';
comment on column public.mfm_honey_orders.groups is 'Per pricing group at the time of order: kg, pricing, wholesale minimum, subtotal.';
update public.mfm_honey_orders set extracted_kg = total_kg, extracted_pricing = pricing where extracted_pricing is null;
alter table public.mfm_honey_order_items
  add column pricing_group text references public.mfm_honey_price_groups (code),
  add column pricing text check (pricing in ('retail', 'wholesale'));
update public.mfm_honey_order_items i set pricing_group = 'extracted_honey', pricing = h.pricing from public.mfm_honey_orders h where h.id = i.honey_order_id and i.pricing_group is null;
create index mfm_honey_order_items_group_idx on public.mfm_honey_order_items (pricing_group);

-- ------------------------------------------------------------ the pricing engine
create or replace function public.mfm_honey_price(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  l jsonb;
  v_slug text;
  v_kg numeric;
  p public.mfm_honey_products;
  v_seen text[] := '{}';
  v_items jsonb := '[]';
  v_lines jsonb;
  v_groups jsonb;
  v_sub numeric;
  v_total numeric;
  v_cats text[];
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
    v_items := v_items || jsonb_build_object('id', p.id, 'slug', p.slug, 'name', p.name, 'swahili_name', p.swahili_name, 'kg', v_kg,
      'retail', p.retail_kes_per_kg, 'wholesale', p.wholesale_kes_per_kg, 'sort', p.sort_order, 'grp', p.pricing_group);
  end loop;
  if jsonb_array_length(v_items) = 0 then raise exception 'Choose at least one honey and how many kg.' using errcode = 'P0001'; end if;

  -- each pricing group qualifies on its own kilograms only
  with i as (
    select x.*, g.wholesale_min_kg, g.label, g.sort_order as gsort, sum(x.kg) over (partition by x.grp) as gkg
    from jsonb_to_recordset(v_items) as x(id int, slug text, name text, swahili_name text, kg numeric, retail numeric, wholesale numeric, sort int, grp text)
    join public.mfm_honey_price_groups g on g.code = x.grp
  ), priced as (
    select i.*, case when i.gkg >= i.wholesale_min_kg then 'wholesale' else 'retail' end as cat,
           case when i.gkg >= i.wholesale_min_kg then i.wholesale else i.retail end as unit
    from i
  )
  select
    (select jsonb_agg(jsonb_build_object('product_id', id, 'slug', slug, 'name', name, 'swahili_name', swahili_name, 'kg', kg,
              'unit_kes_per_kg', unit, 'line_kes', round(kg * unit, 2), 'pricing_group', grp, 'pricing', cat) order by gsort, sort) from priced),
    (select jsonb_object_agg(grp, jsonb_build_object('label', label, 'kg', gkg, 'pricing', cat, 'wholesale_min_kg', wholesale_min_kg,
              'kg_to_wholesale', greatest(wholesale_min_kg - gkg, 0), 'subtotal_kes', sub))
       from (select grp, label, gkg, cat, wholesale_min_kg, sum(round(kg * unit, 2)) sub from priced group by grp, label, gkg, cat, wholesale_min_kg) s),
    (select sum(round(kg * unit, 2)) from priced),
    (select sum(kg) from priced),
    (select array_agg(distinct cat) from priced)
  into v_lines, v_groups, v_sub, v_total, v_cats;

  return jsonb_build_object('lines', v_lines, 'groups', v_groups, 'total_kg', v_total,
    'pricing', case when cardinality(v_cats) = 1 then v_cats[1] else 'mixed' end,
    'extracted_kg', coalesce((v_groups -> 'extracted_honey' ->> 'kg')::numeric, 0), 'extracted_pricing', v_groups -> 'extracted_honey' ->> 'pricing',
    'honeycomb_kg', coalesce((v_groups -> 'honeycomb' ->> 'kg')::numeric, 0), 'honeycomb_pricing', v_groups -> 'honeycomb' ->> 'pricing',
    'subtotal_kes', v_sub);
end $$;

-- ------------------------------------------------------------ public catalogue
create or replace function public.mfm_honey_catalogue() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'wholesale_min_kg', (select wholesale_min_kg from public.mfm_honey_price_groups where code = 'extracted_honey'),
    'groups', (select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'wholesale_min_kg', wholesale_min_kg) order by sort_order) from public.mfm_honey_price_groups),
    'products', coalesce((select jsonb_agg(jsonb_build_object('slug', p.slug, 'name', p.name, 'swahili_name', p.swahili_name, 'description', p.description,
                     'image_url', p.image_url, 'retail_kes_per_kg', p.retail_kes_per_kg, 'wholesale_kes_per_kg', p.wholesale_kes_per_kg,
                     'min_qty_kg', p.min_qty_kg, 'step_kg', p.step_kg, 'pricing_group', p.pricing_group, 'wholesale_min_kg', g.wholesale_min_kg)
                     order by g.sort_order, p.sort_order, p.id)
                   from public.mfm_honey_products p join public.mfm_honey_price_groups g on g.code = p.pricing_group where p.active), '[]'::jsonb))
$$;

-- ------------------------------------------------------------ place an order
create or replace function public.mfm_honey_place_order(p jsonb) returns jsonb
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
  v_price_note text;
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
      'pricing', v_prev.pricing, 'groups', v_prev.groups, 'total_kg', v_prev.total_kg, 'subtotal_kes', v_prev.subtotal_kes, 'replayed', true);
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
  select string_agg(format('%s %s (%s kg)', g.value ->> 'label', g.value ->> 'pricing', public.mfm_honey_kg((g.value ->> 'kg')::numeric)), ', ' order by pg.sort_order)
    into v_price_note from jsonb_each(v_q -> 'groups') g join public.mfm_honey_price_groups pg on pg.code = g.key;
  v_items := v_items || ' | Items total: KES ' || public.mfm_honey_kes((v_q ->> 'subtotal_kes')::numeric)
          || ' | Honey prices: ' || v_price_note
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
         wholesale_min_kg, subtotal_kes, extracted_kg, extracted_pricing, honeycomb_kg, honeycomb_pricing, groups)
  values (v_order, v_client, v_email, v_town, v_addr, v_ful, (v_q ->> 'total_kg')::numeric, v_q ->> 'pricing',
          coalesce((v_q -> 'groups' -> 'extracted_honey' ->> 'wholesale_min_kg')::numeric, (select wholesale_min_kg from public.mfm_honey_price_groups where code = 'extracted_honey')),
          (v_q ->> 'subtotal_kes')::numeric, (v_q ->> 'extracted_kg')::numeric, v_q ->> 'extracted_pricing', (v_q ->> 'honeycomb_kg')::numeric,
          v_q ->> 'honeycomb_pricing', v_q -> 'groups')
  returning id into v_hid;
  for l in select * from jsonb_array_elements(v_q -> 'lines') loop
    insert into public.mfm_honey_order_items (honey_order_id, product_id, product_name, qty_kg, unit_kes_per_kg, line_kes, pricing_group, pricing)
    values (v_hid, (l ->> 'product_id')::smallint, l ->> 'name', (l ->> 'kg')::numeric, (l ->> 'unit_kes_per_kg')::numeric, (l ->> 'line_kes')::numeric,
            l ->> 'pricing_group', l ->> 'pricing');
  end loop;
  insert into public.mfm_order_events (order_number, event_type, to_value, actor_name, source, detail)
  values (v_order, 'honey_order_placed', v_q ->> 'pricing', 'customer', 'mfm_honey_place_order', v_q);

  return jsonb_build_object('order_number', v_order, 'tracking_code', v_code, 'pricing', v_q ->> 'pricing', 'groups', v_q -> 'groups',
                            'total_kg', (v_q ->> 'total_kg')::numeric, 'subtotal_kes', (v_q ->> 'subtotal_kes')::numeric,
                            'lines', v_q -> 'lines', 'fulfilment', v_ful, 'replayed', false);
end $$;

-- ------------------------------------------------------------ staff list (with groups)
create or replace function public.mfm_honey_admin_orders(p_from date default null, p_to date default null, p_include_test boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.mfm_honey_require_staff();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'order_number', o.order_number, 'tracking_code', o.tracking_code, 'created_at', h.created_at,
      'customer_name', o.customer_name, 'phone', o.contact, 'email', h.customer_email, 'county', o.county, 'town', h.town,
      'address', h.address, 'fulfilment', h.fulfilment, 'total_kg', h.total_kg, 'pricing', h.pricing, 'subtotal_kes', h.subtotal_kes,
      'extracted_kg', h.extracted_kg, 'extracted_pricing', h.extracted_pricing, 'honeycomb_kg', h.honeycomb_kg, 'honeycomb_pricing', h.honeycomb_pricing,
      'delivery_kes', h.delivery_kes, 'paid_kes', v.paid_kes, 'stage', o.stage, 'order_status', o.status, 'payment_status', o.payment_status,
      'status', public.mfm_honey_status(o, h), 'confirmed_at', h.confirmed_at, 'confirmed_by', h.confirmed_by, 'ready_at', h.ready_at,
      'cancel_reason', o.cancel_reason, 'cancel_note', o.cancel_note, 'notes', o.notes, 'duplicate_of', o.duplicate_of,
      'is_test', o.customer_name ~* '^test',
      'items', (select jsonb_agg(jsonb_build_object('product', i.product_name, 'slug', pr.slug, 'kg', i.qty_kg, 'unit_kes_per_kg', i.unit_kes_per_kg,
                                  'line_kes', i.line_kes, 'pricing_group', i.pricing_group, 'pricing', i.pricing) order by pr.sort_order)
                  from public.mfm_honey_order_items i join public.mfm_honey_products pr on pr.id = i.product_id where i.honey_order_id = h.id))
      order by h.created_at desc)
    from public.mfm_honey_orders h
    join public.mfm_orders o on o.order_number = h.order_number
    left join public.mfm_order_values v on v.order_number = h.order_number
    where (p_from is null or (h.created_at at time zone 'Africa/Nairobi')::date >= p_from)
      and (p_to is null or (h.created_at at time zone 'Africa/Nairobi')::date <= p_to)
      and (p_include_test or o.customer_name !~* '^test')), '[]'::jsonb);
end $$;

-- ------------------------------------------------------------ owner: products and thresholds
create table public.mfm_honey_product_history (
  id bigint generated always as identity primary key,
  product_id smallint not null references public.mfm_honey_products (id),
  before_row jsonb not null,
  after_row jsonb not null,
  changed_by text not null,
  changed_at timestamptz not null default now()
);
create index mfm_honey_product_history_product_idx on public.mfm_honey_product_history (product_id, changed_at);
alter table public.mfm_honey_product_history enable row level security;
revoke all on table public.mfm_honey_product_history from public, anon, authenticated;
grant select on table public.mfm_honey_product_history to authenticated;
create policy honey_product_history_staff_read on public.mfm_honey_product_history for select to authenticated using (public.mfm_is_staff());

create function public.mfm_honey_admin_products() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.mfm_honey_require_staff();
  return jsonb_build_object(
    'groups', (select jsonb_agg(to_jsonb(g) order by g.sort_order) from public.mfm_honey_price_groups g),
    'products', (select jsonb_agg(jsonb_build_object('slug', slug, 'name', name, 'swahili_name', swahili_name, 'description', description, 'image_url', image_url,
                   'retail_kes_per_kg', retail_kes_per_kg, 'wholesale_kes_per_kg', wholesale_kes_per_kg, 'min_qty_kg', min_qty_kg, 'step_kg', step_kg,
                   'pricing_group', pricing_group, 'active', active, 'updated_at', updated_at, 'updated_by', updated_by) order by sort_order, id) from public.mfm_honey_products));
end $$;

create function public.mfm_honey_update_product(p_slug text, p_name text, p_swahili_name text, p_description text, p_image_url text,
                                                p_min_qty_kg numeric, p_active boolean) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_staff text := public.mfm_honey_require_staff();
  p public.mfm_honey_products;
  v_img text := nullif(btrim(coalesce(p_image_url, '')), '');
begin
  if not public.mfm_is_owner() then raise exception 'Only the owner can change honey products.' using errcode = '42501'; end if;
  select * into p from public.mfm_honey_products where slug = p_slug for update;
  if p.id is null then raise exception 'Unknown honey.' using errcode = 'P0001'; end if;
  if length(btrim(coalesce(p_name, ''))) not between 2 and 80 then raise exception 'Give the product a name.' using errcode = 'P0001'; end if;
  if length(coalesce(p_description, '')) > 400 then raise exception 'Keep the description under 400 characters.' using errcode = 'P0001'; end if;
  if v_img is not null and v_img !~ '^(https://[^\s"''<>]+|images/[A-Za-z0-9._/-]+)$' then
    raise exception 'The photo must be an https:// link or a website path like images/honey.jpg.' using errcode = 'P0001';
  end if;
  if p_min_qty_kg is null or p_min_qty_kg < p.step_kg or mod(p_min_qty_kg, p.step_kg) <> 0 or p_min_qty_kg > 100 then
    raise exception 'The minimum must be a multiple of % kg.', public.mfm_honey_kg(p.step_kg) using errcode = 'P0001';
  end if;
  if coalesce(p_active, true) = false and (select count(*) from public.mfm_honey_products where active and id <> p.id) = 0 then
    raise exception 'At least one honey must stay on sale.' using errcode = 'P0001';
  end if;
  update public.mfm_honey_products set name = btrim(p_name), swahili_name = nullif(btrim(coalesce(p_swahili_name, '')), ''),
         description = nullif(btrim(coalesce(p_description, '')), ''), image_url = v_img, min_qty_kg = p_min_qty_kg,
         active = coalesce(p_active, true), updated_at = now(), updated_by = v_staff
   where id = p.id;
  insert into public.mfm_honey_product_history (product_id, before_row, after_row, changed_by)
  values (p.id, to_jsonb(p), (select to_jsonb(x) from public.mfm_honey_products x where x.id = p.id), v_staff);
  return jsonb_build_object('slug', p.slug, 'saved', true);
end $$;

create function public.mfm_honey_set_group_min(p_group text, p_kg numeric) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_staff text := public.mfm_honey_require_staff();
begin
  if not public.mfm_is_owner() then raise exception 'Only the owner can change the wholesale minimum.' using errcode = '42501'; end if;
  if p_kg is null or p_kg < 0.25 or p_kg > 1000 or mod(p_kg, 0.25) <> 0 then raise exception 'The wholesale minimum is in kg, in steps of 0.25 (0.25 to 1000).' using errcode = 'P0001'; end if;
  update public.mfm_honey_price_groups set wholesale_min_kg = p_kg, updated_at = now(), updated_by = v_staff where code = p_group;
  if not found then raise exception 'Unknown pricing group.' using errcode = 'P0001'; end if;
  insert into public.mfm_honey_group_history (group_code, wholesale_min_kg, changed_by) values (p_group, p_kg, v_staff);
  return jsonb_build_object('group', p_group, 'wholesale_min_kg', p_kg);
end $$;

-- the old single-minimum function now sets the extracted honey group
create or replace function public.mfm_honey_set_wholesale_min(p_kg numeric) returns jsonb
language sql volatile security definer set search_path = public, pg_temp as $$
  select public.mfm_honey_set_group_min('extracted_honey', p_kg)
$$;

-- ------------------------------------------------------------ product photos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('honey-products', 'honey-products', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy honey_products_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'honey-products' and public.mfm_is_owner() and public.mfm_staff_code_ok());
create policy honey_products_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'honey-products' and public.mfm_is_owner() and public.mfm_staff_code_ok());

-- ------------------------------------------------------------ grants
revoke all on function public.mfm_honey_admin_products(), public.mfm_honey_update_product(text, text, text, text, text, numeric, boolean),
  public.mfm_honey_set_group_min(text, numeric), public.mfm_honey_set_wholesale_min(numeric) from public, anon, authenticated;
grant execute on function public.mfm_honey_admin_products(), public.mfm_honey_update_product(text, text, text, text, text, numeric, boolean),
  public.mfm_honey_set_group_min(text, numeric), public.mfm_honey_set_wholesale_min(numeric) to authenticated;
revoke all on function public.mfm_honey_price(jsonb), public.mfm_honey_catalogue(), public.mfm_honey_place_order(jsonb), public.mfm_honey_admin_orders(date, date, boolean)
  from public, anon, authenticated;
grant execute on function public.mfm_honey_catalogue(), public.mfm_honey_place_order(jsonb) to anon, authenticated;
grant execute on function public.mfm_honey_admin_orders(date, date, boolean) to authenticated;
