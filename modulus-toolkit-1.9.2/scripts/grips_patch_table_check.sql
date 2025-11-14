set heading off
set newpage none
set feedback off
set pagesize 500
set linesize 1000
select
	substr(module,1,20) as module,
	substr(version,1,20) as version
from 
	grips_patch_table
order by module, version;
select '  ' from dual;
exit;