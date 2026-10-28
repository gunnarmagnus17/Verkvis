-- Prófunargögn. Keyrðu í SQL-ritlinum í Supabase (eða sjálfkrafa með
-- `npx supabase db reset` ef þú keyrir gagnagrunninn á eigin tölvu).
-- Ekki keyra þetta á gagnagrunni með alvöru notendum.

insert into public.shops (id, kennitala, name, category, area, verified_at) values
  ('11111111-1111-1111-1111-111111111111', '0000000001', 'Bílaverk Prófun',  'handverk', 'Höfuðborgarsvæðið', now()),
  ('22222222-2222-2222-2222-222222222222', '0000000002', 'Dekkjahöllin Prófun', 'handverk', 'Höfuðborgarsvæðið', now()),
  ('33333333-3333-3333-3333-333333333333', '0000000003', 'Keiluhöll Prófun', 'skemmtun', 'Höfuðborgarsvæðið', now());

update public.shops set external_url = 'https://example.com'
  where id = '33333333-3333-3333-3333-333333333333';

insert into public.shop_prices (shop_id, service_code, price_isk) values
  ('11111111-1111-1111-1111-111111111111', 'tires',  9900),
  ('11111111-1111-1111-1111-111111111111', 'oil',   14900),
  ('11111111-1111-1111-1111-111111111111', 'hourly',18900),
  ('22222222-2222-2222-2222-222222222222', 'tires',  8500),
  ('33333333-3333-3333-3333-333333333333', 'bowling', 7900);

-- Lausir tímar næstu daga, reiknaðir út frá deginum í dag
insert into public.slots (shop_id, service_code, label, starts_at, ends_at)
select shop_id, svc, lbl,
       date_trunc('day', now()) + d * interval '1 day' + h * interval '1 hour',
       date_trunc('day', now()) + d * interval '1 day' + (h + 1) * interval '1 hour'
from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, null::text, null::text),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'tires',    null),
  ('33333333-3333-3333-3333-333333333333'::uuid, 'bowling',  'Braut 2')
) as s(shop_id, svc, lbl),
generate_series(1, 3) as d,
(values (9), (13), (16)) as hrs(h);
