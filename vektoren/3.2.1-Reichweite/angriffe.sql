-- Läuft für jede Rolle in beiden Zuständen. Aufruf mit -v zustand=vorher|nachher
\set ON_ERROR_STOP off
SELECT pruef('A1-select',  :'zustand', 'SELECT * FROM intern');
SELECT pruef('A1-update',  :'zustand', 'UPDATE intern SET notiz = notiz');
SELECT pruef('A1-delete',  :'zustand', 'DELETE FROM intern');
SELECT pruef('A2-drop',    :'zustand', 'DROP TABLE kunden');
SELECT pruef('A3-execute', :'zustand', 'SELECT f()');
SELECT pruef('A4-kette',   :'zustand', 'SELECT * FROM intern');
SELECT pruef('A5-setrole', :'zustand', 'SELECT * FROM intern', 'grp_read');
SELECT pruef('N1-nutzfall', :'zustand', 'INSERT INTO kunden VALUES (99, ''Test'', ''DE99'')');