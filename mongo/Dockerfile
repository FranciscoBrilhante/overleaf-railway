# MongoDB as a single-node replica set (Overleaf requires a replica set)
FROM mongo:8.0
COPY entrypoint.sh /usr/local/bin/overleaf-mongo-entrypoint.sh
RUN chmod +x /usr/local/bin/overleaf-mongo-entrypoint.sh
EXPOSE 27017
ENTRYPOINT ["/usr/local/bin/overleaf-mongo-entrypoint.sh"]
