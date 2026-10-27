#!/bin/sh
# Run once after cloning. Turns on the hooks that keep private material out of this public repository.
set -e
cd "$(dirname "$0")"
git config core.hooksPath .githooks
git config --unset-all remote.origin.push 2>/dev/null || true
git config --add remote.origin.push 'refs/heads/*:refs/heads/*'
git config --add remote.origin.push 'refs/tags/*:refs/tags/*'
chmod +x .githooks/*
echo "hooks on: $(git config core.hooksPath); notes are never pushed by default"
