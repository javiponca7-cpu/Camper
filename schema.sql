-- Nuestra Camper · esquema Supabase (pegar en SQL Editor y ejecutar)
create extension if not exists btree_gist;

create table profiles(
  id uuid primary key references auth.users on delete cascade,
  name text not null, color text not null default '#5b6130', created_at timestamptz default now());

create table trips(
  id uuid primary key default gen_random_uuid(),
  title text not null, destination text, start_date date, end_date date,
  description text, places text, route text, overnight text, tips text,
  author uuid not null default auth.uid() references profiles(id),
  created_at timestamptz default now());

create table photos(
  id uuid primary key default gen_random_uuid(),
  trip_id uuid references trips(id) on delete cascade,
  path text not null,
  author uuid not null default auth.uid() references profiles(id),
  created_at timestamptz default now());

create table bookings(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references profiles(id),
  start_date date not null, end_date date not null, note text,
  status text not null default 'pendiente' check (status in ('pendiente','confirmada','cancelada')),
  created_at timestamptz default now(),
  check (end_date >= start_date),
  exclude using gist (daterange(start_date,end_date,'[]') with &&) where (status <> 'cancelada'));

-- Perfil automático al crear cada usuario (nombre = parte antes de la @)
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare cols text[] := array['#5b6130','#b5651d','#2f6f73','#8a4f7d','#a33b3b','#3d5a80'];
begin
  insert into profiles(id,name,color)
  values(new.id, initcap(split_part(new.email,'@',1)), cols[1 + (select count(*) from profiles)::int % 6]);
  return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- RLS
alter table profiles enable row level security;
alter table trips enable row level security;
alter table photos enable row level security;
alter table bookings enable row level security;

create policy "perfiles visibles" on profiles for select using (true); -- necesario para elegir perfil antes del PIN
create policy "editar mi perfil" on profiles for update to authenticated using (id=auth.uid());

create policy "ver viajes" on trips for select to authenticated using (true);
create policy "crear viajes" on trips for insert to authenticated with check (author=auth.uid());
create policy "editar viajes" on trips for update to authenticated using (true);
create policy "borrar mis viajes" on trips for delete to authenticated using (author=auth.uid());

create policy "ver fotos" on photos for select to authenticated using (true);
create policy "subir fotos" on photos for insert to authenticated with check (author=auth.uid());
create policy "borrar mis fotos" on photos for delete to authenticated using (author=auth.uid());

create policy "ver reservas" on bookings for select to authenticated using (true);
create policy "crear reservas" on bookings for insert to authenticated with check (user_id=auth.uid());
create policy "editar mis reservas" on bookings for update to authenticated using (user_id=auth.uid());
create policy "borrar mis reservas" on bookings for delete to authenticated using (user_id=auth.uid());

-- Almacenamiento privado de fotos
insert into storage.buckets(id,name,public) values('photos','photos',false) on conflict do nothing;
create policy "leer fotos" on storage.objects for select to authenticated using (bucket_id='photos');
create policy "subir fotos" on storage.objects for insert to authenticated with check (bucket_id='photos');
create policy "borrar fotos propias" on storage.objects for delete to authenticated using (bucket_id='photos' and owner=auth.uid());

-- Tiempo real
alter publication supabase_realtime add table trips, photos, bookings;
