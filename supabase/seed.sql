-- seed.sql  [Written, untested]
-- Reference data only (geography, categories, settings). NO prices, providers, reviews or verification data.

insert into public.countries (iso2, name, name_i18n, default_currency, default_locale, default_timezone, is_active)
values ('PK', 'Pakistan', '{"ur":"پاکستان","ar":"باكستان"}', 'PKR', 'en', 'Asia/Karachi', true)
on conflict (iso2) do nothing;

insert into public.regions (country_id, code, name)
select c.id, v.code, v.name from public.countries c,
  (values ('PK-PB','Punjab'),('PK-SD','Sindh'),('PK-KP','Khyber Pakhtunkhwa'),('PK-BA','Balochistan'),
          ('PK-IS','Islamabad Capital Territory'),('PK-JK','Azad Jammu & Kashmir'),('PK-GB','Gilgit-Baltistan')) as v(code, name)
where c.iso2 = 'PK'
on conflict (country_id, code) do nothing;

insert into public.cities (country_id, region_id, slug, name)
select c.id, r.id, v.slug, v.name
from public.countries c
join (values
  ('PK-PB','multan','Multan'),('PK-PB','lahore','Lahore'),('PK-PB','faisalabad','Faisalabad'),
  ('PK-PB','rawalpindi','Rawalpindi'),('PK-SD','karachi','Karachi'),('PK-SD','hyderabad','Hyderabad'),
  ('PK-KP','peshawar','Peshawar'),('PK-BA','quetta','Quetta'),('PK-IS','islamabad','Islamabad'),
  ('PK-JK','muzaffarabad','Muzaffarabad'),('PK-GB','gilgit','Gilgit')
) as v(region_code, slug, name) on true
join public.regions r on r.country_id = c.id and r.code = v.region_code
where c.iso2 = 'PK'
on conflict (country_id, slug) do nothing;

insert into public.material_categories (slug, name, sort_order) values
  ('cement','Cement',10),('steel','Steel / Rebar',20),('bricks','Bricks',30),('sand','Sand',40),
  ('crush','Crush / Bajri',50),('paint','Paint',60),('tiles','Tiles',70),('plumbing','Plumbing',80),
  ('electrical','Electrical',90),('doors','Doors',100),('windows','Windows',110),('fans','Fans',120),
  ('sanitary','Sanitary',130),('other','Other',999)
on conflict (slug) do nothing;

insert into public.platform_settings (key, value, is_public) values
  ('price_stale_days', '7', true)
on conflict (key) do nothing;
