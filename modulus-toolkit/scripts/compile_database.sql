set pagesize 500;
SET SERVEROUTPUT ON;
SET FEEDBACK OFF;
--SPOOL output_compile_database.sql
--
prompt Compiling all invalid database objects.
prompt This may take some time ...
--
declare
  --------------------------------------------------------------------------
  procedure exec_sql(
  --------------------------------------------------------------------------
    pSQL in varchar2
    ) is
  --------------------------------------------------------------------------
  --
  --------------------------------------------------------------------------
    v_cursor integer;
    v_error  integer;
  begin
    -- dbms_output.put_line ('exec '||pSQL);
    v_cursor := dbms_sql.open_cursor;
    dbms_sql.parse(v_cursor, pSQL,dbms_sql.native);
    v_error  := dbms_sql.execute(v_cursor);
    dbms_sql.close_cursor(v_cursor);

  exception
    when others then
      dbms_sql.close_cursor(v_cursor);
  end;

begin
   exec_sql ('drop table t_compile_schema');
-- create global temporary table t_compile_schema (
   exec_sql ('create table t_compile_schema ('
             ||' object_type    varchar2(32),'
             ||' object_name    varchar2(70),'
             ||' compile_option varchar2(32),'
             ||' dlevel         number)'
	    );
--  on commit preserve rows
end;
/

declare
--
 TYPE ObjRecTyp is RECORD
 (    objtype   varchar2(30),
      objname   varchar2(70),
      compopt   varchar2(20) );
--
 TYPE ObjTabTyp is TABLE of ObjRecTyp
 INDEX by BINARY_INTEGER;
--
cursor c0 is
 select count(*)
 from   dba_objects
 where  status = 'INVALID';
--
cursor c1 (p_object_id in number) is
 select substr(decode(u.object_type,'PACKAGE BODY','PACKAGE'
                                   , u.object_type),1,30)          object_type,
        u.owner||'."'||substr(u.object_name,1,30)||'"'             object_name,
        decode(u.object_Type, 'PACKAGE BODY', 'compile body',
                              'compile' )                          compile_option,
               o.dlevel                                            dlevel
 from   dba_objects                   u,
        (
          select max(level)   dlevel,
                 object_id
            from public_dependency
           start with object_id = p_object_id
         connect by object_id = prior referenced_object_id
           group by object_id
        )                              o
 where  status       = 'INVALID'
 and    u.object_id  = o.object_id (+)
 and    u.object_id  = p_object_id
 and    u.object_type in ( 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE',
                           'TRIGGER', 'VIEW' )
 order by o.dlevel DESC;
--
 ObjTab  ObjTabTyp;
 txt     varchar2(2000);
 num     number;
 cnt     number := 0;
 passes  number := 0;
 CHandle PLS_INTEGER;

--
begin
  dbms_output.enable (10000000);
  -- fill t_compile_schema
  for r_data in (
    select object_id
      from dba_objects
    )
  loop
    begin
      for r_data_c1 in c1(r_data.object_id) loop
        insert into t_compile_schema (
          object_type,
          object_name,
          compile_option,
          dlevel
          )
        values (
          r_data_c1.object_type,
          r_data_c1.object_name,
          r_data_c1.compile_option,
          r_data_c1.dlevel
          );
      end loop;
    exception
      when others then
        null;
    end;
  end loop;
  --
  cnt := 0;
  for r_data in (
    select object_type,
           object_name,
           compile_option
      from t_compile_schema
     order by dlevel desc
    )
  loop
    --
    cnt := cnt + 1;
    ObjTab(cnt).objtype := r_data.object_type;
    ObjTab(cnt).ObjName := r_data.object_name;
    ObjTab(cnt).CompOpt := r_data.compile_option;
    --
 end loop;
--
 cnt := 0;
--
 for j in 1 .. ObjTab.COUNT loop
   begin
     --
     txt := 'alter '||ObjTab(j).ObjType||' '||ObjTab(j).ObjName||' '||
            ObjTab(j).CompOpt;

     dbms_output.put_line (txt);
     --
     CHandle := DBMS_SQL.OPEN_CURSOR;
     DBMS_SQL.PARSE( CHandle, txt, DBMS_SQL.NATIVE );
     DBMS_SQL.CLOSE_CURSOR( CHandle );
     --
   exception
     when others then
       dbms_sql.close_cursor(CHandle);
       -- ignore errors !!
   end;
 end loop;
--
 ObjTab.delete;
--
 open c0; fetch c0 into num; close c0;
--
if num > 0 then
   txt := 'There are still '||to_char(num)||' objects to be recompiled '||
          '- try running this script again, or check database for errors.';
else
   txt := 'All database objects have been successfully compiled.';
end if;
--
sys.dbms_output.put_line( chr(10) );
sys.dbms_output.put_line( txt );
sys.dbms_output.put_line( chr(10) );
--
end;
/
--SPOOL OFF
exit;