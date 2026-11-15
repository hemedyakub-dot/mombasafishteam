-- Counter: which products on sale are traceable right now (15 Nov 2026)
-- ADDITIVE ONLY: one new read function. Changes nothing existing.
--
-- A product counts as traced when it has stock, its most recent intake was
-- received with a CatchTrace code, and that was within the last 21 days.
-- Returns only what the public trace page shows anyway (code, batch, fish,
-- landing site, date) - no quantities, prices or costs - so every shop staff
-- member may read it, to show customers the QR code.

create function public.shop_traced_now()
returns table (product_id bigint, trace_token text, trace_env text, batch_ref text,
               species jsonb, landing_sites jsonb, demonstration_data boolean, received_at timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.mfm_is_staff() then raise exception 'not staff'; end if;
  return query
    select p.id, l.trace_token, l.trace_env, l.batch_ref,
           coalesce(l.summary -> 'species', '[]'::jsonb), coalesce(l.summary -> 'landing_sites', '[]'::jsonb),
           l.demonstration_data, l.created_at
      from public.mfm_shop_products p
      cross join lateral (
        select i.id from public.mfm_shop_intake i
         where i.product_id = p.id and i.change_type = 'intake' and i.qty_added > 0
         order by i.created_at desc, i.id desc limit 1) last_in
      join public.mfm_shop_trace_links l on l.intake_id = last_in.id
     where p.active and coalesce(p.stock_qty, 0) > 0
       and l.created_at > now() - interval '21 days';
end $$;
revoke all on function public.shop_traced_now() from public, anon;
grant execute on function public.shop_traced_now() to authenticated;
