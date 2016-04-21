-- Voyager data to create CLU physical LHRs
-- other settings via vger_sqlplus_run
set linesize 20;
set trimout on;

-- Combined data for print CLU LHRs
with d as (
  select 
    b.*
  from tmp_lhr_ids b
  where source = 'print'
  and location_code not like 'sr%'
  and display_call_no is not null
  and upper(display_call_no) not like '%SUPPRESS%'
  union all
  select distinct --needed due to item-level join for restricting to UCLA items
    b.*
  from tmp_lhr_ids b
  inner join ucladb.mfhd_item mi on b.mfhd_id = mi.mfhd_id
  inner join ucladb.item_stats ist on mi.item_id = ist.item_id
  inner join vger_support.ucla_item_stat_code isc on ist.item_stat_id = isc.item_stat_id
  where b.location_code like 'sr%'
)
select 
    mfhd_id
 || chr(9)
 || oclc
from d
order by 1
;
