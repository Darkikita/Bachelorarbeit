-- ============================================================
-- Schicht 4  Systemgrenze  (gegen den Ausbruch)
-- Laeuft als ba_admin. Die Serverrollen gehoeren an keine Anwendungs-
-- oder Login-Rolle. Der Entzug schliesst alle drei Wege.
-- ============================================================
REVOKE pg_read_server_files, pg_write_server_files, pg_execute_server_program
  FROM attacker;