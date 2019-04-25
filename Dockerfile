from openresty/openresty

run \
    apt update -y \
        || exit 1; \
    apt install -y python-certbot-nginx busybox supervisor curl dnsutils \
        || exit 1; \
    busybox --install \
        || exit 1; \
    rm /etc/nginx/sites-enabled/default \
        || exit 1; \
    true

run \
    openssl req -x509 -newkey rsa:4096 -keyout /etc/nginx/key.pem -out /etc/nginx/cert.pem -days 365 -nodes -subj '/CN=localhost' \
        || exit 1; \
    mkdir -m 777 -p /etc/letsencrypt/live \
        || exit 1; \
    true

run \
    opm get spacewander/luafilesystem \
        || exit 1; \
    true

add files/ /
run chmod +x /manage_certs

run openresty -t || exit 1

cmd [ "/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisor/supervisord.conf" ]
