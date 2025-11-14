SET LINESIZE 150
SET PAGESIZE 50
COLUMN patch_id FORMAT A20
COLUMN description FORMAT A60
COLUMN action FORMAT A10
COLUMN status FORMAT A10
--SPOOL output_oracle_patch_version.sql
SELECT 
    patch_id,
    description,
    action,
    status
FROM 
    dba_registry_sqlpatch
WHERE 
    status != 'APPLIED'
;
--SPOOL OFF
exit;