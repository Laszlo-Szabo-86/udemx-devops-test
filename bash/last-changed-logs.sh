#!/bin/bash
DATE=$(date +%F)
ls -lt /var/log | grep ^- | head -n 3 > "mod-$DATE.out"