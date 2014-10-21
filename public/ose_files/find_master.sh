#!/bin/bash
#for node in 1 2 3; do ssh services$node "mongo -u openshift -p redhat openshift_broker --eval \"rs.isMaster()['ismaster']\""; done
#for node in 1 2 3; do echo -n "Services$node: "; ssh services$node "mongo -u openshift -p redhat openshift_broker --eval \"rs.isMaster()['ismaster']\" --quiet" 2> /dev/null; done
for server in $(grep MONGO_HOST_PORT /etc/openshift/broker.conf | grep -v "#" | cut -d\" -f 2 | sed -e 's/,/\n/g'); do echo -n "$server: ";  mongo -u openshift -p redhat $server/openshift_broker --eval "rs.isMaster()['ismaster']" --quiet; done
