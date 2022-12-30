# Introduction

This is a Mastodon container supporting all 3 modes of operation, namely `mastodon`, `sidekiq` and `streaming`.

See the [Alpine Base Image](https://gitlab.iitsp.com/allworldit/docker/alpine) project for additional configuration.


# Mastodon


## Configuration file: /etc/mastodon/mastodon.env

This environment variable file MUST be bind mounted into place.


## Volume: /mastodon/public/system

Public data directory.


## Volume: /mastodon/private

Private data directory, used internally by this image to keep state information.


## MASTODON_MODE

Mastodon mode of operation, either `web`, `sidekiq` or `streaming`.


# Administration


## command: tootctl

Command will drop into the mastodon installation as the correcet user.

## command: mastodon-rails

Command will drop into the mastodon installation as the correcet user and run rails.

## Other commands

The mastodon processes run as the mastodon user, in order to drop into the mastodon user you can run the following...

```
su -s /bin/sh - mastodon
```

# Generating keys

The private and public key can be generated using...

```bash
VAPID_PRIVATE_KEY_RAW=$(openssl ecparam -name prime256v1 -genkey -noout -out /dev/stdout)
VAPID_PUBLIC_KEY_RAW=$(echo "$VAPID_PRIVATE_KEY_RAW" | openssl ec -in /dev/stdin -pubout -out /dev/stdout)
VAPID_PRIVATE_KEY=$(echo "$VAPID_PRIVATE_KEY_RAW" | grep -v "PRIVATE" | tr -d '\n')
VAPID_PUBLIC_KEY=$(echo "$VAPID_PUBLIC_KEY_RAW" | grep -v "PUBLIC" | tr -d '\n')
echo "VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY"
echo "VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY"
```

# Migrating to this image

You MUST create `data/mastodon.private` and touch `data/mastodon.private/VERSION` or startup will fail.


# Upgrading

Post deployment migrations must be run after upgrading, as per 4.0.2 release notes.


