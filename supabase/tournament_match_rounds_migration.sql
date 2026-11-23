-- BFB X Tracker: editable tournament match rounds
create table if not exists public.tournament_match_rounds (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint tournament_match_rounds_tournament_name_unique unique (tournament_id, name)
);

alter table public.tournament_match_rounds enable row level security;
revoke all on public.tournament_match_rounds from anon, authenticated;

create policy "Signed in members can view tournament match rounds"
on public.tournament_match_rounds for select to authenticated using (true);

create policy "Admins can create tournament match rounds"
on public.tournament_match_rounds for insert to authenticated
with check (public.is_bx_admin() or public.is_bx_content_admin());

create policy "Admins can update tournament match rounds"
on public.tournament_match_rounds for update to authenticated
using (public.is_bx_admin() or public.is_bx_content_admin())
with check (public.is_bx_admin() or public.is_bx_content_admin());

create policy "Admins can delete tournament match rounds"
on public.tournament_match_rounds for delete to authenticated
using (public.is_bx_admin() or public.is_bx_content_admin());

grant select, insert, update, delete on public.tournament_match_rounds to authenticated;

-- Preserve round names already used by match records.
insert into public.tournament_match_rounds(tournament_id,name,sort_order)
select t.id, m.round_name,
       row_number() over(partition by t.id order by
         case when m.round_name ~* '^round\s*[0-9]+' then substring(m.round_name from '[0-9]+')::int else 999 end,
         m.round_name
       )::int
from public.tournaments t
join (
  select distinct tournament_id, btrim(round_name) round_name
  from public.matches
  where tournament_id is not null and nullif(btrim(round_name),'') is not null
) m on m.tournament_id=t.id
on conflict (tournament_id,name) do nothing;

-- Keep the three existing empty rounds visible for the BeyFansX Rise Tournament.
insert into public.tournament_match_rounds(tournament_id,name,sort_order)
select t.id, 'Round '||n, n
from public.tournaments t cross join generate_series(1,3) n
where t.name ~* 'beyfans\s*x\s*rise'
  and not exists (
    select 1 from public.tournament_match_rounds r
    where r.tournament_id=t.id and r.name ~* ('^round\s*'||n::text||'$')
  )
on conflict (tournament_id,name) do nothing;
