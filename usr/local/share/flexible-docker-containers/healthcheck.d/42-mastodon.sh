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

# Load our MASTODON_MODE env
# shellcheck disable=SC1091
. .mode.env

# Decide which one of our health checks we'll be running
if [ "$MASTODON_MODE" = "web" ]; then
	# Check we get a positive response back when using IPv4
	if ! curl -H "User-Agent: Health Check" --silent --fail -ipv4 http://localhost:3000/health; then
		fdc_error "Mastodon health check failed for Mastodon 'web' using IPv4"
		false
	fi

elif [ "$MASTODON_MODE" = "streaming" ]; then
	# Check we get a positive response back when using IPv4
	if ! curl -H "User-Agent: Health Check" --silent --fail -ipv4 http://localhost:4000/api/v1/streaming/health; then
		fdc_error "Mastodon health check failed for Mastodon 'streaming' using IPv4"
		false
	fi

elif [ "$MASTODON_MODE" = "sidekiq" ]; then
	# Check siekiq is running
	# shellcheck disable=SC2009
	if ! ps aux | grep -q 'sidekiq 6'; then
		fdc_error "Mastodon health check failed for Mastodon 'streaming' using IPv4"
		false
	fi
fi


# Return if we don't have IPv6 support
if [ -z "$(ip -6 route show default)" ]; then
	return
fi


# Decide which one of our health checks we'll be running
if [ "$MASTODON_MODE" = "web" ]; then
	# Check we get a positive response back when using IPv4
	if ! curl -H "User-Agent: Health Check" --silent --fail -ipv6 http://localhost:3000/health; then
		fdc_error "Mastodon health check failed for Mastodon 'web' using IPv6"
		false
	fi

elif [ "$MASTODON_MODE" = "streaming" ]; then
	# Check we get a positive response back when using IPv4
	if ! curl -H "User-Agent: Health Check" --silent --fail -ipv6 http://localhost:4000/api/v1/streaming/health; then
		fdc_error" Mastodon health check failed for Mastodon 'streaming' using IPv6"
		false
	fi
fi
