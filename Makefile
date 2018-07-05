all: clean build-prod

RELEASE_VERSION := $(shell cat apps/ewallet/mix.exs |grep -i version |tr -d '[:blank:]' |cut -d"\"" -f2)
DOCKER_NAME     := "omisego/ewallet:dev"
DOCKER_BUILDER  := "omisegoimages/ewallet-builder:beec6e8"

#
# Setting-up
#

.PHONY: deps

deps:
	mix deps.get

clean:
	rm -rf _build/
	rm -rf deps/
	rm -rf apps/admin_panel/node_modules
	rm -rf apps/admin_panel/priv/static

#
# Linting
#

.PHONY: lint

format:
	mix format

lint:
	mix format --check-formatted
	mix credo

#
# Building
#

.PHONY: build-assets build-prod build-test

build-assets:
	cd apps/admin_panel/assets && \
		yarn install && \
		yarn build

# If we call mix phx.digest without mix compile, mix release will silently fail
# for some reason. Always make sure to run mix compile first.
build-prod: build-assets deps
	env MIX_ENV=prod mix compile
	env MIX_ENV=prod mix phx.digest
	env MIX_ENV=prod mix release

build-test: deps
	env MIX_ENV=test mix compile

#
# Testing
#

.PHONY: test

test: build-test
	env MIX_ENV=test mix do ecto.create, ecto.migrate, test

#
# Docker
#

.PHONY: docker-local docker-local-prod docker-local-build docker-local-up docker-local-down

docker-local-prod:
	docker run --rm -it \
		-v $(PWD):/app \
		-u root \
		--entrypoint /bin/sh \
		$(DOCKER_BUILDER) \
		-c "cd /app && make build-prod"

docker-local-build:
	cp _build/prod/rel/ewallet/releases/$(RELEASE_VERSION)/ewallet.tar.gz .
	docker build . -t $(DOCKER_NAME)
	rm ewallet.tar.gz

docker-local-up:
	cd vendor/docker-local && docker-compose up -d

docker-local-down:
	cd vendor/docker-local && docker-compose down

docker-local: docker-local-prod docker-local-build
