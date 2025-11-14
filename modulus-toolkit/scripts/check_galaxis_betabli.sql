set heading off
set newpage none
set feedback off
set pagesize 500
set linesize 1000
select
	COD_SOCIET,
    COD_ETABLI,
    ID_CASINO,
    NOM_ETABLI,
    NOM_COURT,
    DIRECTION,
    COD_LANGUE
from 
	galaxis.betabli;
select '  ' from dual;
exit;