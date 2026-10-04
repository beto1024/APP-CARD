create extension if not exists pgcrypto;
create type public.user_role as enum ('ADMIN','STUDENT');
create type public.card_kind as enum ('WORD','VERB');

create table public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  role public.user_role not null default 'STUDENT',
  active boolean not null default true,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.source_files(
  id uuid primary key default gen_random_uuid(),
  drive_file_id text unique not null,
  file_name text not null,
  kind public.card_kind not null,
  drive_modified_at timestamptz,
  content_hash text,
  last_sync_at timestamptz
);

create table public.cards(
  id uuid primary key default gen_random_uuid(),
  source_file_id uuid not null references public.source_files(id),
  source_key text not null,
  kind public.card_kind not null,
  level text check(level is null or level in('A1','A2','B1')),
  part_of_speech text,
  german text not null,
  spanish text not null,
  conjugations jsonb,
  content_hash text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(source_file_id,source_key)
);
create index cards_active_idx on public.cards(active,kind,level);

create table public.user_card_progress(
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete cascade,
  due_at timestamptz not null default now(),
  interval_days numeric not null default 0,
  ease_factor numeric not null default 2.5,
  repetitions integer not null default 0,
  lapses integer not null default 0,
  last_reviewed_at timestamptz,
  primary key(user_id,card_id)
);
create index progress_due_idx on public.user_card_progress(user_id,due_at);

create table public.study_reviews(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid not null references public.cards(id),
  rating text not null check(rating in('AGAIN','HARD','GOOD','EASY')),
  resulting_state jsonb not null,
  reviewed_at timestamptz not null default now()
);

create table public.sync_runs(
  id bigint generated always as identity primary key,
  status text not null check(status in('RUNNING','SUCCEEDED','FAILED','SKIPPED')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  details jsonb not null default '{}'::jsonb
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,display_name)
  values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'display_name',split_part(coalesce(new.email,''),'@',1)));
  return new;
end$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='ADMIN' and active)
$$;

alter table public.profiles enable row level security;
alter table public.cards enable row level security;
alter table public.source_files enable row level security;
alter table public.user_card_progress enable row level security;
alter table public.study_reviews enable row level security;
alter table public.sync_runs enable row level security;

create policy "profile own read" on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy "active cards authenticated read" on public.cards for select to authenticated using(active);
create policy "sources authenticated read" on public.source_files for select to authenticated using(true);
create policy "progress own read" on public.user_card_progress for select using(user_id=auth.uid());
create policy "reviews own read" on public.study_reviews for select using(user_id=auth.uid());
create policy "sync admin read" on public.sync_runs for select using(public.is_admin());

create or replace function public.get_due_cards(requested_limit integer default 20)
returns table(id uuid,kind public.card_kind,level text,part_of_speech text,german text,spanish text,conjugations jsonb,due_at timestamptz,interval_days numeric,ease_factor numeric,repetitions integer,lapses integer)
language sql security definer set search_path=public as $$
  select c.id,c.kind,c.level,c.part_of_speech,c.german,c.spanish,c.conjugations,p.due_at,
         coalesce(p.interval_days,0),coalesce(p.ease_factor,2.5),coalesce(p.repetitions,0),coalesce(p.lapses,0)
  from public.cards c left join public.user_card_progress p on p.card_id=c.id and p.user_id=auth.uid()
  where c.active and (p.due_at is null or p.due_at<=now())
  order by p.due_at nulls last,c.level nulls last,c.german
  limit least(greatest(requested_limit,1),100)
$$;

create or replace function public.due_card_count() returns bigint language sql security definer set search_path=public as $$
  select count(*) from public.cards c left join public.user_card_progress p on p.card_id=c.id and p.user_id=auth.uid()
  where c.active and(p.due_at is null or p.due_at<=now())
$$;

create or replace function public.record_review(reviewed_card_id uuid,review_rating text,next_state jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or review_rating not in('AGAIN','HARD','GOOD','EASY') then raise exception 'invalid review'; end if;
  insert into public.user_card_progress(user_id,card_id,due_at,interval_days,ease_factor,repetitions,lapses,last_reviewed_at)
  values(auth.uid(),reviewed_card_id,(next_state->>'due_at')::timestamptz,(next_state->>'interval_days')::numeric,(next_state->>'ease_factor')::numeric,(next_state->>'repetitions')::int,(next_state->>'lapses')::int,(next_state->>'last_reviewed_at')::timestamptz)
  on conflict(user_id,card_id) do update set due_at=excluded.due_at,interval_days=excluded.interval_days,ease_factor=excluded.ease_factor,repetitions=excluded.repetitions,lapses=excluded.lapses,last_reviewed_at=excluded.last_reviewed_at;
  insert into public.study_reviews(user_id,card_id,rating,resulting_state) values(auth.uid(),reviewed_card_id,review_rating,next_state);
end$$;

grant execute on function public.get_due_cards(integer) to authenticated;
grant execute on function public.due_card_count() to authenticated;
grant execute on function public.record_review(uuid,text,jsonb) to authenticated;

create or replace function public.import_source_cards(
  source_drive_id text, source_name text, source_kind public.card_kind,
  source_modified_at timestamptz, source_hash text, imported_cards jsonb
) returns integer language plpgsql security definer set search_path=public as $$
declare source_id uuid; item jsonb; imported_count integer:=0;
begin
  insert into public.source_files(drive_file_id,file_name,kind,drive_modified_at,content_hash,last_sync_at)
  values(source_drive_id,source_name,source_kind,source_modified_at,source_hash,now())
  on conflict(drive_file_id) do update set file_name=excluded.file_name,kind=excluded.kind,drive_modified_at=excluded.drive_modified_at,content_hash=excluded.content_hash,last_sync_at=now()
  returning id into source_id;
  update public.cards set active=false,updated_at=now() where source_file_id=source_id;
  for item in select * from jsonb_array_elements(imported_cards) loop
    insert into public.cards(source_file_id,source_key,kind,level,part_of_speech,german,spanish,conjugations,content_hash,active)
    values(source_id,item->>'source_key',source_kind,nullif(item->>'level',''),nullif(item->>'part_of_speech',''),item->>'german',item->>'spanish',item->'conjugations',item->>'content_hash',true)
    on conflict(source_file_id,source_key) do update set level=excluded.level,part_of_speech=excluded.part_of_speech,german=excluded.german,spanish=excluded.spanish,conjugations=excluded.conjugations,content_hash=excluded.content_hash,active=true,updated_at=now();
    imported_count:=imported_count+1;
  end loop;
  return imported_count;
end$$;
revoke all on function public.import_source_cards(text,text,public.card_kind,timestamptz,text,jsonb) from public,anon,authenticated;
grant execute on function public.import_source_cards(text,text,public.card_kind,timestamptz,text,jsonb) to service_role;
