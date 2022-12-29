#!/bin/sh

# Settings should be loaded from init still...


i=120
while [ "$i" -gt 0 ]; do
	i=$((i-1))

	echo "INFO: Waiting for healthcheck to pass... ${i}s"

	if docker-healthcheck; then
		echo "PASSED:   - Healthcheck passed on for '$MASTODON_MODE'"
		break
	fi

	sleep 1
done

if [ "$i" = 0 ]; then
	exit 1
fi

# We'll wait 60s more, as we're shut down by the run-mastodon-test script
sleep 60