#!/bin/sh

cd /opt/mastodon

# Make sure we have an environment variable configuration file for Mastodon
if [ ! -f /etc/mastodon/mastodon.env ]; then
	echo "ERROR: Mastodon environment variable configuration file '/etc/mastodon/mastodon.env' does not exist"
	echo "       This can be specified using:  --volume /home/user/test/mastodon.env:/etc/mastodon/mastodon.env"
	exit 1
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
	echo "ERROR: Value for MASTODON_MODE is not set, it should be set to one of these values 'web', 'streaming', 'sidekiq'"
	echo "       This can be specified using:  -e MASTODON_MODE=web"
	exit 1
fi

if [ "$MASTODON_MODE" != "web" -a "$MASTODON_MODE" != "streaming" -a "$MASTODON_MODE" != "sidekiq" ]; then
	echo "ERROR: Value for MASTODON_MODE is invalid, supported values are 'web', 'streaming', 'sidekiq'"
	exit 1
fi

# Write out our .mode.env so we can load it from our init and health tests later
echo "MASTODON_MODE=$MASTODON_MODE" > /opt/mastodon/.mode.env


# Check settings we need are set
(
	. /mastodon/mastodon.env

	if [ -z "$MASTODON_HOST" ]; then
		echo "ERROR: Environment variable 'MASTODON_HOST' (internal) must be set, this is the hostname of the main mastodon container"
		false
	fi

	if [ -z "$LOCAL_DOMAIN" ]; then
		echo "ERROR: Environment variable 'LOCAL_DOMAIN' must be set"
		false
	fi

	if [ -z "$DB_HOST" ]; then
		echo "ERROR: Environment variable 'DB_HOST' must be set"
		false
	fi
	if [ -z "$DB_PORT" ]; then
		echo "ERROR: Environment variable 'DB_PORT' must be set"
		false
	fi
	if [ -z "$DB_USER" ]; then
		echo "ERROR: Environment variable 'DB_USER' must be set"
		false
	fi
	if [ -z "$DB_PASS" ]; then
		echo "ERROR: Environment variable 'DB_PASS' must be set"
		false
	fi
	if [ -z "$DB_NAME" ]; then
		echo "ERROR: Environment variable 'DB_NAME' must be set"
		false
	fi

	if [ -z "$REDIS_HOST" ]; then
		echo "ERROR: Environment variable 'REDIS_HOST' must be set"
		false
	fi
	if [ -z "$REDIS_PORT" ]; then
		echo "ERROR: Environment variable 'REDIS_PORT' must be set"
		false
	fi
	if [ -z "$REDIS_PASSWORD" ]; then
		echo "ERROR: Environment variable 'REDIS_PASSWORD' must be set"
		false
	fi

	if [ -z "$SECRET_KEY_BASE" ]; then
		echo "ERROR: Environment variable 'SECRET_KEY_BASE' must be set"
		false
	fi
	if [ -z "$OTP_SECRET" ]; then
		echo "ERROR: Environment variable 'OTP_SECRET' must be set"
		false
	fi

	if [ -z "$VAPID_PRIVATE_KEY" ]; then
		echo "ERROR: Environment variable 'VAPID_PRIVATE_KEY' must be set"
		echo "       This can be specified using:"
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
		echo "ERROR: Environment variable 'VAPID_PUBLIC_KEY' must be set"
		echo "       This can be specified using:"
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
if [ "$MASTODON_MODE" != "web" ]; then

	while ! nc -z "$MASTODON_HOST" 3000; do
		echo "INFO: Waiting for Mastodon on host '$MASTODON_HOST' to start..."
		sleep 2
	done

else

	if [ -n "$REDIS_HOST" -o -n "$REDIS_URL" ]; then
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
			echo "INFO: Waiting for Redis..."
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
		echo "INFO: Waiting for PostgreSQL..."
		sleep 2
	done


	# Check if we need to initialize the database
	if [ ! -f /opt/mastodon/private/VERSION ]; then

		if [ "$MASTODON_MODE" = "web" ]; then
			# Initialize database
			echo "NOTICE: Initializing database..."
			mastodon-rails db:schema:load
			mastodon-rails db:seed
			echo "NOTICE: Database initialization complete"

			# Copy mastodon version into our private state storage
			cp /opt/mastodon/VERSION /opt/mastodon/private/VERSION

		else

			# When this file starts to exist, it means the database has been initialized
			while [ ! -f /opt/mastodon/private/VERSION ]; do
				echo "NOTICE: Waiting for database to be setup"
				sleep 2
			done
		fi

	# If not a new installation, check if we need an upgrade
	else
		. /opt/mastodon/private/VERSION
		MASTODON_VER_CUR="$MASTODON_VER"
		. /opt/mastodon/VERSION
		# If it doesn't match, this is an upgrade
		if [ "$MASTODON_VER_CUR" != "$MASTODON_VER" ]; then
			echo "NOTICE: Upgrade needed from $MASTODON_VER_CUR to $MASTODON_VER"
			SKIP_POST_DEPLOYMENT_MIGRATIONS=true mastodon-rails db:migrate
			echo "NOTICE: Upgrade (pre-deployment) complete"
			echo "MASTODON_VER=$MASTODON_VER" > /opt/mastodon/private/VERSION
		fi
	fi

fi
