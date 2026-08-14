#!/usr/bin/env bash
# Helper to set up Flutter environment for running tests in this sandbox.
# /tmp is a tiny tmpfs here, so we redirect pub cache & temp to /home/user.
export PATH="/home/user/flutter/bin:$PATH"
export FLUTTER_ROOT="/home/user/flutter"
export PUB_CACHE="/home/user/.pub-cache"
export TMPDIR="/home/user/tmp"
export PUBCACHE="/home/user/.pub-cache"
