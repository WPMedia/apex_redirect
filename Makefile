build:
	docker build -t apex .
run:
	docker run --rm -it -p 80:80 -p 443:443 apex
