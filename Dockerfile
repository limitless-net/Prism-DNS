FROM debian:12

# Install dnsmasq and sniproxy
RUN apt-get update && \
    apt-get install -y dnsmasq sniproxy net-tools busybox procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /var/log/sniproxy /etc/dnsmasq.d && \
    chmod 755 /var/log/sniproxy

# Configure sniproxy
RUN echo "user daemon\n\
pidfile /var/run/sniproxy.pid\n\
\n\
error_log {\n\
    filename /var/log/sniproxy/error.log\n\
    priority notice\n\
}\n\
\n\
access_log {\n\
    filename /var/log/sniproxy/access.log\n\
}\n\
\n\
listen 80 {\n\
    proto http\n\
    table http_hosts\n\
}\n\
\n\
listen 443 {\n\
    proto tls\n\
    table https_hosts\n\
}\n\
\n\
table http_hosts {\n\
    .* *:80\n\
}\n\
\n\
table https_hosts {\n\
    .* *:443\n\
}" > /etc/sniproxy.conf

# Configure basic dnsmasq settings
RUN echo "# Enable DNS service\n\
port=53\n\
# Use system DNS as upstream\n\
no-resolv\n\
server=8.8.8.8\n\
server=8.8.4.4\n\
# Read additional config from this directory\n\
conf-dir=/etc/dnsmasq.d/,*.conf\n\
# Don't read /etc/hosts\n\
no-hosts\n\
# Cache settings\n\
cache-size=1000\n\
" > /etc/dnsmasq.conf

# Start script - improved to handle signals properly
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Function to handle shutdown\n\
shutdown() {\n\
    echo "Shutting down services..."\n\
    kill -TERM "$dnsmasq_pid" 2>/dev/null || true\n\
    kill -TERM "$sniproxy_pid" 2>/dev/null || true\n\
    wait "$dnsmasq_pid" "$sniproxy_pid" 2>/dev/null || true\n\
    exit 0\n\
}\n\
\n\
trap shutdown SIGTERM SIGINT\n\
\n\
# Start dnsmasq in background\n\
echo "Starting dnsmasq..."\n\
dnsmasq --no-daemon &\n\
dnsmasq_pid=$!\n\
\n\
# Give dnsmasq a moment to start\n\
sleep 2\n\
\n\
# Start sniproxy in foreground\n\
echo "Starting sniproxy..."\n\
sniproxy -f -c /etc/sniproxy.conf &\n\
sniproxy_pid=$!\n\
\n\
# Wait for both processes\n\
wait -n\n\
\n\
# If either exits, shut down gracefully\n\
shutdown\n\
' > /start.sh && chmod +x /start.sh

EXPOSE 53/udp 53/tcp 80/tcp 443/tcp

CMD ["/start.sh"]
