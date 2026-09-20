\echo '## E2  Serverdatei schreiben  (pg_write_server_files, als attacker)'
-- eine Datei als Betriebssystemnutzer des Servers schreiben ...
COPY (SELECT 'HIJACK durch ' || current_user) TO '/tmp/ba_beweis.txt';
-- ... und ueber pg_read_server_files zum Nachweis zuruecklesen
CREATE TEMP TABLE t (zeile text);
COPY t FROM '/tmp/ba_beweis.txt' WITH (format csv, delimiter E'\x1f', quote E'\x1e');
SELECT zeile AS inhalt FROM t;