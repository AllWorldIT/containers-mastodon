# Copyright (c) 2022-2025, AllWorldIT.
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


FROM registry.conarx.tech/containers/alpine/3.22 as mastodon-builder

LABEL maintainer="Nigel Kukard <nkukard@lbsd.net>"
ARG VERSION_INFO=

ARG MASTODON_VER=4.4.8

COPY --from=registry.conarx.tech/containers/nodejs/3.22:22.21.0 /opt/nodejs-22.21.0 /opt/nodejs-22.21.0
COPY --from=registry.conarx.tech/containers/ruby/3.22:3.4.7 /opt/ruby-3.4.7 /opt/ruby-3.4.7


# Copy build patches
COPY patches build/patches

RUN set -eux; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates openssl c-ares; \
# Ruby
	apk add --no-cache libucontext; \
# NodeJS
	apk add --no-cache nghttp2-libs libuv; \
# Mastodon
	apk add --no-cache coreutils wget procps libpq imagemagick ffmpeg jemalloc icu-libs libidn yaml file tzdata readline; \
# Mastodon build reqs
	apk add --no-cache build-base git jemalloc-dev libucontext-dev libpq-dev icu-dev zlib-dev libidn-dev linux-headers yaml-dev vips-dev; \
	# Setup environment
	for i in /opt/*/ld-musl-x86_64.path; do \
		cat "$i" >> /etc/ld-musl-x86_64.path; \
	done; \
	for i in /opt/*/PATH; do \
		export PATH="$(cat "$i"):$PATH"; \
	done; \
# Start build
	npm install --global yarn; \
	true "Versioning..."; \
	node --version; \
	ruby --version; \
	true "Download Mastodon..."; \
	cd build; \
	wget https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VER}.tar.gz; \
	tar -zxf v${MASTODON_VER}.tar.gz; \
	cd mastodon-${MASTODON_VER}; \
	true "Patching Mastodon..."; \
	patch -p1 < ../patches/mastodon-4.4.0_reserved-usernames.patch; \
	true "Enable corepack..."; \
	corepack enable; \
	corepack prepare --activate; \
	true "Build Mastodon..."; \
	bundle config set --local deployment 'true'; \
	bundle config set --local without 'development test'; \
	bundle config set silence_root_warning true; \
	bundle install -j$(nproc); \
	true "Install Node modules..."; \
	yarn workspaces focus --production @mastodon/mastodon; \
	true "Writing out version..."; \
	echo "MASTODON_VER=$MASTODON_VER" > VERSION; \
	true "Precompiling assets..."; \
	RAILS_ENV=production \
		ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=precompile_placeholder \
		ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=precompile_placeholder \
		ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=precompile_placeholder \
		OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder \
		bin/rails assets:precompile; \
	true "Install Node modules for Streaming server..."; \
	yarn workspaces focus --production @mastodon/streaming; \
	true "Cleaning up..."; \
	yarn cache clean; \
	true "Moving to 'mastodon'..."; \
	cd ..; \
	mv mastodon-${MASTODON_VER} mastodon



FROM registry.conarx.tech/containers/alpine/3.22 as tools

RUN set -eux; \
	true "Install tools"; \
	apk add --no-cache \
		redis \
		postgresql-client



FROM registry.conarx.tech/containers/alpine/3.22


ARG VERSION_INFO=

ARG RUBY_VER=3.4.7
ARG NODEJS_VER=22.21.0

LABEL org.opencontainers.image.authors   = "Nigel Kukard <nkukard@conarx.tech>"
LABEL org.opencontainers.image.version   = "3.22"
LABEL org.opencontainers.image.base.name = "docker.io/library/alpine:3.22"

COPY --from=registry.conarx.tech/containers/ruby/3.22:3.4.7 /opt/ruby-3.4.7 /opt/ruby-3.4.7
COPY --from=registry.conarx.tech/containers/nodejs/3.22:22.21.0 /opt/nodejs-22.21.0 /opt/nodejs-22.21.0


RUN set -eux; \
	true "Setup user and group"; \
	addgroup -S mastodon 2>/dev/null; \
	adduser -S -D -h /opt/mastodon -s /sbin/nologin -G mastodon -g mastodon mastodon 2>/dev/null


# Copy in Mastodon
COPY --chown=mastodon:mastodon --from=mastodon-builder /build/mastodon /opt/mastodon
# Tools
COPY --from=tools /usr/bin/redis-cli /usr/local/bin/redis-cli
COPY --from=tools /usr/bin/psql /usr/local/bin/psql
COPY --from=tools /usr/bin/pg_isready /usr/local/bin/pg_isready


# Add more PATHs to the PATH
ENV PATH="${PATH}:/opt/ruby-${RUBY_VER}/bin:/opt/nodejs-${NODEJS_VER}/bin:/opt/mastodon/bin"

RUN set -eux; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates curl openssl c-ares sudo; \
# Ruby
	apk add --no-cache gmp libucontext; \
	ln -s /opt/ruby-${RUBY_VER}/bin/ruby /usr/local/bin/ruby; \
# NodeJS
	apk add --no-cache libuv nghttp2-libs; \
# Mastodon
	apk add --no-cache coreutils wget procps libpq imagemagick ffmpeg jemalloc icu-libs libidn yaml file tzdata readline vips; \
	mkdir -p /opt/mastodon/public/system; \
	mkdir -p /opt/mastodon/private; \
# Link mastodon to / that everyone else uses
	ln -s /opt/mastodon /mastodon; \
	mkdir /etc/mastodon; \
# Setup environment
	for i in /opt/*/ld-musl-x86_64.path; do \
		cat "$i" >> /etc/ld-musl-x86_64.path; \
	done; \
# Other
	true "Cleanup"; \
	rm -rf \
		/usr/include/*; \
	rm -f /var/cache/apk/*


## Mastodon
COPY etc/supervisor/conf.d/mastodon.conf /etc/supervisor/conf.d/mastodon.conf
COPY usr/local/sbin/start-mastodon /usr/local/sbin/start-mastodon
COPY usr/local/sbin/tootctl /usr/local/sbin/tootctl
COPY usr/local/sbin/mastodon-rails /usr/local/sbin/mastodon-rails
COPY usr/local/share/flexible-docker-containers/init.d/42-mastodon.sh /usr/local/share/flexible-docker-containers/init.d
COPY usr/local/share/flexible-docker-containers/tests.d/42-mastodon.sh /usr/local/share/flexible-docker-containers/tests.d
COPY usr/local/share/flexible-docker-containers/healthcheck.d/42-mastodon.sh /usr/local/share/flexible-docker-containers/healthcheck.d
RUN set -eux; \
	true "Flexible Docker Containers"; \
	if [ -n "$VERSION_INFO" ]; then echo "$VERSION_INFO" >> /.VERSION_INFO; fi; \
	true "Permissions"; \
	chown root:root \
		/etc/supervisor/conf.d/mastodon.conf \
		/etc/mastodon \
		/usr/local/sbin/start-mastodon \
		/usr/local/sbin/tootctl \
		/usr/local/sbin/mastodon-rails; \
	chown mastodon:mastodon \
		/opt/mastodon/private \
		/opt/mastodon/public \
		/opt/mastodon/public/system; \
	chmod 0644 \
		/etc/supervisor/conf.d/mastodon.conf; \
	chmod 0755 \
		/usr/local/sbin/start-mastodon \
		/usr/local/sbin/tootctl \
		/usr/local/sbin/mastodon-rails; \
	chmod 0750 \
		/etc/mastodon \
		/opt/mastodon/private \
		/opt/mastodon/public \
		/opt/mastodon/public/system; \
	fdc set-perms


VOLUME ["/mastodon/private", "/mastodon/public/system"]


EXPOSE 3000 4000
