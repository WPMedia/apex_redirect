from nginx
cmd bash

run \
  apt update -y \
    || exit 1; \
  apt install -y python-certbot-nginx busybox \
    || exit 1; \
  busybox --install \
    || exit 1; \
  true

add files/ /

run nginx -T || exit 1
