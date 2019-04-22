.PHONY install
install:
	docker build -t apex . && docker run --rm -it apex
