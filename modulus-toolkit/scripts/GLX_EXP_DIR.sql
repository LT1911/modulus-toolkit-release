CREATE OR REPLACE DIRECTORY EXP_DIR AS 'G:\Export\';
GRANT READ, WRITE ON DIRECTORY EXP_DIR TO system;

select 
    directory_name, 
    directory_path 
from dba_directories 
where directory_name = 'EXP_DIR';

exit;