#!/bin/bash
docker exec nginx sed -i 's/<title>/Title: /' /usr/share/nginx/html/index.html