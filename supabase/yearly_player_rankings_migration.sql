-- BFB X Tracker: editable annual overall standings
create table if not exists public.yearly_player_rankings (
  season_year integer not null check (season_year between 2000 and 2200),
  player_id uuid not null references public.players(id) on delete cascade,
  rank integer not null check (rank >= 1),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (season_year, player_id),
  constraint yearly_player_rankings_year_rank_unique unique (season_year, rank)
);

alter table public.yearly_player_rankings enable row level security;
revoke all on public.yearly_player_rankings from anon, authenticated;

create policy "Admins can read yearly player rankings"
on public.yearly_player_rankings for select to authenticated
using (public.is_bx_admin() or public.is_bx_content_admin());
create policy "Admins can insert yearly player rankings"
on public.yearly_player_rankings for insert to authenticated
with check (public.is_bx_admin() or public.is_bx_content_admin());
create policy "Admins can update yearly player rankings"
on public.yearly_player_rankings for update to authenticated
using (public.is_bx_admin() or public.is_bx_content_admin())
with check (public.is_bx_admin() or public.is_bx_content_admin());
create policy "Admins can delete yearly player rankings"
on public.yearly_player_rankings for delete to authenticated
using (public.is_bx_admin() or public.is_bx_content_admin());
grant select, insert, update, delete on public.yearly_player_rankings to authenticated;

create or replace function public.get_public_yearly_standings(p_year integer default extract(year from current_date)::integer)
returns jsonb language sql stable security definer set search_path = public
as $function$
  select jsonb_build_object(
    'year', p_year,
    'players', coalesce(jsonb_agg(jsonb_build_object(
      'player_id', p.id, 'player_name', p.name, 'viewer_name', p.viewer_name,
      'team', p.team, 'is_verified', p.auth_user_id is not null, 'rank', r.rank
    ) order by r.rank nulls last, lower(coalesce(nullif(btrim(p.name), ''), ''))),'[]'::jsonb)
  )
  from public.players p
  left join public.yearly_player_rankings r on r.player_id=p.id and r.season_year=p_year;
$function$;

create or replace function public.set_yearly_player_rank(p_year integer,p_player_id uuid,p_rank integer)
returns void language plpgsql security invoker set search_path = public
as $function$
declare v_old_rank integer; v_conflict_player uuid; v_temp_rank integer;
begin
  if auth.uid() is null or not (public.is_bx_admin() or public.is_bx_content_admin()) then
    raise exception 'Only admins and content admins can edit yearly rankings' using errcode='42501';
  end if;
  if p_year is null or p_year<2000 or p_year>2200 then
    raise exception 'Invalid ranking year' using errcode='22023';
  end if;
  if p_rank is not null and (p_rank<1 or p_rank>10000) then
    raise exception 'Rank must be between 1 and 10000' using errcode='22023';
  end if;
  if not exists(select 1 from public.players where id=p_player_id) then
    raise exception 'Player not found' using errcode='23503';
  end if;
  select rank into v_old_rank from public.yearly_player_rankings
    where season_year=p_year and player_id=p_player_id for update;
  if p_rank is null then
    delete from public.yearly_player_rankings where season_year=p_year and player_id=p_player_id;
    return;
  end if;
  select player_id into v_conflict_player from public.yearly_player_rankings
    where season_year=p_year and rank=p_rank and player_id<>p_player_id for update;
  if v_conflict_player is not null then
    select coalesce(max(rank),0)+1 into v_temp_rank from public.yearly_player_rankings where season_year=p_year;
    update public.yearly_player_rankings set rank=v_temp_rank,updated_at=now(),updated_by=auth.uid()
      where season_year=p_year and player_id=v_conflict_player;
  end if;
  insert into public.yearly_player_rankings(season_year,player_id,rank,updated_at,updated_by)
    values(p_year,p_player_id,p_rank,now(),auth.uid())
    on conflict(season_year,player_id) do update
      set rank=excluded.rank,updated_at=now(),updated_by=excluded.updated_by;
  if v_conflict_player is not null and v_old_rank is not null then
    update public.yearly_player_rankings set rank=v_old_rank,updated_at=now(),updated_by=auth.uid()
      where season_year=p_year and player_id=v_conflict_player;
  end if;
end;
$function$;

revoke all on function public.get_public_yearly_standings(integer) from public;
grant execute on function public.get_public_yearly_standings(integer) to anon,authenticated;
revoke all on function public.set_yearly_player_rank(integer,uuid,integer) from public,anon;
grant execute on function public.set_yearly_player_rank(integer,uuid,integer) to authenticated;
