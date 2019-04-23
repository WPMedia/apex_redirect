build:
	docker build -t apex .

run:
	-docker rm -f apex
	docker run --rm -it -p 80:80 -p 443:443 --name apex apex

exec:
	docker exec -it apex bash

debug:
	-docker rm -f apex
	docker run --rm -it -p 80:80 -p 443:443 --name apex --entrypoint /bin/bash apex

or:
	-docker rm -f openresty 
	docker run --rm -it --name openresty --entrypoint /bin/bash openresty/openresty
