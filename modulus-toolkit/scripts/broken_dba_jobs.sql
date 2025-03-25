set heading off
set newpage none
set feedback off
set pagesize 500
set linesize 1000
select 
    job,
    log_user,
    priv_user, 
    schema_user,
    broken
from 
    dba_jobs
where
    broken='Y'
order by job asc;
select '  ' from dual;
exit;