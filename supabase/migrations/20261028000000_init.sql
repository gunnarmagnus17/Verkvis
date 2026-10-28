-- =====================================================================
-- Verkvís – fyrsta migration fyrir Supabase
--
-- Supabase sér um innskráningu. Innskráður notandi er auth.uid().
-- Hlutverkin eru anon (óinnskráður) og authenticated (innskráður).
-- Supabase gefur þessum hlutverkum sjálfgefið aðgang að nýjum töflum,
-- svo hér er sá aðgangur tekinn af og veittur aftur í lágmarki.
--
-- Bókanir og umsagnir verða aðeins til í gegnum föll sem athuga allar
-- reglur á einum stað. Beinn INSERT í þær töflur er ekki leyfður.
-- =====================================================================

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

-- ---------------------------------------------------------------------
-- Flokkar og þjónusta (fastir listar)
-- ---------------------------------------------------------------------
create table public.categories (
  code  text primary key,
  name  text not null,
  sort  smallint not null
);

create table public.services (
  code      text primary key,
  category  text not null references public.categories(code),
  name      text not null,
  unit      text,                          -- t.d. 'á klst.', 'á miða'
  synonyms  text[] not null default '{}'
);

insert into public.categories (code, name, sort) values
  ('handverk', 'Handverk', 1),
  ('skemmtun', 'Skemmtun', 2),
  ('almennt',  'Almennt',  3);

insert into public.services (code, category, name, unit, synonyms) values
  ('tires',    'handverk', 'Dekkjaskipti',        null,      '{dekk,vetrardekk,sumardekk,umfelgun,dekkjaverkstæði}'),
  ('oil',      'handverk', 'Smurning',            null,      '{olía,olíuskipti,smurstöð}'),
  ('brakes',   'handverk', 'Bremsuklossar',       null,      '{bremsur,bremsa,klossar}'),
  ('battery',  'handverk', 'Rafgeymisskipti',     null,      '{rafgeymir,geymir,rafhlaða}'),
  ('diag',     'handverk', 'Bilanagreining',      null,      '{bilun,villukóði,mælaborð,greining,verkstæði,bílaverkstæði}'),
  ('hourly',   'handverk', 'Viðgerð (tímagjald)', 'á klst.', '{viðgerð,verkstæði,bílaviðgerð,bílaverkstæði}'),
  ('cinema',   'skemmtun', 'Bíó',                 'á miða',  '{kvikmynd,bíómynd,mynd,sýning,kvikmyndahús}'),
  ('theatre',  'skemmtun', 'Leikhús',             'á miða',  '{leiksýning,söngleikur,sýning,leikrit}'),
  ('darts',    'skemmtun', 'Píla',                'á braut', '{pílukast,pílur,pílustaður}'),
  ('bowling',  'skemmtun', 'Keila',               'á braut', '{keilusalur,keilu,keiluhöll}'),
  ('haircut',  'almennt',  'Klipping',            null,      '{hárgreiðsla,hársnyrting,rakari,rakarastofa,klippa,hár,hárgreiðslustofa}'),
  ('beard',    'almennt',  'Skeggsnyrting',       null,      '{skegg,rakstur,rakari,rakarastofa}'),
  ('massage',  'almennt',  'Nudd',                null,      '{nuddari,slökunarnudd,íþróttanudd,nuddstofa}'),
  ('nails',    'almennt',  'Neglur',              null,      '{naglasnyrting,gelneglur,handsnyrting,naglastofa}');

-- ---------------------------------------------------------------------
-- Notendur, fyrirtæki og starfsfólk
-- ---------------------------------------------------------------------

-- Prófíll fyrir hvern innskráðan notanda. Símanúmerið er í auth.users.
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text check (length(name) <= 100),
  created_at  timestamptz not null default now()
);

-- Búa sjálfkrafa til prófíl þegar notandi skráir sig fyrst inn
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Fyrirtæki. Birtist aðeins þegar verified_at er sett (af stjórnanda).
create table public.shops (
  id            uuid primary key default gen_random_uuid(),
  kennitala     text not null unique check (kennitala ~ '^[0-9]{10}$'),
  name          text not null check (length(name) between 1 and 120),
  category      text not null references public.categories(code),
  area          text not null,
  address       text,
  external_url  text check (external_url is null or external_url ~ '^https://'),
  verified_at   timestamptz,
  created_at    timestamptz not null default now()
);

create table public.shop_members (
  shop_id  uuid not null references public.shops(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  role     text not null check (role in ('owner', 'staff')),
  primary key (shop_id, user_id)
);

-- Er innskráður notandi starfsmaður fyrirtækisins?
create function public.is_shop_member(p_shop uuid, p_owner_only boolean default false)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.shop_members
    where shop_id = p_shop and user_id = auth.uid()
      and (not p_owner_only or role = 'owner')
  )
$$;

-- ---------------------------------------------------------------------
-- Verðskrá, lausir tímar, bókanir, umsagnir
-- ---------------------------------------------------------------------
create table public.shop_prices (
  shop_id       uuid not null references public.shops(id) on delete cascade,
  service_code  text not null references public.services(code),
  price_isk     integer not null check (price_isk > 0 and price_isk < 10000000),
  primary key (shop_id, service_code)
);

-- Fyrirtæki má aðeins verðleggja þjónustu í eigin flokki
create function public.check_price_category() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select category from public.services where code = new.service_code)
     <> (select category from public.shops where id = new.shop_id) then
    raise exception 'wrong_category';
  end if;
  return new;
end $$;
create trigger shop_prices_category before insert or update on public.shop_prices
  for each row execute function public.check_price_category();

-- Lausir tímar. service_code tómt = gildir um alla þjónustu fyrirtækisins.
-- label = t.d. heiti kvikmyndar eða „braut 2“.
create table public.slots (
  id            uuid primary key default gen_random_uuid(),
  shop_id       uuid not null references public.shops(id) on delete cascade,
  service_code  text references public.services(code),
  label         text check (length(label) <= 60),
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  created_at    timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index slots_shop_time on public.slots (shop_id, starts_at);

create table public.bookings (
  id            uuid primary key default gen_random_uuid(),
  slot_id       uuid not null references public.slots(id),
  shop_id       uuid not null references public.shops(id),
  customer_id   uuid not null references auth.users(id),
  service_code  text not null references public.services(code),
  price_isk     integer not null,
  label         text,
  plate         text check (plate is null or plate ~ '^[A-Z0-9]{2,6}$'),
  status        text not null default 'booked'
                check (status in ('booked', 'cancelled', 'completed', 'no_show')),
  starts_at     timestamptz not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
-- Gagnagrunnurinn sjálfur kemur í veg fyrir tvíbókun
create unique index bookings_one_active_per_slot
  on public.bookings (slot_id) where status <> 'cancelled';
create index bookings_customer on public.bookings (customer_id, starts_at desc);
create index bookings_shop on public.bookings (shop_id, starts_at);

create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null unique references public.bookings(id),
  shop_id     uuid not null references public.shops(id),
  stars       smallint not null check (stars between 1 and 5),
  body        text check (length(body) <= 2000),
  created_at  timestamptz not null default now()
);

create table public.audit_log (
  id        bigserial primary key,
  actor_id  uuid,
  action    text not null,
  target    text not null,
  target_id uuid,
  at        timestamptz not null default now()
);

-- Smellir á miðasölu skemmtistaða. Engar persónuupplýsingar.
create table public.outbound_clicks (
  id       bigserial primary key,
  shop_id  uuid not null references public.shops(id) on delete cascade,
  at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------
alter table public.categories      enable row level security;
alter table public.services        enable row level security;
alter table public.profiles        enable row level security;
alter table public.shops           enable row level security;
alter table public.shop_members    enable row level security;
alter table public.shop_prices     enable row level security;
alter table public.slots           enable row level security;
alter table public.bookings        enable row level security;
alter table public.reviews         enable row level security;
alter table public.audit_log       enable row level security;
alter table public.outbound_clicks enable row level security;

create policy categories_read on public.categories for select using (true);
create policy services_read   on public.services   for select using (true);

create policy profiles_self_select on public.profiles for select using (id = auth.uid());
create policy profiles_self_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

create policy shops_read on public.shops for select
  using (verified_at is not null or public.is_shop_member(id));
create policy shops_owner_update on public.shops for update
  using (public.is_shop_member(id, true)) with check (public.is_shop_member(id, true));

create policy members_self on public.shop_members for select using (user_id = auth.uid());

create policy prices_read on public.shop_prices for select using (
  public.is_shop_member(shop_id)
  or exists (select 1 from public.shops s where s.id = shop_id and s.verified_at is not null)
);
create policy prices_member_write on public.shop_prices for all
  using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));

-- Almenningur sér lausa tíma í gegnum get_offers / public_free_slots
create policy slots_member_select on public.slots for select using (public.is_shop_member(shop_id));
create policy slots_member_insert on public.slots for insert
  with check (public.is_shop_member(shop_id) and starts_at > now());
create policy slots_member_delete on public.slots for delete using (
  public.is_shop_member(shop_id)
  and not exists (select 1 from public.bookings b where b.slot_id = slots.id and b.status <> 'cancelled')
);

create policy bookings_visible on public.bookings for select
  using (customer_id = auth.uid() or public.is_shop_member(shop_id));

create policy reviews_none   on public.reviews         for select using (false);
create policy audit_none     on public.audit_log       for select using (false);
create policy clicks_members on public.outbound_clicks for select using (public.is_shop_member(shop_id));

-- ---------------------------------------------------------------------
-- Opinberar sýnir: takmarkaðir dálkar, engar persónuupplýsingar.
-- Þær keyra með réttindum eiganda (Supabase-linterinn varar við því;
-- það er viljandi hér, því þær sýna aðeins það sem er valið).
-- ---------------------------------------------------------------------
create view public.public_reviews as
  select r.id, r.shop_id, r.stars, r.body, r.created_at
  from public.reviews r
  join public.shops sh on sh.id = r.shop_id and sh.verified_at is not null;

create view public.public_shop_ratings as
  select shop_id, round(avg(stars)::numeric, 1) as avg_stars, count(*)::int as review_count
  from public.public_reviews group by shop_id;

-- ---------------------------------------------------------------------
-- Föll fyrir vefinn
-- ---------------------------------------------------------------------

-- Leit: hunsar kommur og há-/lágstafi, sýnir hvaða orð passaði
create function public.search_services(p_query text)
returns table (code text, name text, category text, matched text, score real)
language sql stable set search_path = public, extensions as $$
  with q as (select lower(unaccent(trim(p_query))) as q),
  terms as (
    select s.code, s.name, s.category, s.name as term, true as is_name from public.services s
    union all
    select s.code, s.name, s.category, unnest(s.synonyms), false from public.services s
  ),
  scored as (
    select t.code, t.name, t.category, t.term, t.is_name,
      case
        when lower(unaccent(t.term)) = q.q then 4
        when lower(unaccent(t.term)) like q.q || '%' then 3
        when lower(unaccent(t.term)) like '%' || q.q || '%' then 2
        else similarity(lower(unaccent(t.term)), q.q)
      end as base
    from terms t, q
    where length(q.q) >= 2
  )
  select distinct on (code) code, name, category, term,
         (base + case when is_name then 0.5 else 0 end)::real
  from scored where base >= 0.3
  order by code, base + case when is_name then 0.5 else 0 end desc
$$;

-- Tilboð fyrir þjónustu: verð, einkunn og næstu 4 lausu tímar hvers staðar
create function public.get_offers(p_service text, p_area text default null, p_shop uuid default null)
returns table (
  shop_id uuid, shop_name text, area text, external_url text,
  price_isk integer, unit text, avg_stars numeric, review_count int,
  next_slots jsonb
)
language sql stable security definer set search_path = public as $$
  select sh.id, sh.name, sh.area, sh.external_url,
         p.price_isk, sv.unit, r.avg_stars, coalesce(r.review_count, 0),
         fs.slots
  from public.shops sh
  join public.shop_prices p on p.shop_id = sh.id and p.service_code = p_service
  join public.services sv on sv.code = p_service
  left join public.public_shop_ratings r on r.shop_id = sh.id
  cross join lateral (
    select jsonb_agg(jsonb_build_object('id', s.id, 'starts_at', s.starts_at, 'label', s.label)
                     order by s.starts_at) as slots
    from (
      select s.* from public.slots s
      where s.shop_id = sh.id
        and s.starts_at > now()
        and (s.service_code is null or s.service_code = p_service)
        and not exists (select 1 from public.bookings b
                        where b.slot_id = s.id and b.status <> 'cancelled')
      order by s.starts_at limit 4
    ) s
  ) fs
  where sh.verified_at is not null
    and (p_area is null or sh.area = p_area)
    and (p_shop is null or sh.id = p_shop)
    and fs.slots is not null
$$;

create function public.book_slot(p_slot uuid, p_service text, p_plate text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_user  uuid := auth.uid();
  v_slot  public.slots%rowtype;
  v_shop  public.shops%rowtype;
  v_cat   text;
  v_price integer;
  v_plate text := nullif(upper(trim(p_plate)), '');
  v_id    uuid;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;

  if (select count(*) from public.bookings
      where customer_id = v_user and status = 'booked' and starts_at > now()) >= 5 then
    raise exception 'too_many_bookings';
  end if;

  select * into v_slot from public.slots where id = p_slot for update;
  if not found or v_slot.starts_at <= now() then raise exception 'slot_unavailable'; end if;
  if v_slot.service_code is not null and v_slot.service_code <> p_service then
    raise exception 'slot_unavailable';
  end if;

  select * into v_shop from public.shops where id = v_slot.shop_id and verified_at is not null;
  if not found then raise exception 'slot_unavailable'; end if;
  if v_shop.external_url is not null then raise exception 'book_externally'; end if;

  select category into v_cat from public.services where code = p_service;
  if v_cat = 'handverk' and v_plate is null then raise exception 'plate_required'; end if;
  if v_cat <> 'handverk' then v_plate := null; end if;

  select price_isk into v_price from public.shop_prices
    where shop_id = v_shop.id and service_code = p_service;
  if v_price is null then raise exception 'service_not_offered'; end if;

  insert into public.bookings (slot_id, shop_id, customer_id, service_code, price_isk, label, plate, starts_at)
  values (p_slot, v_shop.id, v_user, p_service, v_price, v_slot.label, v_plate, v_slot.starts_at)
  returning id into v_id;

  insert into public.audit_log (actor_id, action, target, target_id) values (v_user, 'book', 'bookings', v_id);
  return v_id;
exception when unique_violation then
  raise exception 'slot_unavailable';
end $$;

create function public.cancel_booking(p_booking uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.bookings set status = 'cancelled', updated_at = now()
  where id = p_booking and status = 'booked'
    and (customer_id = auth.uid() or public.is_shop_member(shop_id));
  if not found then raise exception 'not_found'; end if;
  insert into public.audit_log (actor_id, action, target, target_id) values (auth.uid(), 'cancel', 'bookings', p_booking);
end $$;

create function public.set_booking_status(p_booking uuid, p_status text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('completed', 'no_show') then raise exception 'invalid_status'; end if;
  update public.bookings set status = p_status, updated_at = now()
  where id = p_booking and status = 'booked' and public.is_shop_member(shop_id);
  if not found then raise exception 'not_found'; end if;
  insert into public.audit_log (actor_id, action, target, target_id) values (auth.uid(), p_status, 'bookings', p_booking);
end $$;

create function public.leave_review(p_booking uuid, p_stars smallint, p_body text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_shop uuid; v_id uuid;
begin
  select shop_id into v_shop from public.bookings
    where id = p_booking and customer_id = auth.uid() and status = 'completed';
  if v_shop is null then raise exception 'not_allowed'; end if;
  insert into public.reviews (booking_id, shop_id, stars, body)
  values (p_booking, v_shop, p_stars, nullif(trim(p_body), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'already_reviewed';
end $$;

create function public.log_outbound_click(p_shop uuid)
returns void
language sql security definer set search_path = public as $$
  insert into public.outbound_clicks (shop_id)
  select id from public.shops where id = p_shop and external_url is not null and verified_at is not null
$$;

-- ---------------------------------------------------------------------
-- Réttindi: taka sjálfgefinn aðgang af og veita aftur í lágmarki
-- ---------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Allir (líka óinnskráðir)
grant select on public.categories, public.services, public.shops, public.shop_prices,
                public.public_reviews, public.public_shop_ratings to anon, authenticated;
grant execute on function public.search_services(text),
                          public.get_offers(text, text, uuid),
                          public.log_outbound_click(uuid),
                          public.is_shop_member(uuid, boolean) to anon, authenticated;

-- Aðeins innskráðir
grant select, update (name) on public.profiles to authenticated;
grant update (name, area, address, external_url) on public.shops to authenticated;
grant select on public.shop_members, public.bookings, public.outbound_clicks to authenticated;
grant select, insert, update, delete on public.shop_prices to authenticated;
grant select, insert, delete on public.slots to authenticated;
grant execute on function public.book_slot(uuid, text, text),
                          public.cancel_booking(uuid),
                          public.set_booking_status(uuid, text),
                          public.leave_review(uuid, smallint, text) to authenticated;

-- Stofnun fyrirtækja og staðfesting (verified_at) fer fram í stjórnendaþjónustu
-- eða í SQL-ritlinum í Supabase, aldrei úr vafranum.
