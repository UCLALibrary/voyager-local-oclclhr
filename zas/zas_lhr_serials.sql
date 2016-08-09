set linesize 20;
set trimout on;

define last_date = &1; 

-- Tab-delimited output
-- Use concatentation so sqlplus will not pad with spaces
with updates as (
  select bib_id
  from ucladb.bib_history
  where action_date >= to_date('&last_date', 'YYYYMMDD')
  and operator_id != 'nomelvyl'
  union
  select bm.bib_id
  from ucladb.bib_mfhd bm
  inner join ucladb.mfhd_history mh on bm.mfhd_id = mh.mfhd_id
  where mh.action_date >= to_date('&last_date', 'YYYYMMDD')
  and mh.operator_id != 'nomelvyl'
)
select /*+ index(bi BIB_INDEX_BIB_ID_IDX) */
    bm.mfhd_id
 || chr(9)
 || replace(bi.normal_heading, 'UCOCLC', '')
  as oclc
from updates u
inner join bib_text bt on u.bib_id = bt.bib_id
inner join bib_master br on bt.bib_id = br.bib_id
inner join bib_mfhd bm on br.bib_id = bm.bib_id
inner join mfhd_master mm on bm.mfhd_id = mm.mfhd_id
inner join location l on mm.location_id = l.location_id
inner join bib_index bi on u.bib_id = bi.bib_id
  and bi.index_code = '0350'
  and bi.normal_heading like 'UCOCLC%'
where (l.location_code = 'sr' or l.location_code like 'srucl%')
and mm.suppress_in_opac = 'N'
and br.suppress_in_opac = 'N'
and bt.bib_format like '%s'
-- Must have OCLC number
/*
and exists (
  select *
  from bib_index
  where bib_id = bm.bib_id
  and index_code = '0350'
  and normal_heading like 'UCOCLC%'
)
*/
-- MFHD must have items - hundreds don't
and exists (
  select *
  from mfhd_item
  where mfhd_id = mm.mfhd_id
)
order by bm.mfhd_id
;

