for node in $(oo-mco ping | head -n -2 | awk '{print $1}'); do 
	echo -n "$node: "; ssh $node "ls /var/lib/openshift/ | wc -l" 2> /dev/null
done
