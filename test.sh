#! /usr/bin/env bash

odin run . && gcc test.s -g -o out && (./out; echo -e "\nRETURN $?\n")
