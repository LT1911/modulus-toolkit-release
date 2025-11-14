--as sysdba
drop table MOD_columns_to_update;

drop procedure MOD_disable_constraints;
drop procedure MOD_enable_constraints;
drop procedure MOD_update_default_values;
drop procedure MOD_recreate_triggers;
drop procedure MOD_recreate_sequences;
drop procedure MOD_recreate_views;

drop function MOD_update_column;
drop function MOD_get_old_societ;
drop function MOD_get_old_etabli;

drop procedure MOD_CasinoChanger;
exit;