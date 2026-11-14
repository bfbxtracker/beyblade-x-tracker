-- BFB X Tracker: Admin activity and login audit log
-- Run once in Supabase SQL Editor. Does not modify existing records.

create table if not exists public.admin_activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  actor_email text,
  action text not null,
  entity_table text not null,
  record_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_activity_log_created_at_idx
  on public.admin_activity_log (created_at desc);
create index if not exists admin_activity_log_actor_email_idx
  on public.admin_activity_log (lower(actor_email));

alter table public.admin_activity_log enable row level security;

drop policy if exists "Admins read activity log" on public.admin_activity_log;
create policy "Admins read activity log"
  on public.admin_activity_log for select to authenticated
  using (exists (
    select 1 from public.admin_users au
    where au.user_id = auth.uid()
  ));

drop policy if exists "Users log own sign in" on public.admin_activity_log;
create policy "Users log own sign in"
  on public.admin_activity_log for insert to authenticated
  with check (
    actor_user_id = auth.uid()
    and action = 'LOGIN'
    and entity_table = 'auth'
  );

create or replace function public.bfbx_write_activity_log()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_id text;
  v_email text;
  v_details jsonb;
begin
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    v_old := v_row;
  elsif tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    v_old := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;

  v_id := coalesce(v_row->>'id', v_row->>'user_id', v_row->>'email');
  v_email := coalesce(auth.jwt()->>'email', 'Unknown authenticated account');
  v_details := jsonb_build_object(
    'summary', coalesce(v_row->>'name', v_row->>'full_name', v_row->>'finish_type', v_row->>'email', v_id),
    'after', case when tg_op = 'DELETE' then null else v_row end,
    'before', case when tg_op = 'INSERT' then null else v_old end
  );

  insert into public.admin_activity_log
    (actor_user_id, actor_email, action, entity_table, record_id, details)
  values
    (auth.uid(), v_email, tg_op, tg_table_name, v_id, v_details);

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- Record changes made through the application or Supabase SQL/API as long as
-- an authenticated user context is present.
do $$
declare
  t text;
begin
  foreach t in array array[
    'players',
    'combos',
    'tournaments',
    'matches',
    'scoring',
    'tournament_groups',
    'tournament_participants',
    'approved_viewers'
  ]
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists bfbx_activity_audit on public.%I', t);
      execute format(
        'create trigger bfbx_activity_audit after insert or update or delete on public.%I for each row execute function public.bfbx_write_activity_log()',
        t
      );
    end if;
  end loop;
end;
$$;

grant select, insert on public.admin_activity_log to authenticated;
revoke all on public.admin_activity_log from anon;
