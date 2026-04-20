#!/bin/bash -xv
cd $HOME/git/sharedlibs/personal-scripts
git subtree split --prefix=personal-scripts/ssl/ai -b github-ai
git push -u  github-ai github-ai:main
