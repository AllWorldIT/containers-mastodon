#!/bin/bash
# Copyright (c) 2022-2023, AllWorldIT.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.


# shellcheck disable=SC2164
cd /opt/mastodon

fdc_notice "Initializing Mastodon settings"

# Make sure we have an environment variable configuration file for Mastodon
if [ ! -f /etc/mastodon/mastodon.env ]; then
	fdc_error "Mastodon environment variable configuration file '/etc/mastodon/mastodon.env' does not exist"
	fdc_error "This can be specified using:  --volume /home/user/test/mastodon.env:/etc/mastodon/mastodon.env"
	false
fi
# Setup environment variables
cat <<EOF > /opt/mastodon/mastodon.env
# Defaults
PATH="$PATH:/opt/mastodon/bin"
RAILS_ENV="production"
NODE_ENV="production"
RAILS_SERVE_STATIC_FILES="true"
BIND="::"
DEFAULT_LOCALE="en"
# User config
EOF
cat /etc/mastodon/mastodon.env >> /opt/mastodon/mastodon.env
chmod 0640 /opt/mastodon/mastodon.env


# First we're going to check what mode we're running in...
if [ -z "$MASTODON_MODE" ]; then
	fdc_error "Value for MASTODON_MODE is not set, it should be set to one of these values 'web', 'streaming', 'sidekiq'"
	fdc_error "This can be specified using:  -e MASTODON_MODE=web"
	false
fi

if [ "$MASTODON_MODE" != "web" ] && [ "$MASTODON_MODE" != "streaming" ] && [ "$MASTODON_MODE" != "sidekiq" ]; then
	fdc_error "Value for MASTODON_MODE is invalid, supported values are 'web', 'streaming', 'sidekiq'"
	false
fi

# Write out our .mode.env so we can load it from our init and health tests later
echo "MASTODON_MODE=$MASTODON_MODE" > /opt/mastodon/.mode.env


# Check settings we need are set
(
	. /mastodon/mastodon.env

	if [ -z "$MASTODON_HOST" ]; then
		fdc_error "Environment variable 'MASTODON_HOST' (internal) must be set, this is the hostname of the main mastodon container"
		false
	fi

	if [ -z "$LOCAL_DOMAIN" ]; then
		fdc_error "Environment variable 'LOCAL_DOMAIN' must be set"
		false
	fi

	if [ -z "$DB_HOST" ]; then
		fdc_error "Environment variable 'DB_HOST' must be set"
		false
	fi
	if [ -z "$DB_PORT" ]; then
		fdc_error "Environment variable 'DB_PORT' must be set"
		false
	fi
	if [ -z "$DB_USER" ]; then
		fdc_error "Environment variable 'DB_USER' must be set"
		false
	fi
	if [ -z "$DB_PASS" ]; then
		fdc_error "Environment variable 'DB_PASS' must be set"
		false
	fi
	if [ -z "$DB_NAME" ]; then
		fdc_error "Environment variable 'DB_NAME' must be set"
		false
	fi

	if [ -z "$REDIS_HOST" ]; then
		fdc_error "Environment variable 'REDIS_HOST' must be set"
		false
	fi
	if [ -z "$REDIS_PORT" ]; then
		fdc_error "Environment variable 'REDIS_PORT' must be set"
		false
	fi
	if [ -z "$REDIS_PASSWORD" ]; then
		fdc_error "Environment variable 'REDIS_PASSWORD' must be set"
		false
	fi

	if [ -z "$SECRET_KEY_BASE" ]; then
		fdc_error "Environment variable 'SECRET_KEY_BASE' must be set"
		false
	fi
	if [ -z "$OTP_SECRET" ]; then
		fdc_error "Environment variable 'OTP_SECRET' must be set"
		false
	fi

	if [ -z "$VAPID_PRIVATE_KEY" ]; then
		fdc_error "Environment variable 'VAPID_PRIVATE_KEY' must be set"
		echo "	   This can be specified using:"
		cat <<EOF
	VAPID_PRIVATE_KEY_RAW=\$(openssl ecparam -name prime256v1 -genkey -noout -out /dev/stdout)
	VAPID_PUBLIC_KEY_RAW=\$(echo "\$VAPID_PRIVATE_KEY_RAW" | openssl ec -in /dev/stdin -pubout -out /dev/stdout)
	VAPID_PRIVATE_KEY=\$(echo "\$VAPID_PRIVATE_KEY_RAW" | grep -v "PRIVATE" | tr -d '\n')
	VAPID_PUBLIC_KEY=\$(echo "\$VAPID_PUBLIC_KEY_RAW" | grep -v "PUBLIC" | tr -d '\n')
	echo "VAPID_PRIVATE_KEY=\$VAPID_PRIVATE_KEY"
	echo "VAPID_PUBLIC_KEY=\$VAPID_PUBLIC_KEY"
EOF
		false
	fi
	if [ -z "$VAPID_PUBLIC_KEY" ]; then
		fdc_error "Environment variable 'VAPID_PUBLIC_KEY' must be set"
		echo "	   This can be specified using:"
		cat <<EOF
	VAPID_PRIVATE_KEY_RAW=\$(openssl ecparam -name prime256v1 -genkey -noout -out /dev/stdout)
	VAPID_PUBLIC_KEY_RAW=\$(echo "\$VAPID_PRIVATE_KEY_RAW" | openssl ec -in /dev/stdin -pubout -out /dev/stdout)
	VAPID_PRIVATE_KEY=\$(echo "\$VAPID_PRIVATE_KEY_RAW" | grep -v "PRIVATE" | tr -d '\n')
	VAPID_PUBLIC_KEY=\$(echo "\$VAPID_PUBLIC_KEY_RAW" | grep -v "PUBLIC" | tr -d '\n')
	echo "VAPID_PRIVATE_KEY=\$VAPID_PRIVATE_KEY"
	echo "VAPID_PUBLIC_KEY=\$VAPID_PUBLIC_KEY"
EOF
		false
	fi
)


# Fixup permissions
chmod 0750 /opt/mastodon/private /opt/mastodon/public /opt/mastodon/public/system
chown mastodon:mastodon /opt/mastodon/private /opt/mastodon/public /opt/mastodon/public/system

# Load configuration
set -a
. /opt/mastodon/mastodon.env
set +a


# All containers need to wait for the main container to come up
# This signifies completion of any tasks or upgrades that need tobe done
if [ "$MASTODON_MODE" = "web" ]; then


	if [ -n "$REDIS_HOST" ] || [ -n "$REDIS_URL" ]; then
		# Check Redis is up
		REDIS_CHECK=(redis-cli)
		if [ -n "$REDIS_URL" ]; then
			REDIS_CHECK+=(-U "$REDIS_URL")
		else
			if [ -n "$REDIS_HOST" ]; then
				REDIS_CHECK+=(-h "$REDIS_HOST")
			fi
			if [ -n "$REDIS_PORT" ]; then
				REDIS_CHECK+=(-p "$REDIS_PORT")
			fi
		fi
		REDIS_CHECK+=(PING)

		if [ -n "$REDIS_PASSWORD" ]; then
			export REDISCLI_AUTH=$REDIS_PASSWORD
		fi

		# Wait for redis
		while true; do
			if "${REDIS_CHECK[@]}" | grep -q PONG; then
				break
			fi
			fdc_info "Mastodon waiting for Redis to start up..."
			sleep 2
		done
	fi


	# The database must be reachable before we can continue, so we wait for it to come up
	POSTGRES_CHECK=(pg_isready)

	if [ -n "$DB_HOST" ]; then
		POSTGRES_CHECK+=(-h "$DB_HOST")
	fi

	if [ -n "$DB_PORT" ]; then
		POSTGRES_CHECK+=(-p "$DB_PORT")
	fi

	if [ -n "$DB_USER" ]; then
		POSTGRES_CHECK+=(-U "$DB_USER")
	fi

	# Wait for POSTGRES
	while true; do
		if "${POSTGRES_CHECK[@]}"; then
			break
		fi
		fdc_info "Waiting for PostgreSQL..."
		sleep 2
	done


	# Check if we need to initialize the database
	if [ ! -f /opt/mastodon/private/VERSION ]; then
		# Initialize database
		fdc_notice "Initializing Mastodon database..."
		mastodon-rails db:schema:load
		mastodon-rails db:seed
		fdc_notice "Mastodon database initialization complete"

		# Copy mastodon version into our private state storage
		cp /opt/mastodon/VERSION /opt/mastodon/private/VERSION

	# If not a new installation, check if we need an upgrade
	else
		. /opt/mastodon/private/VERSION
		MASTODON_VER_CUR="$MASTODON_VER"
		. /opt/mastodon/VERSION
		# If it doesn't match, this is an upgrade
		if [ "$MASTODON_VER_CUR" != "$MASTODON_VER" ]; then
			fdc_notice "Mastodon upgrade needed from $MASTODON_VER_CUR to $MASTODON_VER"
			SKIP_POST_DEPLOYMENT_MIGRATIONS=true mastodon-rails db:migrate
			fdc_notice "Mastodon upgrade (pre-deployment) complete"
			echo "MASTODON_VER=$MASTODON_VER" > /opt/mastodon/private/VERSION
		fi
	fi

else

	while ! nc -z "$MASTODON_HOST" 3000; do
		fdc_info "Waiting for Mastodon on host '$MASTODON_HOST' to start..."
		sleep 2
	done

fi
