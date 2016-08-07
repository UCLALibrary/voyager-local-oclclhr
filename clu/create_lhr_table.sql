define last_date = &1;

drop table vger_report.tmp_lhr_ids;

-- Requires other tables in vger_report, which are rebuilt
-- daily via vger_rebuild_cataloging_reports

create table vger_report.tmp_lhr_ids as
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
, one_oclc as (
  select bib_id from updates
  minus
  select bib_id from vger_report.rpt_multiple_ucoclc
)
, bibs as (
  -- Force index use for performance, else wildcard in normal_heading causes problems
  select /*+ index(bi BIB_INDEX_BIB_ID_IDX) */
    oo.bib_id
  , replace(bi.normal_heading, 'UCOCLC', '') as oclc
  from one_oclc oo
  inner join ucladb.bib_master bm on oo.bib_id = bm.bib_id
  inner join ucladb.bib_text bt on oo.bib_id = bt.bib_id
  inner join ucladb.bib_index bi
    on oo.bib_id = bi.bib_id
    and bi.index_code = '0350'
    and bi.normal_heading like 'UCOCLC%'
  where bm.suppress_in_opac = 'N'
  and bt.bib_format like '%s'
)
, ok_910 as (
  select
    bib_id
  from vger_report.bib_f910a_data
  where f910a not in ('ACQ', 'MARS')
)
, print_bibs as (
  -- Bib record has at least one unsuppressed holdings with physical location and a call number
  select
    b.bib_id
  , mm.mfhd_id
  , b.oclc
  , l.location_code
  , mm.display_call_no
  from bibs b
  inner join ucladb.bib_mfhd bm on b.bib_id = bm.bib_id
  inner join ucladb.mfhd_master mm on bm.mfhd_id = mm.mfhd_id
  inner join ucladb.location l on mm.location_id = l.location_id
  where l.location_code not like '%acq'
  and l.location_code not like '%prscp'
  and l.location_code != 'in'
  and l.location_code not like 'sr%' -- SRLF locs have diff criteria, below
  and l.location_code not like '%wt' -- WEST shared print locs
  and l.suppress_in_opac = 'N'
  and mm.suppress_in_opac = 'N'
  and mm.normalized_call_no is not null
  and mm.normalized_call_no not like 'SUPPRESSED%' -- shouldn't be necessary but a few hundred mfhds say otherwise
  union
  -- Bib record has a 910 $a with other than ACQ or MARS, via ok_910 above
  select
    b.bib_id
  , mm.mfhd_id
  , b.oclc
  , l.location_code
  , mm.display_call_no
  from bibs b
  inner join ucladb.bib_mfhd bm on b.bib_id = bm.bib_id
  inner join ucladb.mfhd_master mm on bm.mfhd_id = mm.mfhd_id
  inner join ucladb.location l on mm.location_id = l.location_id
  inner join ok_910 o on b.bib_id = o.bib_id
  where l.location_code not like '%acq'
  and l.location_code not like '%prscp'
  and l.location_code != 'in'
  and l.suppress_in_opac = 'N'
  and mm.suppress_in_opac = 'N'
  union
  -- Bib record has at least one unsuppressed SRLF holdings record
  --  which has UCLA item(s) linked to it
  select
    b.bib_id
  , mm.mfhd_id
  , b.oclc
  , l.location_code
  , mm.display_call_no
  from bibs b
  inner join ucladb.bib_mfhd bm on b.bib_id = bm.bib_id
  inner join ucladb.mfhd_master mm on bm.mfhd_id = mm.mfhd_id
  inner join ucladb.location l on mm.location_id = l.location_id
  inner join ucladb.mfhd_item mi on mm.mfhd_id = mi.mfhd_id
  inner join ucladb.item_stats ist on mi.item_id = ist.item_id
  inner join vger_support.ucla_item_stat_code isc on ist.item_stat_id = isc.item_stat_id
  where l.location_code like 'sr%' -- yes, srbuo is included in CLU LHRs
  and l.suppress_in_opac = 'N'
  and mm.suppress_in_opac = 'N'
)
, internet_bibs as (
  select distinct
    b.bib_id
  , null as mfhd_id
  , b.oclc
  , 'in' as location_code
  , null as display_call_no
  from bibs b
  inner join ok_910 o on b.bib_id = o.bib_id
  -- Faster than inner join with ucladb_bib_subfield for 856 $x
  where exists (
    select * from vger_subfields.ucladb_bib_subfield
    where record_id = b.bib_id
    and tag = '856x'
    and upper(subfield) like '%UCLA%'
  )
)
select
  'print' as source
, bib_id
, mfhd_id
, oclc
, location_code
, display_call_no
from print_bibs
union all
select
  'internet' as source
, bib_id
, mfhd_id
, oclc
, location_code
, display_call_no
from internet_bibs
;

