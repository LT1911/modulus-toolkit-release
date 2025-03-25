--to be executed as sys for each DB
ALTER SYSTEM SET SEC_CASE_SENSITIVE_LOGON = FALSE;
ALTER PROFILE DEFAULT LIMIT
    CONNECT_TIME UNLIMITED
    IDLE_TIME UNLIMITED
    SESSIONS_PER_USER UNLIMITED
    LOGICAL_READS_PER_SESSION UNLIMITED
    PRIVATE_SGA UNLIMITED
    FAILED_LOGIN_ATTEMPTS UNLIMITED
    PASSWORD_LIFE_TIME UNLIMITED;

CREATE PUBLIC SYNONYM dbms_system FOR dbms_system;
GRANT EXECUTE ON dbms_system TO PUBLIC;
CREATE PUBLIC SYNONYM dbms_crypto FOR dbms_crypto;
GRANT EXECUTE ON dbms_crypto TO PUBLIC;

exit;