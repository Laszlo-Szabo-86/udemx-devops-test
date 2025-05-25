#!/bin/bash
DATE=$(date +%F)
find /var/log -type f -mtime -5 > "last_five-$DATE.out"