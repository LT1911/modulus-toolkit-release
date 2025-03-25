set heading off
set newpage none
set feedback off
set pagesize 500
set linesize 1000
select 
    substr(username,1,25) as username, 
	substr(account_status,1,15) as account_status
from 
    dba_users
WHERE
    username not like 'APEX%'
AND
    username
not in
(
'ANONYMOUS',
'APPQOSSYS',
'AUDSYS',
'BOREF',
'CTXSYS',
'DBSFWUSER',
'DBSNMP',
'DIP',
'DVF',
'DVSYS',
'EMC',
'FLOWS_FILES',
'GGSYS',
'GSMADMIN_INTERNAL',
'GSMCATUSER',
'GSMUSER',
'LBACSYS',
'MDDATA',
'MDSYS',
'MGMT_VIEW',
'OJVMSYS',
'OLAPSYS',
'ORACLE_OCM',
'ORDDATA',
'ORDPLUGINS',
'ORDSYS',
'OUTLN',
'OWBSYS',
'OWBSYS_AUDIT',
'REMOTE_SCHEDULER_AGENT',
'RMANSCS',
'SCOTT',
'SI_INFORMTN_SCHEMA',
'SPATIAL_CSW_ADMIN_USR',
'SPATIAL_WFS_ADMIN_USR',
'SYS',
'SYS$UMF',
'SYSBACKUP',
'SYSDG',
'SYSKM',
'SYSMAN',
'SYSRAC',
'SYSTEM',
'WMSYS',
'XDB',
'XS$NULL'
)
order by 1 asc;
select '  ' from dual;
exit;