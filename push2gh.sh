#!/bin/bash -xv
cd $HOME/git
git subtree split --prefix=personal-scripts/ai -b github-ai
git push -u  github-ai github-ai:main
