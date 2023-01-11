FROM vault:latest

RUN apk add curl jq openssl

COPY custom-entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/custom-entrypoint.sh

ENTRYPOINT [ "custom-entrypoint.sh" ]
CMD [ "server", "-dev" ]