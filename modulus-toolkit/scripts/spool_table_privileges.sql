SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF

SPOOL grant_table_privileges.sql

select 'SPOOL output_table_privileges.sql' from dual;
select 
    'GRANT ' || PRIVILEGE || ' ON ' || GRANTOR || '.' || '"' || TABLE_NAME || '"' || ' TO ' || GRANTEE || (case when GRANTABLE = 'YES' then ' WITH GRANT OPTION' else '' end)  || ';' 
from 
    dba_tab_privs 
order by 
    GRANTOR, PRIVILEGE;

select 'SPOOL OFF' from dual;
select 'exit;' from dual;

SPOOL OFF
exit;