-- Prefer the nearest future tournament on the public dashboard.
-- If none is upcoming, show today's tournament, then the most recent past tournament.
create or replace function public.get_public_dashboard()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
with player_match_rows as (
  select m.player1_id as player_id,
    case when m.player1_points > m.player2_points then 1 else 0 end as wins,
    case when m.player1_points < m.player2_points then 1 else 0 end as losses,
    case when m.player1_points = m.player2_points then 1 else 0 end as draws,
    (m.player1_points - m.player2_points) as margin
  from public.matches m
  union all
  select m.player2_id as player_id,
    case when m.player2_points > m.player1_points then 1 else 0 end as wins,
    case when m.player2_points < m.player1_points then 1 else 0 end as losses,
    case when m.player2_points = m.player1_points then 1 else 0 end as draws,
    (m.player2_points - m.player1_points) as margin
  from public.matches m
),
player_totals as (
  select p.id,p.name,
    coalesce(sum(r.wins),0)::integer as wins,
    coalesce(sum(r.losses),0)::integer as losses,
    coalesce(sum(r.draws),0)::integer as draws,
    coalesce(sum(r.margin),0)::integer as margin
  from public.players p
  left join player_match_rows r on r.player_id = p.id
  group by p.id,p.name
),
featured as (
  select jsonb_build_object(
    'name',t.name,
    'tournament_date',t.tournament_date,
    'location',t.location,
    'format',t.format,
    'banner_image_url',t.banner_image_url,
    'background_text',t.background_text
  ) as item
  from public.tournaments t
  order by
    case
      when t.tournament_date > current_date then 0
      when t.tournament_date = current_date then 1
      when t.tournament_date is not null then 2
      else 3
    end,
    case when t.tournament_date > current_date then t.tournament_date end asc,
    case when t.tournament_date = current_date then t.created_at end desc,
    case when t.tournament_date < current_date then t.tournament_date end desc,
    t.created_at desc nulls last
  limit 1
)
select jsonb_build_object(
  'players_count',(select count(*) from public.players),
  'combos_count',(select count(*) from public.combos),
  'matches_count',(select count(*) from public.matches),
  'tournaments_count',(select count(*) from public.tournaments),
  'winners_count',(select count(*) from player_totals where wins > 0),
  'featured_tournament',(select item from featured),
  'top_players',coalesce((
    select jsonb_agg(
      jsonb_build_object('name',name,'wins',wins)
      order by wins desc,margin desc,name asc
    )
    from player_totals
  ),'[]'::jsonb)
);
$function$;
