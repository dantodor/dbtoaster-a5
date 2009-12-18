#!/bin/sh

for i in $(grep address $* | sed 's/address \([^:]*\):.*/\1/') $(grep switch $* | sed 's/switch //'); do
  echo "Cleaning up " $i
  ssh $i 'killall ruby'
  ssh $i 'rm /tmp/__db.00* /tmp/db_Map*'
done