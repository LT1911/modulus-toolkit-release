SET SERVEROUTPUT ON;
--SPOOL output_recomp_serial.sql
exec utl_recomp.recomp_serial();
--SPOOL OFF
exit;