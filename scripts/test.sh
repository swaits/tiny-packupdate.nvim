#!/usr/bin/env bash
set -euo pipefail

# Clone mini.nvim for test framework (if not cached)
if [ ! -d deps/mini.nvim ]; then
  mkdir -p deps
  git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim
fi

# Run tests
nvim --headless -u scripts/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run_file('tests/test_init.lua')"
