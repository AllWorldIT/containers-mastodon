[![pipeline status](https://gitlab.conarx.tech/containers/mastodon/badges/main/pipeline.svg)](https://gitlab.conarx.tech/containers/mastodon/-/commits/main)

# Container Information

[Container Source](https://gitlab.conarx.tech/containers/mastodon) - [GitHub Mirror](https://github.com/AllWorldIT/containers-mastodon)

This is the Conarx Containers Mastodon image, supporting all 3 modes of operation, namely `mastodon`, `sidekiq` and `streaming`.



# Mirrors

|  Provider  |  Repository                              |
|------------|------------------------------------------|
| DockerHub  | allworldit/mastodon                      |
| Conarx     | registry.conarx.tech/containers/mastodon |



# Commercial Support

Commercial support is available from [Conarx](https://conarx.tech).



# Environment Variables

Additional environment variables are available from...
* [Conarx Containers Alpine image](https://gitlab.conarx.tech/containers/alpine).


## MASTODON_MODE

Mastodon mode of operation, either `web`, `sidekiq` or `streaming`.



# Volumes


## /mastodon/public/system

Public data directory.


## /mastodon/private

Private data directory, used internally by this image to keep state information.



# Exposed Ports

Mastodon web port 3000 is exposed from the `web` mode instance.

Mastodon web port 4000 is exposed from the `streaming` mode instance.



# Administration

The `s3` mc alias is setup automatically.

The Minio admin command can be executed from the host using...

```
docker-compose exec mastodon mc ls s3\mybucket
```



# Configuration


## /etc/mastodon/mastodon.env

This environment variable file MUST be bind mounted into place.

An example of this configuration can be found below...

```bash
MASTODON_HOST=mastodon

BIND=0.0.0.0

DEFAULT_LANGUAGE=en

LOCAL_DOMAIN=xxx.xxx
SECRET_KEY_BASE=xxx
OTP_SECRET=xxx
VAPID_PRIVATE_KEY=xxx
VAPID_PUBLIC_KEY=xxx
DB_HOST=postgresql
DB_PORT=5432
DB_NAME=mastodon
DB_USER=mastodon
DB_PASS=xxx
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=xxx
TRUSTED_PROXY_IP=172.16.0.0/12,64:ff9b::/96


ES_ENABLED=true
ES_HOST=elasticsearch
ES_PORT=9200
ES_USER=elastic
ES_PASS=xxx

SMTP_SERVER=172.16.0.1
SMTP_PORT=25
SMTP_LOGIN=
SMTP_PASSWORD=
SMTP_AUTH_METHOD=plain
SMTP_OPENSSL_VERIFY_MODE=none
SMTP_ENABLE_STARTTLS=auto
SMTP_FROM_ADDRESS="XXXX Notifications <notifications@xxx.xxx>"

# Optional S3 support
S3_ENABLED=true
S3_BUCKET=media.linux.social
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx
S3_PROTOCOL=https
S3_HOSTNAME=media.xxx.xxx
S3_ENDPOINT=https://s3.xxxx/

# Optional libretranslate support
LIBRE_TRANSLATE_ENDPOINT=https://translate.xxxx
LIBRE_TRANSLATE_API_KEY=xxx
```



# Administration

The below commands have been added for convenience.

## tootctl

This command will run as the correct user.


## mastodon-rails

This command will run rails as the correct user within the Mastodon installation.


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

Post deployment migrations must be run after upgrading, as per the release notes.


