#!/bin/sh
# Usage: edge-lint [--fix] <files>
set -e

usage() {
  echo "Usage:"
  echo "    $0 [--fix] files"
  exit 1
}

if [ ${1:-nope} = --fix ]; then
  shift
  if [ $# -lt 1 ]; then
    usage
  fi

  import-sort -l --write "$@"
  prettier-eslint --write "$@"
else
  if [ $# -lt 1 ]; then
    usage
  fi

  eslint "$@"
  import-sort --list-different "$@"
  prettier-eslint --list-different "$@"
fi
