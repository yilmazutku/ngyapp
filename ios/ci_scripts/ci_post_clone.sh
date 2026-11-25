#!/bin/sh

set -e

exec sh "$CI_PRIMARY_REPOSITORY_PATH/tools/xcode_cloud/flutter_post_clone.sh" ios
