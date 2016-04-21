-- Voyager data to create CLU internet LHRs
-- other settings via vger_sqlplus_run
set linesize 20;
set trimout on;

select distinct
    bib_id
 || chr(9)
 || oclc
from vger_report.tmp_lhr_ids
where source = 'internet'
order by 1 
;
