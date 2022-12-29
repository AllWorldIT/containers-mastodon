#!/bin/sh

cd /opt/mastodon

# Load our MASTODON_MODE env
. .mode.env

# Decide which one of our health checks we'll be running
if [ "$MASTODON_MODE" = "web" ]; then
	wget -q --spider --proxy=off http://localhost:3000/health || exit 1

elif [ "$MASTODON_MODE" = "streaming" ]; then
	wget -q --spider --proxy=off http://localhost:4000/api/v1/streaming/health || exit 1

elif [ "$MASTODON_MODE" = "sidekiq" ]; then
	ps aux | grep -q 'sidekiq 6' || exit 1

fi
