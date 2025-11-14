Rem  Copyright (c) Modulus 2023. All Rights Reserved.
Rem
Rem    NAME
Rem      db_object_hash_new.sql
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
Rem      sqlplus "sys/sysdba@<db> as sysdba" @db_object_hash_new.sql AS_JACKPOT GALAXIS MIS
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
select 'sh1-sh256-'||to_char(sysdate,'YYYY-MM-DD_HH24-MI-SS')||'.log' as foo3 from sys.dual;
spool ^LOG1

prompt .
prompt . Modulus Casino System Database Object SHA1 and SHA256 Hashes
prompt ................................................................
prompt .
declare
  function NormalizeSource(pText varchar2) return varchar2 is
    normalized_text varchar2(32767);
  begin
    -- Convert to UPPERCASE first
    normalized_text := UPPER(pText);
    -- Remove ALL whitespace characters (spaces, tabs, carriage returns, line feeds)
    -- Remove spaces
    normalized_text := REPLACE(normalized_text, ' ', '');
    -- Remove tabs
    normalized_text := REPLACE(normalized_text, CHR(9), '');
    -- Remove carriage returns
    normalized_text := REPLACE(normalized_text, CHR(13), '');
    -- Remove line feeds
    normalized_text := REPLACE(normalized_text, CHR(10), '');
    
    return normalized_text;
  end NormalizeSource;
  
  procedure PrintNormalizedSource(pOwner varchar2, pObjectName varchar2) is
    normalized_line varchar2(32767);
    full_normalized clob := empty_clob;
    
    cursor cSource(pOwner varchar2, pName varchar2) is
      select text
      from dba_source
      where type != 'PACKAGE'
        and name = upper(pName)
        and owner = upper(pOwner)
      order by line;
  begin
    dbms_output.put_line('=== Normalized Source for ' || pOwner || '.' || pObjectName || ' ===');
    
    dbms_lob.createTemporary(full_normalized, true);
    dbms_lob.open(full_normalized, dbms_lob.lob_readwrite);
    
    for rS in cSource(pOwner, pObjectName) loop
      -- Normalize the source line (UPPERCASE + remove all spaces)
      normalized_line := NormalizeSource(rS.text);
      -- Append to the full normalized string
      if LENGTH(normalized_line) > 0 then
        dbms_lob.writeappend(full_normalized, length(normalized_line), normalized_line);
      end if;
    end loop;
    
    -- Print the complete normalized source (all spaces removed, continuous string, UPPERCASE)
    if dbms_lob.getlength(full_normalized) > 0 then
      -- Print in chunks if too long for dbms_output
      declare
        chunk_size number := 2000;
        pos number := 1;
        chunk varchar2(2000);
        total_length number := dbms_lob.getlength(full_normalized);
      begin
        while pos <= total_length loop
          chunk := dbms_lob.substr(full_normalized, least(chunk_size, total_length - pos + 1), pos);
          dbms_output.put_line(chunk);
          pos := pos + chunk_size;
        end loop;
      end;
    else
      dbms_output.put_line('***empty or missing***');
    end if;
    
    dbms_lob.close(full_normalized);
    dbms_lob.freeTemporary(full_normalized);
    
    dbms_output.put_line('=== End of Normalized Source ===');
    dbms_output.put_line('.');
  end PrintNormalizedSource;
  
  function CalculateSHA1(pOwner varchar2, pObjectName varchar2) return varchar2 is
    source clob := empty_clob;
    hash raw(45);
    rowcount number := 0;
    normalized_line varchar2(32767);
    
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
      -- Normalize the source line before appending (UPPERCASE + remove ALL spaces)
      normalized_line := NormalizeSource(rS.text);
      -- Only append if there's content after normalization
      if LENGTH(normalized_line) > 0 then
        dbms_lob.writeappend (source, length(normalized_line), normalized_line);
      end if;
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
 
  function CalculateSHA256(pOwner varchar2, pObjectName varchar2) return varchar2 is
    source clob := empty_clob;
    hash raw(64);
    rowcount number := 0;
    normalized_line varchar2(32767);
    salt varchar2(8) := UTL_RAW.CAST_TO_VARCHAR2(HEXTORAW('0000000000000000'));

	
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
    dbms_lob.writeappend (source, length(salt), salt);

	
    for rS in cSource(pOwner, pObjectName) loop
      rowcount := rowcount+1;
      -- Normalize the source line before appending (UPPERCASE + remove ALL spaces)
      normalized_line := NormalizeSource(rS.text);
      -- Only append if there's content after normalization
      if LENGTH(normalized_line) > 0 then
        dbms_lob.writeappend (source, length(normalized_line), normalized_line);
      end if;
    end loop;

	
    hash := dbms_crypto.hash(source, dbms_crypto.hash_sh256);
    
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
  end CalculateSHA256;
  
begin
  dbms_output.put_line('SHA-1 hashes:');
  dbms_output.put_line('.');
  dbms_output.put_line('GALAXIS JACKPOT');
  dbms_output.put_line('------------');
  
  -- Print normalized source before hash calculation for each object
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
  
  dbms_output.put_line('.');
  dbms_output.put_line('.');
  dbms_output.put_line('SHA-256 hashes:');
  dbms_output.put_line('.');
  dbms_output.put_line('SHA-256 SALT (HEX) = 0000 0000 0000 0000');
  dbms_output.put_line('.');
  dbms_output.put_line('Star JACKPOT');
  dbms_output.put_line('------------');
  dbms_output.put_line('^jpowner'||'.dbx'||' => '||nvl(CalculateSHA256('^jpowner', 'dbx'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.dbx_init'||' => '||nvl(CalculateSHA256('^jpowner', 'dbx_init'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_contrib'||' => '||nvl(CalculateSHA256('^jpowner', 'jp_contrib'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_engine'||' => '||nvl(CalculateSHA256('^jpowner', 'jp_engine'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_group'||' => '||nvl(CalculateSHA256('^jpowner', 'jp_group'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.jp_instance'||' => '||nvl(CalculateSHA256('^jpowner', 'jp_instance'), '***missing***'));
  dbms_output.put_line('^jpowner'||'.slotmachine'||' => '||nvl(CalculateSHA256('^jpowner', 'slotmachine'), '***missing***'));
  dbms_output.put_line('.');
  dbms_output.put_line('GALAXIS');
  dbms_output.put_line('-------');
  dbms_output.put_line('^misowner'||'.MOVEMENT'||' => '||nvl(CalculateSHA256('^misowner', 'MOVEMENT'), '***missing***'));
  dbms_output.put_line('^misowner'||'.PRUNE'||' => '||nvl(CalculateSHA256('^misowner', 'PRUNE'), '***missing***'));
  dbms_output.put_line('^misowner'||'.METERREPORT'||' => '||nvl(CalculateSHA256('^misowner', 'METERREPORT'), '***missing***'));
end;
/
spool off
prompt .
prompt . Enter "exit" to close SQL*Plus now
prompt .
exit