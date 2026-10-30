# lab-tools: one small image with readable commands for every lab.
# Built locally by `make image` and loaded into kind by `make cluster`.
FROM python:3.12-alpine
RUN apk add --no-cache procps coreutils
COPY tools/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*
CMD ["sleep", "infinity"]
