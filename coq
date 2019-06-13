#!/bin/sh
export OPAMROOT=~/opam-coq.8.9.1
eval `opam config env`
coqide
