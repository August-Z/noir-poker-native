#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
reference_commit=03c78233f9454de54e378c5c81ba1dd25fa9b14e
reference_dir=.reference/noir-poker
mkdir -p "$reference_dir"
if [ ! -d "$reference_dir/.git" ]; then
  git -C "$reference_dir" init --quiet
  git -C "$reference_dir" remote add origin https://github.com/JessieZJZ/noir-poker.git
fi
git -C "$reference_dir" diff --quiet
git -C "$reference_dir" fetch --quiet --depth 1 origin "$reference_commit"
git -C "$reference_dir" checkout --quiet --detach "$reference_commit"
printf 'Read-only migration reference ready: %s\n' "$reference_commit"
