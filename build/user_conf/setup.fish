#!/usr/bin/fish 
set -x NPM_PACKAGES "$HOME/.local/npm_packages"
set -U fish_user_paths $HOME/.cargo/bin $HOME/.local/bin $HOME/.local/npm_packages/bin $fish_user_paths

