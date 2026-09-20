-- ============================================================
-- Vektor 3.2.4  Ausbruch aus der Datenbank
-- Grundzustand (absichtlich unsicher). Laeuft als ba_admin in ba_test.
-- ============================================================

CREATE ROLE attacker LOGIN PASSWORD 'attacker';

-- Fehlkonfiguration: die drei Serverrollen an eine Login-Rolle vergeben.
-- Der Vektor ist die Folge genau dieser Vergabe. Der Dateizugriff laeuft
-- ueber COPY, das die Rollenmitgliedschaft direkt prueft; ein separates
-- EXECUTE auf pg_read_file o.ae. ist dafuer nicht noetig.
GRANT pg_read_server_files, pg_write_server_files, pg_execute_server_program
  TO attacker;