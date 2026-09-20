\echo '## T3  Reaktion  (als ba_admin)'
\echo '-- Direktes Entfernen scheitert, solange die Rolle Objekte besitzt:'
DROP ROLE attacker;
\echo '-- Korrekt: erst Objekte und Rechte der Rolle entfernen ...'
DROP OWNED BY attacker;
\echo '-- ... dann die Rolle:'
DROP ROLE attacker;
-- Alternative statt DROP OWNED: REASSIGN OWNED BY attacker TO <rolle>,
-- dann gehen die Objekte samt Code an den neuen Eigentuemer ueber, danach
-- noch DROP OWNED fuer die verbliebenen Rechte. Deshalb loeschen, nicht
-- uebertragen, was der Angreifer angelegt hat.