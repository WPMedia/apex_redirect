from nginx
cmd [ '/usr/bin/supervisord', '-c', '/etc/supervisor/supervisord.conf' ]

run \
  apt update -y \
    || exit 1; \
  apt install -y python-certbot-nginx busybox supervisor \
    || exit 1; \
  busybox --install \
    || exit 1; \
  true

add files/ /

run nginx -T || exit 1
