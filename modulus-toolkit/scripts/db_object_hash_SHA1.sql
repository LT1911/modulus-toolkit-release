Rem  Copyright (c) MODULUS 2023. All Rights Reserved.
Rem
Rem    NAME
Rem      db_object_hash_SHA1.sql
Rem
Rem    DESCRIPTION
Rem
Rem    NOTES
Rem
Rem    REQUIREMENTS
Rem      - Oracle Database 10.2.0.2 or later
Rem      - Star JACKPOT 3.09.00 or later (will report ***missing*** if not installed)
Rem      - Galaxis 940 or later (will report ***missing*** if not installed)
Rem
Rem    Arguments:
Rem     Position 1: Name of the schema of the Jackpot schema
Rem     Position 2: Name of the schema of the Galaxis schema
Rem     Position 3: Name of the schema of the MIS schema
Rem
Rem    Example:
Rem
Rem      sqlplus "sys/sysdba@<db> as sysdba" @db_object_hash_SHA1.sql AS_JACKPOT GALAXIS MIS
Rem

set define '^'
set concat on
set concat .
set line 2000
set trimspool on
set verify off
set feedback off
set termout off
spool off
set termout on
set serveroutput on

define jpowner       = '^1'
define glxowner      = '^2'
define misowner       = '^3'

column foo3 new_val LOG1
select 'sh1-'||to_char(sysdate,'YYYY-MM-DD_HH24-MI-SS')||'.log' as foo3 from sys.dual;
spool ^LOG1

prompt .
prompt . MODULUS Casino System Database Object SHA1 Hash
prompt .................................................
prompt .

declare
  function CalculateSHA1(pOwner varchar2, pObjectName varchar2) return varchar2 is
    source clob := empty_clob;
    hash raw(45);
    rowcount number := 0;
    
    cursor cSource(pOwner varchar2, pName varchar2) is
      select text
      from dba_source
      where type != 'PACKAGE'
        and name = upper(pName)
        and owner = upper(pOwner)
      order by line;
  begin
    dbms_lob.createTemporary(source, true);
    dbms_lob.open (source, dbms_lob.lob_readwrite);
    
    for rS in cSource(pOwner, pObjectName) loop
      rowcount := rowcount+1;
      dbms_lob.writeappend (source, length(rS.text), rS.text);
    end loop;
    
    hash := dbms_crypto.hash(source, dbms_crypto.hash_sh1);
    
    dbms_lob.close(source);
    dbms_lob.freeTemporary(source);
    
    if rowcount > 0 then
      return cast(hash as varchar2);
    end if;
    return '***missing***';
  exception
    when others then
      dbms_lob.close(source);
      dbms_lob.freeTemporary(source);
      raise;
  end CalculateSHA1;
  
begin
  dbms_output.put_line('.');
  dbms_output.put_line('Star JACKPOT');
  dbms_output.put_line('------------');
  dbms_output.put_line('^jpowner'||'.dbx'||' => '||nvl(CalculateSHA1('^jpowner', 'dbx'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.dbx_init'||' => '||nvl(CalculateSHA1('^jpowner', 'dbx_init'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_contrib'||' => '||nvl(CalculateSHA1('^jpowner', 'jp_contrib'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_engine'||' => '||nvl(CalculateSHA1('^jpowner', 'jp_engine'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_group'||' => '||nvl(CalculateSHA1('^jpowner', 'jp_group'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_instance'||' => '||nvl(CalculateSHA1('^jpowner', 'jp_instance'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.slotmachine'||' => '||nvl(CalculateSHA1('^jpowner', 'slotmachine'), '***missing***'));
  dbms_output.put_line('.');
  dbms_output.put_line('GALAXIS');
  dbms_output.put_line('-------');
  dbms_output.put_line('^misowner'||'.MOVEMENT'||' => '||nvl(CalculateSHA1('^misowner', 'MOVEMENT'), '***missing***'));
  dbms_output.put_line('^misowner'||'.PRUNE'||' => '||nvl(CalculateSHA1('^misowner', 'PRUNE'), '***missing***'));
  dbms_output.put_line('^misowner'||'.METERREPORT'||' => '||nvl(CalculateSHA1('^misowner', 'METERREPORT'), '***missing***'));
end;
/
spool off
exit
--prompt .
--prompt . Enter "exit" to close SQL*Plus now
--prompt .