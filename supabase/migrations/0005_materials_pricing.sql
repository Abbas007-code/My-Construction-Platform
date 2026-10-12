-- 0005_materials_pricing.sql
-- Catalog + price engine. Depends on 0001-0004 (uses private.is_admin()).
-- Rules: every price carries an explicit status; demo/estimated/historical are never presented as verified;
-- unlisted (unverified/suspended) suppliers' prices are not public; price_history is append-only.

create type public.price_status as enum ('verified','supplier_submitted','estimated','historical','demo');
create type public.price_source_type as enum ('admin_entry','supplier','api','survey','model_estimate','seed_demo');

create table public.platform_settings (
  key text primary key,
  value jsonb not null,
  is_public boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.material_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.material_categories(id),
  slug text not null unique,
  name text not null,
  name_i18n jsonb not null default '{}',
  default_unit text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index material_categories_parent_idx on public.material_categories(parent_id);
create trigger material_categories_updated before update on public.material_categories for each row execute function public.set_updated_at();

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.material_categories(id),
  brand_id uuid references public.brands(id),
  slug text not null unique,
  name text not null,
  model text,
  specification jsonb not null default '{}',
  unit text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_category_idx on public.products(category_id) where is_active;
create index products_brand_idx on public.products(brand_id);
create trigger products_updated before update on public.products for each row execute function public.set_updated_at();

create table public.price_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  source_type public.price_source_type not null,
  notes text,
  created_at timestamptz not null default now()
);

create table public.product_prices (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  country_id uuid not null references public.countries(id),
  city_id uuid not null,
  area_id uuid,
  supplier_profile_id uuid references public.provider_profiles(id),
  unit text not null,
  currency char(3) not null,
  current_price numeric(14,2) not null check (current_price >= 0),
  previous_price numeric(14,2) check (previous_price >= 0),
  availability text not null default 'unknown' check (availability in ('in_stock','limited','out_of_stock','unknown')),
  status public.price_status not null,
  source_type public.price_source_type not null,
  source_id uuid references public.price_sources(id),
  source_note text,
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),           -- last time the price was submitted/confirmed
  foreign key (city_id, country_id) references public.cities(id, country_id),
  foreign key (area_id, city_id) references public.areas(id, city_id),
  constraint verified_needs_stamp check (status <> 'verified' or (verified_at is not null and verified_by is not null)),
  constraint demo_source_matches check ((status = 'demo') = (source_type = 'seed_demo'))
);
create unique index product_prices_unique_idx on public.product_prices
  (product_id, city_id, coalesce(area_id, '00000000-0000-0000-0000-000000000000'::uuid),
   coalesce(supplier_profile_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index product_prices_city_idx on public.product_prices(city_id, product_id);
create index product_prices_supplier_idx on public.product_prices(supplier_profile_id);
create index product_prices_source_idx on public.product_prices(source_id);

create table public.price_history (
  id bigint generated always as identity primary key,
  product_price_id uuid,                                   -- no FK: history outlives deleted rows
  product_id uuid not null,
  country_id uuid not null,
  city_id uuid not null,
  area_id uuid,
  supplier_profile_id uuid,
  currency char(3) not null,
  unit text not null,
  price numeric(14,2) not null,
  status public.price_status not null,
  source_type public.price_source_type not null,
  recorded_by uuid,                                        -- not exposed to API roles (column grants)
  recorded_at timestamptz not null default now()
);
create index price_history_lookup_idx on public.price_history(product_id, city_id, recorded_at desc);

-- append-only: nobody (including privileged roles) can update, delete or truncate history
create function public.price_history_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'price_history is append-only' using errcode = '42501'; end $$;
create trigger price_history_no_change before update or delete on public.price_history
  for each row execute function public.price_history_immutable();
create trigger price_history_no_truncate before truncate on public.price_history
  for each statement execute function public.price_history_immutable();

-- price integrity is enforced server-side, never trusted from the client
create function public.product_prices_before() returns trigger
language plpgsql set search_path = '' as $$
declare _unit text; _cur char(3);
begin
  select p.unit into _unit from public.products p where p.id = new.product_id;
  if _unit is null then raise exception 'unknown or inactive product' using errcode = '23503'; end if;
  if new.unit <> _unit then
    raise exception 'unit % does not match product unit %', new.unit, _unit using errcode = '23514';
  end if;
  select c.default_currency into _cur from public.countries c where c.id = new.country_id;
  if new.currency is distinct from _cur then
    raise exception 'currency % does not match country currency %', new.currency, _cur using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    new.previous_price := null; new.created_at := now(); new.updated_at := now();
  else
    new.previous_price := case when new.current_price is distinct from old.current_price
                               then old.current_price else old.previous_price end;
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;
  if new.status = 'verified' then
    if tg_op = 'INSERT' or old.status is distinct from 'verified' then
      new.verified_at := coalesce(new.verified_at, now());
      new.verified_by := coalesce(new.verified_by, (select auth.uid()));
    end if;
  else
    new.verified_at := null; new.verified_by := null;
  end if;
  return new;
end $$;
create trigger product_prices_before_trg before insert or update on public.product_prices
  for each row execute function public.product_prices_before();

create function public.product_prices_after() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.current_price is distinct from old.current_price
     or new.status is distinct from old.status then
    insert into public.price_history(product_price_id, product_id, country_id, city_id, area_id,
      supplier_profile_id, currency, unit, price, status, source_type, recorded_by)
    values (new.id, new.product_id, new.country_id, new.city_id, new.area_id,
      new.supplier_profile_id, new.currency, new.unit, new.current_price, new.status, new.source_type,
      (select auth.uid()));
  end if;
  return null;
end $$;
revoke execute on function public.product_prices_after() from public, anon, authenticated;
create trigger product_prices_after_trg after insert or update on public.product_prices
  for each row execute function public.product_prices_after();

-- public read model: explicit status labels; never "live"; outdated prices say so
create view public.product_prices_view with (security_invoker = true) as
select
  pp.id, pp.product_id, pp.country_id, pp.city_id, pp.area_id, pp.supplier_profile_id,
  pp.unit, pp.currency, pp.current_price, pp.previous_price, pp.availability,
  pp.status, pp.source_type, pp.source_note, pp.verified_at, pp.updated_at,
  case when pp.previous_price is null then 'none'
       when pp.current_price > pp.previous_price then 'up'
       when pp.current_price < pp.previous_price then 'down'
       else 'unchanged' end as price_trend,
  f.is_fresh,
  (pp.status = 'demo') as is_demo,
  case pp.status
    when 'demo' then 'Demo data'
    when 'estimated' then 'Estimate'
    when 'historical' then 'Historical price'
    when 'supplier_submitted' then case when f.is_fresh then 'Supplier submitted' else 'Supplier submitted (outdated)' end
    when 'verified' then case when f.is_fresh then 'Verified' else 'Verified (outdated)' end
  end as display_label
from public.product_prices pp
cross join lateral (
  select (pp.status in ('verified','supplier_submitted')
          and pp.updated_at > now() - make_interval(days => coalesce(
            (select (s.value #>> '{}')::int from public.platform_settings s where s.key = 'price_stale_days'), 7))
         ) as is_fresh
) f;

-- ---------- RLS ----------
-- catalog: public sees only active categories/products; admins manage everything
alter table public.material_categories enable row level security;
create policy material_categories_read on public.material_categories for select to anon, authenticated using (is_active);
create policy material_categories_admin_write on public.material_categories for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

alter table public.brands enable row level security;
create policy brands_read on public.brands for select to anon, authenticated using (true);
create policy brands_admin_write on public.brands for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

alter table public.products enable row level security;
create policy products_read on public.products for select to anon, authenticated using (is_active);
create policy products_admin_write on public.products for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- price sources are internal (admin only)
alter table public.price_sources enable row level security;
create policy price_sources_admin on public.price_sources for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

alter table public.platform_settings enable row level security;
create policy settings_public_read on public.platform_settings for select to anon, authenticated using (is_public);
create policy settings_admin_write on public.platform_settings for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- prices: visible only for active products and (market-level, or a publicly listed supplier).
-- The provider_profiles / products subqueries run under the caller's RLS, so anon only "sees"
-- verified+published+non-suspended suppliers and active products; owners see their own; admins see all.
alter table public.product_prices enable row level security;
create policy prices_read on public.product_prices for select to anon, authenticated
  using (
    exists (select 1 from public.products p where p.id = product_prices.product_id)
    and (supplier_profile_id is null
         or exists (select 1 from public.provider_profiles pp where pp.id = product_prices.supplier_profile_id))
  );
create policy prices_admin_write on public.product_prices for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
-- suppliers: only their own, non-suspended supplier profile; only as 'supplier_submitted'; never self-verified
create policy prices_supplier_insert on public.product_prices for insert to authenticated
  with check (status = 'supplier_submitted' and source_type = 'supplier' and verified_at is null and verified_by is null
    and exists (select 1 from public.provider_profiles pp
                where pp.id = supplier_profile_id and pp.user_id = (select auth.uid())
                  and pp.provider_type = 'SUPPLIER' and not private.is_suspended(pp.user_id)));
create policy prices_supplier_update on public.product_prices for update to authenticated
  using (exists (select 1 from public.provider_profiles pp
                 where pp.id = supplier_profile_id and pp.user_id = (select auth.uid())
                   and pp.provider_type = 'SUPPLIER' and not private.is_suspended(pp.user_id)))
  with check (status = 'supplier_submitted' and source_type = 'supplier' and verified_at is null and verified_by is null
    and exists (select 1 from public.provider_profiles pp
                where pp.id = supplier_profile_id and pp.user_id = (select auth.uid())
                  and pp.provider_type = 'SUPPLIER' and not private.is_suspended(pp.user_id)));

-- history: same visibility as prices; read-only
alter table public.price_history enable row level security;
create policy price_history_read on public.price_history for select to anon, authenticated
  using (
    exists (select 1 from public.products p where p.id = price_history.product_id)
    and (supplier_profile_id is null
         or exists (select 1 from public.provider_profiles pp where pp.id = price_history.supplier_profile_id))
  );

-- ---------- privileges (least privilege; consistent with 0003) ----------
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke insert, update, delete on all tables in schema public from anon;
revoke all on public.price_sources from anon;
revoke select on public.platform_settings from anon, authenticated;
grant select (key, value, is_public) on public.platform_settings to anon, authenticated;
-- internal columns (verified_by, source_id, created_at) are not readable through the API
revoke select on public.product_prices from anon, authenticated;
grant select (id, product_id, country_id, city_id, area_id, supplier_profile_id, unit, currency, current_price,
              previous_price, availability, status, source_type, source_note, verified_at, updated_at)
  on public.product_prices to anon, authenticated;
revoke insert, update, delete, select on public.price_history from anon, authenticated;
grant select (id, product_price_id, product_id, country_id, city_id, area_id, supplier_profile_id, currency, unit,
              price, status, source_type, recorded_at)
  on public.price_history to anon, authenticated;
revoke all on public.product_prices_view from anon, authenticated;
grant select on public.product_prices_view to anon, authenticated;
