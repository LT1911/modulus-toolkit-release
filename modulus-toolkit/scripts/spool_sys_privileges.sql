SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF

SPOOL grant_sys_privileges.sql

select 'SPOOL output_sys_privileges.sql' from dual;
select 
    'GRANT ' || PRIVILEGE ||  ' TO ' || GRANTEE  || ';' 
from 
    dba_sys_privs 
order by 
    GRANTEE, PRIVILEGE;

select 'SPOOL OFF' from dual;
select 'exit;' from dual;

SPOOL OFF
exit;