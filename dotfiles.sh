#!/usr/bin/env bash
for dotfile in $(git grep -Il '' '.*' ':(exclude)*/*'); do
  ln -fs {"$PWD","$HOME"}/"$dotfile"
done
