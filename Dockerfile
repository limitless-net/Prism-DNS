FROM debian:latest

# Install dnsmasq and sniproxy
RUN apt-get update && \
    apt-get install -y dnsmasq sniproxy net-tools busybox && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

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

# Create log directories
RUN mkdir -p /var/log/sniproxy && \
    chmod 755 /var/log/sniproxy

# Start script
RUN echo '#!/bin/bash\n\
# Start dnsmasq\n\
dnsmasq --no-daemon -C /etc/dnsmasq.d/custom_unlock.conf &\n\
\n\
# Start sniproxy\n\
sniproxy -f -c /etc/sniproxy.conf\n\
' > /start.sh && chmod +x /start.sh

CMD ["/start.sh"]
