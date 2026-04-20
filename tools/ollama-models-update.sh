#!/bin/bash

ollama list | awk 'NR>1 {print $1}' | xargs -n1 ollama pull
