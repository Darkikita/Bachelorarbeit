#!/bin/bash
# Aufruf aus /home/nikita/docker/ba-test:
#   vektoren/1-reichweite/lauf.sh vorher
#   vektoren/1-reichweite/lauf.sh nachher
Z=$1
for R in app_over attacker admin_cr; do
  docker compose exec -T -e PGPASSWORD=$R pg-service \
    psql -U $R -d ba_test -v zustand=$Z -f - < vektoren/3.2.1-Reichweite/angriffe.sql
done