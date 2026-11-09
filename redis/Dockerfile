FROM redis:7.4
EXPOSE 6379
# Listen on IPv4 and (if available) IPv6, persist to /data with AOF.
CMD ["redis-server", "--appendonly", "yes", "--bind", "* -::*", "--protected-mode", "no"]
