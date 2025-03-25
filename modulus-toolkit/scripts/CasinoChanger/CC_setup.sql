--as sysdba

--table with all columns that need to be updated
CREATE TABLE MOD_columns_to_update (
    schema_name       VARCHAR2(40),
    table_name        VARCHAR2(40),
    column_name       VARCHAR2(40),
    column_identifier VARCHAR2(20)
);

--filling table with all relevant columns
--truncate table MOD_columns_to_update;
INSERT INTO MOD_columns_to_update (schema_name, table_name, column_name)
SELECT 
    DISTINCT owner, table_name, column_name
FROM 
    dba_tab_columns
WHERE 
    1=1
AND table_name not like 'BIN$%'
--AND object_type = 'TABLE' -- Exclude views
AND table_name IN (SELECT table_name FROM dba_tables WHERE owner = dba_tab_columns.owner) -- Exclude views
AND
    (
    column_name IN ('ID_CASINO', 'CASINO_ID', 'COD_ETABLI', 'COD_SOCIET', 'NOM_COURT', 'SITEID')
    or column_name like '%ETABLI%'
    or column_name like '%SOCIET%'
    --or column_name like '%CAS%' --too generic, delivers too much
    )
ORDER BY 
    owner, table_name, column_name ASC;  

--filling column_identifier
--helper to find all distinct column_names
--select distinct(column_name) from MOD_columns_to_update;
UPDATE MOD_columns_to_update
SET column_identifier = 
    CASE 
        WHEN column_name IN ('ID_CASINO', 'CASINO_ID', 'SITEID') THEN 'CASINO_ID'
        WHEN column_name = 'COD_SOCIET' THEN 'COD_SOCIET'
        WHEN column_name = 'NOM_SOCIET' THEN 'NOM_SOCIET'
        WHEN column_name = 'COD_ETABLI' THEN 'COD_ETABLI'
        WHEN column_name = 'NOM_ETABLI' THEN 'NOM_ETABLI'
        WHEN column_name = 'NOM_COURT' THEN 'NOM_COURT'
        ELSE ''
    END;
commit;

--to check:
--select * from MOD_columns_to_update order by 1,2,3 desc;
--select count(*) from MOD_columns_to_update;

--disabling constraints
CREATE OR REPLACE PROCEDURE MOD_disable_constraints
IS
BEGIN
	
    DBMS_OUTPUT.PUT_LINE('----------------------------------');
    DBMS_OUTPUT.PUT_LINE('----------------------------------');
    DBMS_OUTPUT.PUT_LINE('Disabling referential constraints: ');
    DBMS_OUTPUT.PUT_LINE('----------------------------------');
    DBMS_OUTPUT.PUT_LINE('----------------------------------');
    
    -- Disable referential constraints referencing the columns to be updated
    FOR rec IN (SELECT schema_name, table_name, column_name FROM MOD_columns_to_update)
    LOOP
        FOR constr IN (SELECT con.owner, con.table_name, con.constraint_name
                       FROM dba_constraints con
                       JOIN dba_cons_columns col ON con.constraint_name = col.constraint_name
                       WHERE con.constraint_type = 'R'
                       AND col.table_name = rec.table_name
                       AND col.column_name = rec.column_name)
        LOOP
            DBMS_OUTPUT.PUT_LINE('Disabling referential constraint ' || constr.constraint_name || ' referencing table ' || constr.table_name || ' in schema ' || constr.owner);
            EXECUTE IMMEDIATE 'ALTER TABLE ' || constr.owner || '.' || constr.table_name || ' DISABLE CONSTRAINT ' || constr.constraint_name;
        END LOOP;
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('----------------------');
    DBMS_OUTPUT.PUT_LINE('----------------------');
    DBMS_OUTPUT.PUT_LINE('Disabling constraints: ');
    DBMS_OUTPUT.PUT_LINE('----------------------');
    DBMS_OUTPUT.PUT_LINE('----------------------');
    
    -- Disable constraints for the affected columns of each table
    FOR rec IN (SELECT schema_name, table_name, column_name FROM MOD_columns_to_update)
    LOOP
        FOR constr IN (SELECT con.owner, con.table_name, con.constraint_name, con.constraint_type
                       FROM dba_constraints con
                       JOIN dba_cons_columns col ON con.constraint_name = col.constraint_name
                       WHERE con.table_name = rec.table_name
                       AND col.column_name = rec.column_name)
        LOOP
            DBMS_OUTPUT.PUT_LINE('Disabling ' || constr.constraint_type || ' constraint ' || constr.constraint_name || ' for column ' || rec.column_name || ' in table ' || constr.table_name || ' in schema ' || constr.owner);
            EXECUTE IMMEDIATE 'ALTER TABLE ' || constr.owner || '.' || constr.table_name || ' DISABLE CONSTRAINT ' || constr.constraint_name;
        END LOOP;
    END LOOP;

	
END;
/

--enable constraints:
CREATE OR REPLACE PROCEDURE MOD_enable_constraints
IS
BEGIN

    DBMS_OUTPUT.PUT_LINE('---------------------');
    DBMS_OUTPUT.PUT_LINE('---------------------');
    DBMS_OUTPUT.PUT_LINE('Enabling constraints: ');
    DBMS_OUTPUT.PUT_LINE('---------------------');
    DBMS_OUTPUT.PUT_LINE('---------------------');
    

    -- Enable constraints for the affected columns
    FOR rec IN (SELECT schema_name, table_name, column_name FROM MOD_columns_to_update)
    LOOP
        FOR constr IN (SELECT con.owner, con.table_name, con.constraint_name, con.constraint_type
                       FROM dba_constraints con
                       JOIN dba_cons_columns col ON con.constraint_name = col.constraint_name
                       WHERE con.table_name = rec.table_name
                       AND col.column_name = rec.column_name
                       AND con.constraint_type IN ('P', 'U', 'C'))
        LOOP
            BEGIN
                EXECUTE IMMEDIATE 'ALTER TABLE ' || constr.owner || '.' || constr.table_name || ' ENABLE CONSTRAINT ' || constr.constraint_name;
                DBMS_OUTPUT.PUT_LINE('Enabled ' || constr.constraint_type || ' constraint ' || constr.constraint_name || ' for column ' || rec.column_name || ' in table ' || rec.table_name || ' in schema ' || rec.schema_name);
            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('Error enabling ' || constr.constraint_type || ' constraint ' || constr.constraint_name || ' for column ' || rec.column_name || ' in table ' || rec.table_name || ' in schema ' || rec.schema_name || ': ' || SQLERRM);
            END;
        END LOOP;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('--------------------------------');
    DBMS_OUTPUT.PUT_LINE('--------------------------------');
    DBMS_OUTPUT.PUT_LINE('Enabling referential constraints:');
    DBMS_OUTPUT.PUT_LINE('--------------------------------');
    DBMS_OUTPUT.PUT_LINE('--------------------------------');

    -- Enable referential constraints
    FOR rec IN (SELECT schema_name, table_name, column_name FROM MOD_columns_to_update)
    LOOP
        FOR constr IN (SELECT con.owner, con.table_name, con.constraint_name, con.constraint_type
                       FROM dba_constraints con
                       JOIN dba_cons_columns col ON con.constraint_name = col.constraint_name
                       WHERE con.table_name = rec.table_name
                       AND col.column_name = rec.column_name
                       AND con.constraint_type = 'R')
        LOOP
            BEGIN
                EXECUTE IMMEDIATE 'ALTER TABLE ' || constr.owner || '.' || constr.table_name || ' ENABLE CONSTRAINT ' || constr.constraint_name;
                DBMS_OUTPUT.PUT_LINE('Enabled referential constraint ' || constr.constraint_name || ' for column ' || rec.column_name || ' in table ' || rec.table_name || ' in schema ' || rec.schema_name);
            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('Error enabling referential constraint ' || constr.constraint_name || ' for column ' || rec.column_name || ' in table ' || rec.table_name || ' in schema ' || rec.schema_name || ': ' || SQLERRM);
            END;
        END LOOP;
    END LOOP;
END;
/

--procedure that will update the relevant default values
CREATE OR REPLACE PROCEDURE MOD_update_default_values(
    new_casino_id NUMBER
) AS
BEGIN
    FOR rec IN (SELECT tc.owner, tc.table_name, tc.column_name
                FROM dba_tab_columns tc
                LEFT JOIN all_tab_cols atc ON tc.owner = atc.owner 
                                            AND tc.table_name = atc.table_name 
                                            AND tc.column_name = atc.column_name
                WHERE tc.owner NOT LIKE 'APEX%'
                  AND tc.owner NOT IN ('ANONYMOUS', 'APPQOSSYS', 'AUDSYS', 'BOREF', 'CTXSYS', 'DBSFWUSER', 'DBSNMP', 'DIP', 'DVF', 
                                       'DVSYS', 'EMC', 'FLOWS_FILES', 'GGSYS', 'GSMADMIN_INTERNAL', 'GSMCATUSER', 'GSMUSER', 'LBACSYS', 
                                       'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OJVMSYS', 'OLAPSYS', 'ORACLE_OCM', 'ORDDATA', 'ORDPLUGINS', 
                                       'ORDSYS', 'OUTLN', 'OWBSYS', 'OWBSYS_AUDIT', 'REMOTE_SCHEDULER_AGENT', 'RMANSCS', 'SCOTT', 
                                       'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 'SPATIAL_WFS_ADMIN_USR', 'SYS', 'SYS$UMF', 
                                       'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSMAN', 'SYSRAC', 'SYSTEM', 'WMSYS', 'XDB', 'XS$NULL')
                  AND tc.table_name NOT LIKE 'BIN%'
                  AND tc.column_name IN ('ID_CASINO')
                  AND tc.data_default is not null
                ) 
    LOOP
        -- Generate and execute dynamic SQL to update default values
        --DBMS_OUTPUT.PUT_LINE('Updating: ' || rec.column_name || ' in table ' || rec.table_name);
        EXECUTE IMMEDIATE 'ALTER TABLE ' || rec.owner || '.' || rec.table_name || ' MODIFY (' || rec.column_name || ' DEFAULT ' || new_casino_id || ')';
        DBMS_OUTPUT.PUT_LINE('Default value updated for column ' || rec.column_name || ' in table ' || rec.table_name || ' to ' || new_casino_id);
        
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/

--function that spools DDL of triggers, replaces OLD_CASINO_ID with NEW_CASINO_ID and recreates them
CREATE OR REPLACE PROCEDURE MOD_recreate_triggers (
    OLD_CASINO_ID      IN NUMBER,
    NEW_CASINO_ID      IN NUMBER
) AS
    v_trigger_ddl CLOB;
    need_to_recreate INTEGER;
    v_trigger_status VARCHAR2(8);
BEGIN
    FOR rec IN (SELECT owner, trigger_name
                FROM dba_triggers
                WHERE owner NOT IN (
                    'ANONYMOUS', 'APPQOSSYS', 'AUDSYS', 'BOREF', 'CTXSYS', 'DBSFWUSER', 'DBSNMP', 'DIP', 'DVF', 
                    'DVSYS', 'EMC', 'FLOWS_FILES', 'GGSYS', 'GSMADMIN_INTERNAL', 'GSMCATUSER', 'GSMUSER', 'LBACSYS', 
                    'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OJVMSYS', 'OLAPSYS', 'ORACLE_OCM', 'ORDDATA', 'ORDPLUGINS', 
                    'ORDSYS', 'OUTLN', 'OWBSYS', 'OWBSYS_AUDIT', 'REMOTE_SCHEDULER_AGENT', 'RMANSCS', 'SCOTT', 
                    'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 'SPATIAL_WFS_ADMIN_USR', 'SYS', 'SYS$UMF', 
                    'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSMAN', 'SYSRAC', 'SYSTEM', 'WMSYS', 'XDB', 'XS$NULL')
                AND owner NOT LIKE 'APEX%') -- Specify the owners you want to exclude
    LOOP
        v_trigger_ddl := '';
        v_trigger_ddl := DBMS_METADATA.GET_DDL('TRIGGER', rec.trigger_name, rec.owner);
        
        need_to_recreate := 0;
        
        -- Check if the trigger DDL contains the hardcoded number 4090
        IF INSTR(v_trigger_ddl, '4090') > 0 THEN
            -- Replace hardcoded 4090 with NEW_CASINO_ID
            v_trigger_ddl := REPLACE(v_trigger_ddl, '+ 4090', ('+ ' || TO_CHAR(NEW_CASINO_ID)));
            need_to_recreate := need_to_recreate + 1;
        END IF;
       
        IF INSTR(v_trigger_ddl, ('+ ' || TO_CHAR(OLD_CASINO_ID))) > 0 THEN
            -- Replace OLD_CASINO_ID with NEW_CASINO_ID
            need_to_recreate := need_to_recreate + 1;
            v_trigger_ddl := REPLACE(v_trigger_ddl, ('+ ' || TO_CHAR(OLD_CASINO_ID)), ('+ ' || TO_CHAR(NEW_CASINO_ID)));
        END IF;
        
        -- Remove ALTER TRIGGER statements from DDL
        v_trigger_ddl := REGEXP_REPLACE(v_trigger_ddl, '^ALTER TRIGGER.*$', '', 1, 0, 'm');
        
        -- Remove "/" at the end of DDL
        v_trigger_ddl := REGEXP_REPLACE(v_trigger_ddl, '/$', '');
        
        -- Check if the trigger is enabled or disabled
        SELECT status
        INTO v_trigger_status
        FROM dba_triggers
        WHERE owner = rec.owner
        AND trigger_name = rec.trigger_name;
        
        IF need_to_recreate > 0 THEN
            --Execute the modified trigger DDL
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE(v_trigger_ddl);
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE('Modifying trigger ' || rec.owner || '.' || rec.trigger_name);
            EXECUTE IMMEDIATE v_trigger_ddl;
            
            -- Enable or disable the trigger based on its previous state
            IF v_trigger_status = 'ENABLED' THEN
                EXECUTE IMMEDIATE 'ALTER TRIGGER ' || rec.owner || '.' || rec.trigger_name || ' ENABLE';
            ELSE
                EXECUTE IMMEDIATE 'ALTER TRIGGER ' || rec.owner || '.' || rec.trigger_name || ' DISABLE';
            END IF;
        END IF; 
        
    END LOOP;
END;
/

--function that spools DDL of sequences, replaces OLD_CASINO_ID with NEW_CASINO_ID and recreates them
CREATE OR REPLACE PROCEDURE MOD_recreate_sequences (
    OLD_CASINO_ID      IN NUMBER,
    NEW_CASINO_ID      IN NUMBER
) AS
    v_sequence_ddl CLOB;
    need_to_recreate integer;
BEGIN
    FOR rec IN (SELECT sequence_owner, sequence_name
                FROM dba_sequences
                WHERE sequence_owner NOT IN (
                    'ANONYMOUS', 'APPQOSSYS', 'AUDSYS', 'BOREF', 'CTXSYS', 'DBSFWUSER', 'DBSNMP', 'DIP', 'DVF', 
                    'DVSYS', 'EMC', 'FLOWS_FILES', 'GGSYS', 'GSMADMIN_INTERNAL', 'GSMCATUSER', 'GSMUSER', 'LBACSYS', 
                    'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OJVMSYS', 'OLAPSYS', 'ORACLE_OCM', 'ORDDATA', 'ORDPLUGINS', 
                    'ORDSYS', 'OUTLN', 'OWBSYS', 'OWBSYS_AUDIT', 'REMOTE_SCHEDULER_AGENT', 'RMANSCS', 'SCOTT', 
                    'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 'SPATIAL_WFS_ADMIN_USR', 'SYS', 'SYS$UMF', 
                    'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSMAN', 'SYSRAC', 'SYSTEM', 'WMSYS', 'XDB', 'XS$NULL')
                AND sequence_owner NOT LIKE 'APEX%') -- Specify the owners you want to exclude
    LOOP
        
        v_sequence_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', rec.sequence_name, rec.sequence_owner);
        
        need_to_recreate := 0;
        
        -- Check if the trigger DDL contains the hardcoded number 4090
        IF INSTR(v_sequence_ddl, '4090') > 0 THEN
            -- Replace hardcoded 4090 with NEW_CASINO_ID
            v_sequence_ddl := REPLACE(v_sequence_ddl, '+ 4090', ('+ ' || TO_CHAR(NEW_CASINO_ID)));
            need_to_recreate := need_to_recreate + 1;
        END IF;
       
        IF INSTR(v_sequence_ddl, ('+ ' || TO_CHAR(OLD_CASINO_ID))) > 0 THEN
            -- Replace OLD_CASINO_ID with NEW_CASINO_ID
            need_to_recreate := need_to_recreate + 1;
            v_sequence_ddl := REPLACE(v_sequence_ddl, ('+ ' || TO_CHAR(OLD_CASINO_ID)), ('+ ' || TO_CHAR(NEW_CASINO_ID)));
        END IF;
        
        IF need_to_recreate > 0 THEN
            -- Execute the modified trigger DDL
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE(v_sequence_ddl);
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE('Modifying sequence ' || rec.sequence_owner || '.' || rec.sequence_name);
            --EXECUTE IMMEDIATE v_sequence_ddl;
        END IF; 
        
    END LOOP;
END;
/

--function that spools DDL of views, replaces OLD_CASINO_ID with NEW_CASINO_ID and recreates them
CREATE OR REPLACE PROCEDURE MOD_recreate_views (
    OLD_CASINO_ID      IN NUMBER,
    NEW_CASINO_ID      IN NUMBER
) AS
    v_view_ddl CLOB;
    need_to_recreate INTEGER;
BEGIN
    FOR rec IN (SELECT owner, view_name
                FROM dba_views
                WHERE owner NOT IN (
                    'ANONYMOUS', 'APPQOSSYS', 'AUDSYS', 'BOREF', 'CTXSYS', 'DBSFWUSER', 'DBSNMP', 'DIP', 'DVF', 
                    'DVSYS', 'EMC', 'FLOWS_FILES', 'GGSYS', 'GSMADMIN_INTERNAL', 'GSMCATUSER', 'GSMUSER', 'LBACSYS', 
                    'MDDATA', 'MDSYS', 'MGMT_VIEW', 'OJVMSYS', 'OLAPSYS', 'ORACLE_OCM', 'ORDDATA', 'ORDPLUGINS', 
                    'ORDSYS', 'OUTLN', 'OWBSYS', 'OWBSYS_AUDIT', 'REMOTE_SCHEDULER_AGENT', 'RMANSCS', 'SCOTT', 
                    'SI_INFORMTN_SCHEMA', 'SPATIAL_CSW_ADMIN_USR', 'SPATIAL_WFS_ADMIN_USR', 'SYS', 'SYS$UMF', 
                    'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSMAN', 'SYSRAC', 'SYSTEM', 'WMSYS', 'XDB', 'XS$NULL')
                AND owner NOT LIKE 'APEX%') -- Specify the owners you want to exclude
    LOOP
        v_view_ddl := '';
        v_view_ddl := DBMS_METADATA.GET_DDL('VIEW', rec.view_name, rec.owner);
        
        need_to_recreate := 0;
        
        -- Check if the view DDL contains the hardcoded number 4090
        IF INSTR(v_view_ddl, '4090') > 0 THEN
            -- Replace hardcoded 4090 with NEW_CASINO_ID
            v_view_ddl := REPLACE(v_view_ddl, '4090', TO_CHAR(NEW_CASINO_ID));
            need_to_recreate := need_to_recreate + 1;
        END IF;
       
        IF INSTR(v_view_ddl, OLD_CASINO_ID) > 0 THEN
            -- Replace OLD_CASINO_ID with NEW_CASINO_ID
            need_to_recreate := need_to_recreate + 1;
            v_view_ddl := REPLACE(v_view_ddl, OLD_CASINO_ID, NEW_CASINO_ID);
        END IF;
        
        -- Remove "/" at the end of DDL
        v_view_ddl := REGEXP_REPLACE(v_view_ddl, '/$', '');
        
        IF need_to_recreate > 0 THEN
            -- Remove trailing semicolon if exists
            IF SUBSTR(v_view_ddl, LENGTH(v_view_ddl), 1) = ';' THEN
                v_view_ddl := SUBSTR(v_view_ddl, 1, LENGTH(v_view_ddl) - 1);
            END IF;
            
            -- Print the modified view DDL
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE(v_view_ddl);
            DBMS_OUTPUT.PUT_LINE('------------');
            DBMS_OUTPUT.PUT_LINE('Modifying view ' || rec.owner || '.' || rec.view_name);
            EXECUTE IMMEDIATE v_view_ddl;
        END IF; 
        
    END LOOP;
END;
/

--functions that will update the relevant columns
--different update statement will be executed depending on param_identifier (VARCHAR vs NUMBER)
--TODO: updating with more detailed where-clause in case of multi-casino DB?
CREATE OR REPLACE FUNCTION MOD_update_column(
    param_schema  VARCHAR2,
    param_table   VARCHAR2,
    param_column  VARCHAR2,
    param_old     VARCHAR2,
    param_new     VARCHAR2,
    param_identifier VARCHAR2
) RETURN NUMBER
IS
    v_sql VARCHAR2(1000);
    v_rows_updated NUMBER := 0; -- Variable to store the number of rows updated
BEGIN

    IF param_identifier = 'CASINO_ID' 
    THEN
        -- Construct the SQL statement for update of a number column
        v_sql := 'UPDATE ' || param_schema || '.' || param_table || ' SET ' || param_column || ' = ' || param_new || ' WHERE ' || param_column || ' = ' || param_old; 
    
    ELSIF param_identifier IN ('NOM_SOCIET', 'NOM_ETABLI', 'NOM_COURT') THEN
        -- Construct the SQL statement for update of specific text columns
        v_sql := 'UPDATE ' || param_schema || '.' || param_table || ' SET ' || param_column || ' = ''' || param_new || ''''; --' WHERE ' || param_column || ' = ''' || param_old || '''';   

    ELSE --ELSIF param_identifier IN ('COD_ETABLI','COD_SOCIET') THEN 
        -- Construct the SQL statement for update of a text column
        v_sql := 'UPDATE ' || param_schema || '.' || param_table || ' SET ' || param_column || ' = ''' || param_new || ''' WHERE ' || param_column || ' = ''' || param_old || '''';
    END IF;

    DBMS_OUTPUT.PUT_LINE(' - ' || v_sql || ';');

    -- Execute the dynamic SQL and store the number of rows updated
    BEGIN
        EXECUTE IMMEDIATE v_sql;
        v_rows_updated := SQL%ROWCOUNT; -- Get the number of rows updated
        
        COMMIT; -- Commit the transaction
    EXCEPTION
        WHEN OTHERS THEN
            -- Output error message
            DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
    END;

    -- Output the number of rows updated
    DBMS_OUTPUT.PUT_LINE(' ---> Rows updated: ' || v_rows_updated);
    
    -- Return 1 to indicate success
    RETURN 1;
                 			 
END;
/

--helper function to fetch OLD_COD_SOCIET
CREATE OR REPLACE FUNCTION MOD_get_old_societ(OLD_CASINO_ID NUMBER)
RETURN VARCHAR2
IS
    OLD_COD_SOCIET VARCHAR2(100);
BEGIN
    -- Retrieve OLD_COD_SOCIET based on OLD_CASINO_ID
    SELECT COD_SOCIET INTO OLD_COD_SOCIET
    FROM GALAXIS.BETABLI
    WHERE ID_CASINO = OLD_CASINO_ID;

    RETURN OLD_COD_SOCIET;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;  -- Or handle the exception as needed
END;
/

--helper function to fetch OLD_COD_ETABLI
CREATE OR REPLACE FUNCTION MOD_get_old_etabli(OLD_CASINO_ID NUMBER)
RETURN VARCHAR2
IS
    OLD_COD_ETABLI VARCHAR2(100);
BEGIN
    -- Retrieve OLD_COD_ETABLI based on OLD_CASINO_ID
    SELECT COD_ETABLI INTO OLD_COD_ETABLI
    FROM GALAXIS.BETABLI
    WHERE ID_CASINO = OLD_CASINO_ID;

    RETURN OLD_COD_ETABLI;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;  -- Or handle the exception as needed
END;
/

--actual CasinoChanger script that will call all the functions
CREATE OR REPLACE PROCEDURE MOD_CasinoChanger(
    OLD_CASINO_ID   NUMBER,   --TODO:  create function to fetch current casino parameters according to a single casino_ID input parameter!
    NEW_CASINO_ID   NUMBER,
    NEW_COD_SOCIET  VARCHAR2,
    NEW_COD_ETABLI  VARCHAR2,
    NEW_NOM_SOCIET  VARCHAR2,
    NEW_NOM_ETABLI  VARCHAR2,
    NEW_NOM_COURT   VARCHAR2
)
IS
    OLD_COD_SOCIET   VARCHAR2(20);
    OLD_COD_ETABLI   VARCHAR2(20);
    confirm_response VARCHAR2(1);
    update_result     NUMBER;
BEGIN
    
    --OLD_CASINO_ID -->  fetch other variables
    OLD_COD_SOCIET := MOD_get_old_societ(OLD_CASINO_ID);
    OLD_COD_ETABLI := MOD_get_old_etabli(OLD_CASINO_ID);
    
    DBMS_OUTPUT.PUT_LINE('--------');
    DBMS_OUTPUT.PUT_LINE('Changing CASINO_ID'); 
    DBMS_OUTPUT.PUT_LINE('- from: ' || OLD_CASINO_ID);
    DBMS_OUTPUT.PUT_LINE('- to:   ' || NEW_CASINO_ID || ' !');
    DBMS_OUTPUT.PUT_LINE('--------');
    DBMS_OUTPUT.PUT_LINE('Changing COD_SOCIET:');
    DBMS_OUTPUT.PUT_LINE('- from: ' || OLD_COD_SOCIET);
    DBMS_OUTPUT.PUT_LINE('- to:   ' || NEW_COD_SOCIET || ' !');
    DBMS_OUTPUT.PUT_LINE('--------');
    DBMS_OUTPUT.PUT_LINE('Changing COD_ETABLI:');
    DBMS_OUTPUT.PUT_LINE('- from: ' || OLD_COD_ETABLI);
    DBMS_OUTPUT.PUT_LINE('- to:   ' || NEW_COD_ETABLI || ' !');
    DBMS_OUTPUT.PUT_LINE('--------');
    
    -- Ask for confirmation
    --DBMS_OUTPUT.PUT_LINE('Are you sure you want to update data? (Y/N)');
    --DBMS_OUTPUT.GET_LINE(confirm_response);

    -- If user confirms, proceed with data update
    --IF UPPER(confirm_response) = 'Y' THEN
        -- Disable constraints
        MOD_disable_constraints;

        -- Loop through MOD_columns_to_update and call MOD_update_column for each line
        
        FOR rec IN (SELECT * FROM MOD_columns_to_update)
        LOOP
            update_result := MOD_update_column(
                rec.schema_name,
                rec.table_name,
                rec.column_name,
                CASE
                    WHEN rec.column_identifier = 'CASINO_ID' THEN TO_CHAR(OLD_CASINO_ID)
                    WHEN rec.column_name = 'COD_SOCIET' THEN OLD_COD_SOCIET
                    WHEN rec.column_name = 'COD_ETABLI' THEN OLD_COD_ETABLI
                    --WHEN rec.column_name = 'NOM_SOCIET' THEN OLD_NOM_SOCIET
                    --WHEN rec.column_name = 'NOM_ETABLI' THEN OLD_NOM_ETABLI
                    --WHEN rec.column_name = 'NOM_COURT' THEN OLD_NOM_COURT
                    ELSE NULL
                END,
                CASE
                    WHEN rec.column_identifier = 'CASINO_ID' THEN TO_CHAR(NEW_CASINO_ID)
                    WHEN rec.column_name = 'COD_SOCIET' THEN NEW_COD_SOCIET
                    WHEN rec.column_name = 'COD_ETABLI' THEN NEW_COD_ETABLI
                    WHEN rec.column_name = 'NOM_SOCIET' THEN NEW_NOM_SOCIET
                    WHEN rec.column_name = 'NOM_ETABLI' THEN NEW_NOM_ETABLI
                    WHEN rec.column_name = 'NOM_COURT' THEN NEW_NOM_COURT
                    ELSE NULL
                END,
                rec.column_identifier
            );
            -- Check the return value of MOD_update_column
            IF update_result != 1 THEN
                DBMS_OUTPUT.PUT_LINE('Error updating column ' || rec.column_name || ' in table ' || rec.table_name ||
                                     ' in schema ' || rec.schema_name);
                -- Optionally, handle the error condition further
                -- You might want to consider rolling back changes, logging the error, etc.
            END IF;
        END LOOP;

        -- Enable constraints
        MOD_enable_constraints;
        
        -- Update Views
        --MOD_recreate_views(OLD_CASINO_ID,NEW_CASINO_ID);
        
        -- Update Triggers
        --MOD_recreate_triggers(OLD_CASINO_ID,NEW_CASINO_ID);
        
        -- Update sequences
        -- does not really do much:
        --MOD_recreate_sequences(OLD_CASINO_ID,NEW_CASINO_ID);
        
        -- Update default values
        MOD_update_default_values(NEW_CASINO_ID);

    --    DBMS_OUTPUT.PUT_LINE('Data update completed.');
    --ELSE
    --    DBMS_OUTPUT.PUT_LINE('Update canceled.');
    --END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Enable constraints in case of an exception
        MOD_enable_constraints;
        DBMS_OUTPUT.PUT_LINE('An error occurred during data update.');
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/

exit;