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


#
# Ruby builder
#


FROM registry.conarx.tech/containers/alpine/edge as ruby-builder

ARG RUBY_VER=3.0.6

# Copy build patches
COPY patches build/patches


# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/ruby/APKBUILD
	apk add --no-cache \
		build-base \
		ca-certificates \
		gmp-dev libucontext-dev \
		zlib-dev openssl-dev gdbm-dev readline-dev libffi-dev coreutils yaml-dev linux-headers autoconf \
		\
		jemalloc-dev


# Download packages
RUN set -eux; \
	mkdir -p build; \
	cd build; \
	wget "https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz"; \
	tar -xf "ruby-${RUBY_VER}.tar.gz"


# Build and install Ruby
RUN set -eux; \
	cd build; \
	cd ruby-${RUBY_VER}; \
# Patching
#	patch -p1 < ../patches/ruby-dont-install-bundled-gems.patch; \
	patch -p1 < ../patches/ruby-fix-get_main_stack.patch; \
	patch -p1 <	../patches/ruby-test_insns-lower-recursion-depth.patch; \
# -fomit-frame-pointer makes ruby segfault, see gentoo bug #150413
# In many places aliasing rules are broken; play it safe
# as it's risky with newer compilers to leave it as it is.
	export CFLAGS="-fno-omit-frame-pointer -fno-strict-aliasing"; \
	export CPPFLAGS="-fno-omit-frame-pointer -fno-strict-aliasing"; \
	\
# Needed for coroutine stuff
	export LIBS="-lucontext"; \
# ruby saves path to install. we want use $PATH
	export INSTALL=install; \
# the configure script does not detect isnan/isinf as macros
	export ac_cv_func_isnan=yes; \
	export ac_cv_func_isinf=yes; \
	\
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--mandir=/usr/share/man \
		--infodir=/usr/share/info \
		--with-sitedir=/usr/local/lib/site_ruby \
		--with-search-path="/usr/lib/site_ruby/\$(ruby_ver)/x86_64-linux" \
		--enable-pthread \
		--disable-rpath \
		--enable-shared \
		--enable-yjit \
		--with-jemalloc \
		--disable-install-doc; \
# Build
	make -j$(nproc) -l 8 VERBOSE=1; \
# Test
	make test; \
# Install
	pkgdir="/build/ruby-root"; \
	make DESTDIR="$pkgdir" SUDO="" install; \
# Remove cruft
	rm -rfv \
		"$pkgdir"/usr/share \
		"$pkgdir"/usr/lib/pkgconfig


RUN set -eux; \
	cd build/ruby-root; \
	pkgdir="/build/ruby-root"; \
	scanelf --recursive --nobanner --osabi --etype "ET_DYN,ET_EXEC" .  | awk '{print $3}' | xargs \
		strip \
			--remove-section=.comment \
			--remove-section=.note \
			-R .gnu.lto_* -R .gnu.debuglto_* \
			-N __gnu_lto_slim -N __gnu_lto_v1 \
			--strip-unneeded; \
	du -hs "$pkgdir"



#
# Nodejs builder
#

FROM registry.conarx.tech/containers/alpine/edge as nodejs-builder

ARG NODEJS_VER=18.15.0

# Copy build patches
COPY patches build/patches


# Install libs we need
RUN set -eux; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/nodejs/APKBUILD
	apk add --no-cache \
		build-base \
		ca-certificates \
		brotli-dev c-ares-dev icu-dev linux-headers nghttp2-dev openssl-dev python3 py3-jinja2 samurai zlib-dev


# Download packages
RUN set -eux; \
	mkdir -p build; \
	cd build; \
	wget "https://nodejs.org/dist/v$NODEJS_VER/node-v$NODEJS_VER.tar.gz"; \
	tar -xf "node-v${NODEJS_VER}.tar.gz"


# Build and install Nodejs
RUN set -eux; \
	cd build; \
	cd node-v${NODEJS_VER}; \
# Remove bundled dependencies that we're not using.
# ref: https://git.alpinelinux.org/aports/tree/main/nodejs/APKBUILD
	# openssl.cnf is required for build.
	mv deps/openssl/nodejs-openssl.cnf .; \
	\
	# Remove bundled dependencies that we're not using.
	rm -rf deps/brotli \
		deps/cares \
		deps/corepack \
		deps/openssl/* \
		deps/v8/third_party/jinja2 \
		deps/zlib \
		tools/inspector_protocol/jinja2; \
	\
	mv nodejs-openssl.cnf deps/openssl/; \
# Patching
	patch -p1 < ../patches/nodejs-fix-build-with-system-c-ares.patch; \
	patch -p1 < ../patches/node-v18.15.0_nodejs-disable-running-gyp-on-shared-deps.patch; \
# Compiler flags
	export CFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CXXFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CPPFLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	\
# NOTE: We use bundled libuv because they don't care much about backward
# compatibility and it has happened several times in past that we
# couldn't upgrade nodejs package in stable branches to fix CVEs due to
# libuv incompatibility.
#
# NOTE: We don't package the bundled npm - it's a separate project with
# its own release cycle and version numbering, so it's better to keep
# it in a standalone aport.
#
# TODO: Fix and enable corepack.
	python3 configure.py --prefix=/usr \
		--shared-brotli \
		--shared-zlib \
		--shared-openssl \
		--shared-cares \
		--shared-nghttp2 \
		--ninja \
		--openssl-use-def-ca-store \
		--with-icu-default-data-dir=$(icu-config --icudatadir) \
		--with-intl=system-icu; \
	\
# Build, must build without -j or it will fail
	make -l 8 VERBOSE=1 BUILDTYPE=Release; \
# Test
	./node -e 'console.log("Hello, world!")'; \
	./node -e "require('assert').equal(process.versions.node, '$NODEJS_VER')"; \
# Install
	pkgdir="/build/nodejs-root"; \
	make DESTDIR="$pkgdir" install; \
	\
# Remove cruft
	rm -rfv \
		"$pkgdir"/usr/share \
		"$pkgdir"/usr/lib/node_modules/npm/docs \
		"$pkgdir"/usr/lib/node_modules/npm/man


RUN set -eux; \
	cd build/nodejs-root; \
	pkgdir="/build/nodejs-root"; \
	scanelf --recursive --nobanner --osabi --etype "ET_DYN,ET_EXEC" .  | awk '{print $3}' | xargs \
		strip \
			--remove-section=.comment \
			--remove-section=.note \
			-R .gnu.lto_* -R .gnu.debuglto_* \
			-N __gnu_lto_slim -N __gnu_lto_v1 \
			--strip-unneeded; \
	du -hs "$pkgdir"



#
# Build Mastodon
#


FROM registry.conarx.tech/containers/alpine/edge as mastodon-builder


LABEL maintainer="Nigel Kukard <nkukard@lbsd.net>"
ARG VERSION_INFO=

ARG MASTODON_VER=4.1.4


# Copy in built binaries
COPY --from=ruby-builder /build/ruby-root /
COPY --from=nodejs-builder /build/nodejs-root /

# Copy build patches
COPY patches build/patches

RUN set -eux; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates openssl c-ares; \
# Ruby
	apk add --no-cache libucontext; \
# NodeJS
	apk add --no-cache nghttp2-libs; \
# Mastodon
	apk add --no-cache coreutils wget procps libpq imagemagick ffmpeg jemalloc icu-libs libidn yaml file tzdata readline; \
# Mastodon build reqs
	apk add --no-cache build-base git jemalloc-dev libucontext-dev libpq-dev icu-dev zlib-dev libidn-dev; \
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
	patch -p1 < ../patches/mastodon-4.0.2_reserved-usernames.patch; \
	true "Build Mastodon..."; \
	bundle config set --local deployment 'true'; \
	bundle config set --local without 'development test'; \
	bundle config set silence_root_warning true; \
	bundle install -j$(nproc); \
	yarn install --pure-lockfile --network-timeout 600000; \
	true "Writing out version..."; \
	echo "MASTODON_VER=$MASTODON_VER" > VERSION; \
	true "Precompiling assets..."; \
	RAILS_ENV=production OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder \
		bin/rails assets:precompile; \
	true "Cleaning up..."; \
	yarn cache clean; \
	true "Moving to 'mastodon'..."; \
	cd ..; \
	mv mastodon-${MASTODON_VER} mastodon



FROM registry.conarx.tech/containers/alpine/edge as tools

RUN set -eux; \
	true "Install tools"; \
	apk add --no-cache \
		redis \
		postgresql-client



FROM registry.conarx.tech/containers/alpine/edge


ARG VERSION_INFO=

LABEL org.opencontainers.image.authors   "Nigel Kukard <nkukard@conarx.tech>"
LABEL org.opencontainers.image.version   "edge"
LABEL org.opencontainers.image.base.name "docker.io/library/alpine:edge"



RUN set -eux; \
	true "Setup user and group"; \
	addgroup -S mastodon 2>/dev/null; \
	adduser -S -D -h /opt/mastodon -s /sbin/nologin -G mastodon -g mastodon mastodon 2>/dev/null


# Copy in built binaries
COPY --from=ruby-builder /build/ruby-root /
COPY --from=nodejs-builder /build/nodejs-root /
# Copy in Mastodon
COPY --chown=mastodon:mastodon --from=mastodon-builder /build/mastodon /opt/mastodon
# Tools
COPY --from=tools /usr/bin/redis-cli /usr/local/bin/redis-cli
COPY --from=tools /usr/bin/psql /usr/local/bin/psql
COPY --from=tools /usr/bin/pg_isready /usr/local/bin/pg_isready


# Add more PATHs to the PATH
ENV PATH="${PATH}:/opt/mastodon/bin"

RUN set -eux; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates curl openssl c-ares sudo; \
# Ruby
	apk add --no-cache libucontext; \
# NodeJS
	apk add --no-cache nghttp2-libs; \
# Mastodon
	apk add --no-cache coreutils wget procps libpq imagemagick ffmpeg jemalloc icu-libs libidn yaml file tzdata readline; \
	mkdir -p /opt/mastodon/public/system; \
	mkdir -p /opt/mastodon/private; \
# Link mastodon to / that everyone else uses
	ln -s /opt/mastodon /mastodon; \
	mkdir /etc/mastodon; \
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
