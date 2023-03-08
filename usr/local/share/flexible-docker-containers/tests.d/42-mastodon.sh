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


fdc_test_start mastodon "Using health check to test Mastodon is up"
i=120
while [ "$i" -gt 0 ]; do
	i=$((i-1))

	fdc_test_progress mastodon "Waiting for Mastodon health check to pass... ${i}s"

	# shellcheck disable=SC1091
	if source /usr/local/share/flexible-docker-containers/healthcheck.d/42-mastodon.sh; then
		fdc_test_pass mastodon "Mastodon health check passed on for mode '$MASTODON_MODE'"
		break
	fi

	sleep 1
done

if [ "$i" = 0 ]; then
	fdc_test_fail mastodon "Mastodon health check failed!"
	false
fi

touch /PASSED

# We'll wait 60s more, as we're shut down by the run-mastodon-test script
sleep 60