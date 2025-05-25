#!/bin/bash
DATE=$(date +%F)
awk '{ print $3 }' /proc/loadavg > "loadavg-$DATE.out"