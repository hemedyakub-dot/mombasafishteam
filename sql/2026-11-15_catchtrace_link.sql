-- MombasaFish shop <-> CatchTrace link (15 Nov 2026)
--
-- ADDITIVE ONLY. Creates one new table and four new functions. It does not
-- change any existing table, function, policy or row. add_shop_stock and
-- everything that reads mfm_shop_intake keep working exactly as before.
--
-- What it does: when the owner receives stock that carries a CatchTrace QR
-- code, the stock intake is recorded as usual AND tied to that QR code. The
-- shop can then show which stock is traceable to a landing site, and how much
-- of what came in was traced.
--
-- The two databases stay separate. This database never connects to CatchTrace
-- and holds no CatchTrace password or key. The shop page reads the public QR
-- page data (the same data any customer sees when scanning) and keeps a short
-- summary of it here, labelled as "as shown when received".

create table public.mfm_shop_trace_links (
  id           bigint generated always as identity primary key,
  intake_id    bigint not null unique references public.mfm_shop_intake (id),
  product_id   bigint not null references public.mfm_shop_products (id),
  qty          numeric not null check (qty > 0),
  trace_token  text not null check (trace_token ~ '^[0-9a-f]{32}$'),
  trace_env    text not null check (trace_env in ('staging', 'production')),
  batch_ref    text,
  summary      jsonb not null default '{}'::jsonb,
  demonstration_data boolean not null default false,
  linked_by    uuid default auth.uid(),
  staff_name   text,
  created_at   timestamptz not null default now()
);
create index mfm_shop_trace_links_product_idx on public.mfm_shop_trace_links (product_id, created_at desc);
create index mfm_shop_trace_links_token_idx on public.mfm_shop_trace_links (trace_token);
comment on table public.mfm_shop_trace_links is 'Stock intakes tied to a CatchTrace QR code. summary = what the public trace page showed when the stock was received.';

-- Read and written only through the functions below.
alter table public.mfm_shop_trace_links enable row level security;
revoke all on table public.mfm_shop_trace_links from public, anon, authenticated;

-- Same as add_shop_stock (owner only, adds stock, writes the intake audit row)
-- plus the link row - all in one transaction, so there is never stock without
-- its link or a link without its stock.
create function public.add_shop_stock_traced(
  p_product bigint, p_qty numeric, p_staff text,
  p_trace_token text, p_trace_env text, p_batch_ref text, p_summary jsonb, p_demo boolean)
returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare
  v_intake bigint;
  v_before numeric;
begin
  if not public.mfm_is_owner() then raise exception 'owner only — adding stock is restricted to the owner'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'enter an amount above zero'; end if;
  if p_trace_token is null or p_trace_token !~ '^[0-9a-f]{32}$' then raise exception 'that is not a CatchTrace QR code'; end if;
  if p_trace_env not in ('staging', 'production') then raise exception 'unknown CatchTrace system'; end if;
  if not exists (select 1 from public.mfm_shop_products where id = p_product) then raise exception 'product not found'; end if;

  select coalesce(sum(qty), 0) into v_before from public.mfm_shop_trace_links where trace_token = p_trace_token;

  update public.mfm_shop_products
     set stock_qty = coalesce(stock_qty, 0) + p_qty, in_stock = true, updated_at = now()
   where id = p_product;
  insert into public.mfm_shop_intake (product_id, qty_added, staff_name, change_type, reason)
  values (p_product, p_qty, p_staff, 'intake', left('CatchTrace ' || coalesce(p_batch_ref, p_trace_token), 200))
  returning id into v_intake;
  insert into public.mfm_shop_trace_links (intake_id, product_id, qty, trace_token, trace_env, batch_ref, summary, demonstration_data, staff_name)
  values (v_intake, p_product, p_qty, p_trace_token, p_trace_env, left(p_batch_ref, 60), coalesce(p_summary, '{}'::jsonb), coalesce(p_demo, false), p_staff);

  return jsonb_build_object('intake_id', v_intake, 'earlier_qty_on_this_code', v_before);
end $$;

-- How much has already been received on one QR code (to warn about a code
-- being entered twice).
create function public.shop_trace_code_used(p_trace_token text)
returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.mfm_is_owner() then raise exception 'owner only'; end if;
  return (select jsonb_build_object('times', count(*), 'qty', coalesce(sum(qty), 0), 'last', max(created_at))
            from public.mfm_shop_trace_links where trace_token = p_trace_token);
end $$;

-- Recent traced intakes, newest first.
create function public.shop_trace_links_recent(p_days integer default 30)
returns table (id bigint, created_at timestamptz, product_id bigint, product_name text, sw_name text, sale_unit text,
               qty numeric, trace_token text, trace_env text, batch_ref text, summary jsonb, demonstration_data boolean, staff_name text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.mfm_is_owner() then raise exception 'owner only'; end if;
  return query
    select l.id, l.created_at, l.product_id, p.name, p.sw_name, p.sale_unit, l.qty, l.trace_token, l.trace_env, l.batch_ref, l.summary, l.demonstration_data, l.staff_name
      from public.mfm_shop_trace_links l join public.mfm_shop_products p on p.id = l.product_id
     where l.created_at > now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
     order by l.created_at desc
     limit 200;
end $$;

-- Of the stock received (intakes only - not corrections or recounts), how
-- much was tied to a CatchTrace code, per product. Test (staging) and
-- demonstration codes are counted separately so they never inflate the real figure.
create function public.shop_trace_coverage(p_days integer default 30)
returns table (product_id bigint, product_name text, sale_unit text, received numeric, traced numeric, traced_test numeric)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.mfm_is_owner() then raise exception 'owner only'; end if;
  return query
    select p.id, p.name, p.sale_unit,
           coalesce(sum(i.qty_added), 0),
           coalesce(sum(l.qty) filter (where l.trace_env = 'production' and not l.demonstration_data), 0),
           coalesce(sum(l.qty) filter (where l.trace_env <> 'production' or l.demonstration_data), 0)
      from public.mfm_shop_intake i
      join public.mfm_shop_products p on p.id = i.product_id
      left join public.mfm_shop_trace_links l on l.intake_id = i.id
     where i.change_type = 'intake' and i.qty_added > 0
       and i.created_at > now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
     group by p.id, p.name, p.sale_unit
     order by 4 desc;
end $$;

revoke all on function public.add_shop_stock_traced(bigint, numeric, text, text, text, text, jsonb, boolean) from public, anon;
revoke all on function public.shop_trace_code_used(text) from public, anon;
revoke all on function public.shop_trace_links_recent(integer) from public, anon;
revoke all on function public.shop_trace_coverage(integer) from public, anon;
grant execute on function public.add_shop_stock_traced(bigint, numeric, text, text, text, text, jsonb, boolean) to authenticated;
grant execute on function public.shop_trace_code_used(text) to authenticated;
grant execute on function public.shop_trace_links_recent(integer) to authenticated;
grant execute on function public.shop_trace_coverage(integer) to authenticated;
