#!/bin/sh
# Run once after cloning, and again after adding a remote. Turns on the hooks that keep private
# material out of this public repository, and makes every remote push branches and tags only.
set -e
cd "$(dirname "$0")"
git config core.hooksPath .githooks
chmod +x .githooks/*
for r in $(git remote); do
  git config --unset-all "remote.$r.push" 2>/dev/null || true
  git config --add "remote.$r.push" 'refs/heads/*:refs/heads/*'
  git config --add "remote.$r.push" 'refs/tags/*:refs/tags/*'
done
echo "hooks on: $(git config core.hooksPath); remotes push branches and tags only: $(git remote | tr '\n' ' ')"
