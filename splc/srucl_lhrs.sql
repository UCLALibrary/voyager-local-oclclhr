set linesize 20;
set trimout on;

define last_date = &1;

with srucl as (
  select
    mfhd_id
  from ucladb.mfhd_master mm
  inner join ucladb.location l on mm.location_id = l.location_id
  where l.location_code = 'srucl'
)
, updates as (
  -- srucl holdings updated since last_date
  select mfhd_id
  from ucladb.mfhd_history
  where mfhd_id in (select mfhd_id from srucl)
  and action_date >= to_date('&last_date', 'YYYYMMDD')
  and operator_id != 'nomelvyl'
  union
  -- srucl holdings, if their *bibs* were updated since last_date
  select s.mfhd_id
  from srucl s
  inner join ucladb.bib_mfhd bm on s.mfhd_id = bm.mfhd_id
  inner join ucladb.bib_history bh on bm.bib_id = bh.bib_id
  where bh.action_date >= to_date('&last_date', 'YYYYMMDD')
  and bh.operator_id != 'nomelvyl'
)
-- Tab-delimited output
-- Use concatentation so sqlplus will not pad with spaces
select
    u.mfhd_id
||  chr(9)
||  ( select replace(normal_heading, 'UCOCLC', '')
    from ucladb.bib_index
    where bib_id = bm.bib_id
    and index_code = '0350'
    and normal_heading like 'UCOCLC%'
    and rownum < 2
  ) as oclc
from updates u
inner join ucladb.mfhd_master mm on u.mfhd_id = mm.mfhd_id
inner join ucladb.location l on mm.location_id = l.location_id
inner join ucladb.bib_mfhd bm on mm.mfhd_id = bm.mfhd_id
inner join ucladb.bib_text bt on bm.bib_id = bt.bib_id
inner join ucladb.bib_master br on bm.bib_id = br.bib_id
where l.location_code = 'srucl'
and exists (
  select *
  from ucladb.bib_index
  where bib_id = bm.bib_id
  and index_code = '0350'
  and normal_heading like 'UCOCLC%'
)
order by u.mfhd_id
;
