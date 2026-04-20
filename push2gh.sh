#!/bin/bash -xv
cd $HOME/git/sharedlibs
git subtree split --prefix=personal-scripts/ssl/ai -b github-ai
git push -u  github-ai github-ai:main
