set pagesize 500;
--SPOOL output_check_invalid_objects.sql
select 
    substr(object_name,1,40) as object_name,
    substr(owner,1,15) as schema,
    object_type 
from dba_objects 
where 
    status != 'VALID';
--SPOOL OFF
exit;