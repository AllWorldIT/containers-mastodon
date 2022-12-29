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


# Upgrading

Post deployment migrations must be run after upgrading, as per 4.0.2 release notes.

