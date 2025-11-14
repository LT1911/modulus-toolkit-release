-- fix_broken_jobs.sql
-- Purpose: Clear the BROKEN flag for all DBMS_JOB jobs where BROKEN='Y'
-- Usage:   sqlplus /nolog @fix_broken_jobs.sql
-- Notes:   Run with a user that can SELECT from DBA_JOBS and EXEC DBMS_JOB.

set termout on verify off echo off feedback on
set serveroutput on size unlimited
set lines 200 pages 200

prompt ===============================================
prompt   DBMS_JOB - Clear BROKEN flag for all jobs
prompt ===============================================

-- OPTIONAL: do your connect here (uncomment & edit if you like)
-- conn sys/<password>@GLX as sysdba

prompt
prompt [BEFORE] Jobs currently broken:
col schema_user format a20
col what        format a60
select job,
       substr(schema_user,1,20) as schema_user,
       substr(what,1,60)        as what,
       failures,
       to_char(next_date,'YYYY-MM-DD HH24:MI:SS') as next_date,
       interval
from   dba_jobs
where  broken = 'Y'
order  by job;

declare
  cursor c_jobs is
    select job, schema_user, what
    from   dba_jobs
    where  broken = 'Y'
    order  by job;

  v_count_attempted integer := 0;
  v_count_fixed     integer := 0;
begin
  dbms_output.put_line(chr(10) || '--- Clearing BROKEN flag ---');

  for r in c_jobs loop
    v_count_attempted := v_count_attempted + 1;
    begin
      dbms_output.put_line('Fixing JOB '||r.job||' ('||r.schema_user||') ...');

      -- Clear the BROKEN flag
      dbms_job.broken(r.job, false);

      -- (Optional) If you want to push the next run time forward when it's in the past,
      -- uncomment the next line (e.g., run again in 5 minutes):
      -- dbms_job.next_date(r.job, sysdate + 5/1440);

      v_count_fixed := v_count_fixed + 1;
    exception
      when others then
        dbms_output.put_line('  -> Failed for JOB '||r.job||': '||sqlerrm);
        -- continue with the next job
    end;
  end loop;

  commit;

  dbms_output.put_line('--- Done ---');
  dbms_output.put_line('Jobs attempted: '||v_count_attempted);
  dbms_output.put_line('Jobs fixed:     '||v_count_fixed);
end;
/
show errors

prompt
prompt [AFTER] Remaining jobs still broken (should be none):
select job,
       substr(schema_user,1,20) as schema_user,
       substr(what,1,60)        as what,
       failures,
       to_char(next_date,'YYYY-MM-DD HH24:MI:SS') as next_date,
       interval
from   dba_jobs
where  broken = 'Y'
order  by job;

-- exit SQL*Plus if this script was started with @
exit
