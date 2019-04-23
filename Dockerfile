from openresty/openresty

run \
  apt update -y \
    || exit 1; \
  apt install -y python-certbot-nginx busybox supervisor curl dnsutils \
    || exit 1; \
  busybox --install \
    || exit 1; \
  true

run \
  rm /etc/nginx/sites-enabled/default \
    || exit 1; \
  true

add files/ /
run chmod +x /manage_certs

run openresty -T || exit 1

cmd [ "/usr/bin/supervisord", "--nodaemon", "-c", "/etc/supervisor/supervisord.conf" ]
