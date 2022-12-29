

#
# Ruby builder
#


FROM registry.gitlab.iitsp.com/allworldit/docker/alpine:latest as ruby-builder

ARG RUBY_VER=3.0.4

# Copy build patches
COPY patches build/patches


# Install libs we need
RUN set -ex; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/ruby/APKBUILD
	apk add --no-cache \
		build-base \
		ca-certificates \
		gmp-dev libucontext-dev \
		zlib-dev openssl1.1-compat-dev gdbm-dev readline-dev libffi-dev coreutils yaml-dev linux-headers autoconf \
		\
		jemalloc-dev


# Download packages
RUN set -ex; \
	mkdir -p build; \
	cd build; \
	wget "https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz"; \
	tar -xf "ruby-${RUBY_VER}.tar.gz"


# Build and install Ruby
RUN set -ex; \
	cd build; \
	cd ruby-${RUBY_VER}; \
# Patching
#	patch -p1 < ../patches/ruby-dont-install-bundled-gems.patch; \
	patch -p1 < ../patches/ruby-fix-get_main_stack.patch; \
	patch -p1 <	../patches/ruby-test_insns-lower-recursion-depth.patch; \
# Compiler flags
	export CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fexceptions -Wp,-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -flto=auto"; \
	export CXXFLAGS="-Wp,-D_GLIBCXX_ASSERTIONS"; \
	export CPPFLAGS="$CXXFLAGS"; \
	export LDFLAGS="-Wl,-O2,--sort-common,--as-needed,-z,relro,-z,now -flto=auto"; \
	\
# -fomit-frame-pointer makes ruby segfault, see gentoo bug #150413
# In many places aliasing rules are broken; play it safe
# as it's risky with newer compilers to leave it as it is.
	export CFLAGS="$CFLAGS -fno-omit-frame-pointer -fno-strict-aliasing"; \
	export CPPFLAGS="$CPPFLAGS -fno-omit-frame-pointer -fno-strict-aliasing"; \
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
		--with-search-path="/usr/lib/site_ruby/\$(ruby_ver)/$_arch-linux" \
		--enable-pthread \
		--disable-rpath \
		--enable-shared \
		--enable-yjit \
		--with-jemalloc \
		--disable-install-doc; \
# Build
	make VERBOSE=1 -j$(nproc); \
# Test
	make test; \
# Install
	pkgdir="/build/ruby-root"; \
	make DESTDIR="$pkgdir" SUDO="" install; \
# Remove cruft
	rm -rfv \
		"$pkgdir"/usr/share \
		"$pkgdir"/usr/lib/pkgconfig


RUN set -ex; \
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

FROM registry.gitlab.iitsp.com/allworldit/docker/alpine:latest as nodejs-builder

ARG NODEJS_VER=16.18.1

# Copy build patches
COPY patches build/patches


# Install libs we need
RUN set -ex; \
	true "Installing build dependencies"; \
# from https://git.alpinelinux.org/aports/tree/main/nodejs/APKBUILD
	apk add --no-cache \
		build-base \
		ca-certificates \
		brotli-dev c-ares-dev icu-dev linux-headers nghttp2-dev openssl1.1-compat-dev python3 py3-jinja2 samurai zlib-dev


# Download packages
RUN set -ex; \
	mkdir -p build; \
	cd build; \
	wget "https://nodejs.org/dist/v$NODEJS_VER/node-v$NODEJS_VER.tar.gz"; \
	tar -xf "node-v${NODEJS_VER}.tar.gz"


# Build and install Nodejs
RUN set -ex; \
	cd build; \
	cd node-v${NODEJS_VER}; \
# Remove bundled dependencies that we're not using.
	rm -rf deps/brotli \
		deps/cares \
		deps/openssl \
		deps/v8/third_party/jinja2 \
		deps/zlib \
		tools/inspector_protocol/jinja2; \
# Patching
	patch -p1 < ../patches/nodejs-fix-build-with-system-c-ares.patch; \
	patch -p1 < ../patches/nodejs-disable-running-gyp-on-shared-deps.patch; \
# Compiler flags
	export CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fexceptions -Wp,-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -flto=auto"; \
	export CXXFLAGS="-Wp,-D_GLIBCXX_ASSERTIONS"; \
	export CPPFLAGS="$CXXFLAGS"; \
	export LDFLAGS="-Wl,-O2,--sort-common,--as-needed,-z,relro,-z,now -flto=auto"; \
	\
	export CFLAGS="$CFLAGS -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CXXFLAGS="$CXXFLAGS -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
	export CPPFLAGS="$CPPFLAGS -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"; \
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
# Build
	make VERBOSE=1 BUILDTYPE=Release; \
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


RUN set -ex; \
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


FROM registry.gitlab.iitsp.com/allworldit/docker/alpine:latest as mastodon-builder


LABEL maintainer="Nigel Kukard <nkukard@lbsd.net>"
ARG VERSION_INFO=

ARG MASTODON_VER=4.0.2


# Copy in built binaries
COPY --from=ruby-builder /build/ruby-root /
COPY --from=nodejs-builder /build/nodejs-root /


RUN set -ex; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates openssl1.1-compat c-ares; \
# Ruby
	apk add --no-cache libucontext; \
# NodeJS
	apk add --no-cache nghttp2-libs; \
# Mastodon
	apk add --no-cache coreutils wget procps libpq imagemagick ffmpeg jemalloc icu-libs libidn yaml file tzdata readline; \
# Mastodon build reqs
	apk add --no-cache build-base git jemalloc-dev libucontext-dev libpq-dev icu-dev zlib-dev libidn-dev; \
	mkdir build; \
	true "Versioning..."; \
	node --version; \
	ruby --version; \
	true "Download Mastodon..."; \
	cd build; \
	wget https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VER}.tar.gz; \
	tar -zxf v${MASTODON_VER}.tar.gz; \
	true "Patching Mastodon..."; \
	true "Build Mastodon..."; \
	npm install --global yarn; \
	cd mastodon-${MASTODON_VER}; \
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



FROM registry.gitlab.iitsp.com/allworldit/docker/alpine:latest as tools

RUN set -ex; \
	true "Install tools"; \
	apk add --no-cache \
		redis \
		postgresql-client



FROM registry.gitlab.iitsp.com/allworldit/docker/alpine:latest

LABEL maintainer="Nigel Kukard <nkukard@lbsd.net>"
ARG VERSION_INFO=


RUN set -ex; \
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

RUN set -ex; \
	true "Install requirements"; \
# Base requirements
	apk add --no-cache ca-certificates openssl1.1-compat c-ares sudo; \
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
	true "Versioning"; \
	if [ -n "$VERSION_INFO" ]; then echo "$VERSION_INFO" >> /.VERSION_INFO; fi; \
	true "Cleanup"; \
	rm -rf \
		/usr/include/*; \
	rm -f /var/cache/apk/*


## Mastodon
COPY etc/supervisor/conf.d/mastodon.conf /etc/supervisor/conf.d/mastodon.conf
COPY healthcheck.d/70-mastodon.sh /docker-healthcheck.d/70-mastodon.sh
COPY usr/local/sbin/start-mastodon /usr/local/sbin/start-mastodon
COPY usr/local/sbin/tootctl /usr/local/sbin/tootctl
COPY usr/local/sbin/mastodon-rails /usr/local/sbin/mastodon-rails
COPY init.d/70-mastodon.sh /docker-entrypoint-init.d/70-mastodon.sh
COPY pre-init-tests.d/70-mastodon.sh /docker-entrypoint-pre-init-tests.d/70-mastodon.sh
COPY tests.d/70-mastodon.sh /docker-entrypoint-tests.d/70-mastodon.sh
RUN set -ex; \
	chown root:root \
		/etc/supervisor/conf.d/mastodon.conf \
		/etc/mastodon \
		/docker-healthcheck.d/70-mastodon.sh \
		/usr/local/sbin/start-mastodon \
		/usr/local/sbin/tootctl \
		/usr/local/sbin/mastodon-rails \
		/docker-entrypoint-init.d/70-mastodon.sh \
		/docker-entrypoint-pre-init-tests.d/70-mastodon.sh \
		/docker-entrypoint-tests.d/70-mastodon.sh; \
	chown mastodon:mastodon \
		/opt/mastodon/private \
		/opt/mastodon/public \
		/opt/mastodon/public/system; \
	chmod 0644 \
		/etc/supervisor/conf.d/mastodon.conf; \
	chmod 0755 \
		/docker-healthcheck.d/70-mastodon.sh \
		/usr/local/sbin/start-mastodon \
		/usr/local/sbin/tootctl \
		/usr/local/sbin/mastodon-rails \
		/docker-entrypoint-init.d/70-mastodon.sh \
		/docker-entrypoint-pre-init-tests.d/70-mastodon.sh \
		/docker-entrypoint-tests.d/70-mastodon.sh; \
	chmod 0750 \
		/etc/mastodon \
		/opt/mastodon/private \
		/opt/mastodon/public \
		/opt/mastodon/public/system


VOLUME ["/mastodon/private", "/mastodon/public/system"]


EXPOSE 3000 4000
