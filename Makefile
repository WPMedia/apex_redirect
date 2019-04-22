build:
	docker build -t apex .
run:
	docker run --rm -it -p 80:80 -p 443:443 --name apex apex
debug:
	docker run --rm -it -p 80:80 -p 443:443 --name apex-debug --entrypoint /bin/bash apex
