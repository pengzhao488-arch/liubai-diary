-- Run once in your own Supabase SQL Editor. No diary data or credentials here.
create table if not exists public.diary_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date text not null check (date ~ '^\d{4}-\d{2}-\d{2}$'),
  title text not null check (length(title) <= 200),
  body text not null check (length(body) <= 100000),
  mood text not null,
  deleted boolean not null default false,
  version integer not null default 1 check (version > 0),
  updated_at timestamptz not null default now()
);
create index if not exists diary_entries_user on public.diary_entries(user_id);
alter table public.diary_entries enable row level security;
drop policy if exists own_diaries_read on public.diary_entries;
create policy own_diaries_read on public.diary_entries for select to authenticated
  using ((select auth.uid()) = user_id);
-- Writes only through the version-checked RPC; clients cannot bypass it.
revoke all on public.diary_entries from anon, authenticated;
grant select on public.diary_entries to authenticated;

create or replace function public.save_diary(
  p_id uuid, p_date text, p_title text, p_body text, p_mood text,
  p_version integer, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  current_row public.diary_entries;
begin
  if uid is null then raise exception 'Login required'; end if;
  if p_version < 0 then raise exception 'Invalid version'; end if;
  -- Serialize writes, including simultaneous first inserts, for this entry id.
  perform pg_advisory_xact_lock(hashtextextended(p_id::text, 0));
  select * into current_row from public.diary_entries where id = p_id;
  if found then
    if current_row.user_id <> uid then raise exception 'Entry unavailable'; end if;
    if current_row.version <> p_version then
      return jsonb_build_object('conflict', true, 'entry', to_jsonb(current_row));
    end if;
    update public.diary_entries set date=p_date, title=p_title, body=p_body,
      mood=p_mood, deleted=p_deleted, version=version+1, updated_at=now()
      where id=p_id and user_id=uid returning * into current_row;
  else
    if p_version <> 0 then raise exception 'Entry missing; restore from a backup'; end if;
    insert into public.diary_entries(id,user_id,date,title,body,mood,deleted)
      values(p_id,uid,p_date,p_title,p_body,p_mood,p_deleted) returning * into current_row;
  end if;
  return jsonb_build_object('conflict', false, 'entry', to_jsonb(current_row));
end;
$$;
revoke all on function public.save_diary(uuid,text,text,text,text,integer,boolean) from public, anon;
grant execute on function public.save_diary(uuid,text,text,text,text,integer,boolean) to authenticated;
