all: clean build-prod

RELEASE_VERSION := $(shell cat apps/ewallet/mix.exs |grep -i version |tr -d '[:blank:]' |cut -d"\"" -f2)
DOCKER_NAME     := "omisego/ewallet:dev"
DOCKER_BUILDER  := "omisegoimages/ewallet-builder:beec6e8"

#
# Setting-up
#

.PHONY: deps deps-ewallet deps-assets

deps: deps-ewallet deps-assets

deps-ewallet:
	mix deps.get

deps-assets:
	cd apps/admin_panel/assets && \
		yarn install

#
# Cleaning
#

.PHONY: clean clean-ewallet clean-assets

clean: clean-ewallet clean-assets

clean-ewallet:
	rm -rf _build/
	rm -rf deps/

clean-assets:
	rm -rf apps/admin_panel/assets/node_modules
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

build-assets: deps-assets
	cd apps/admin_panel/assets && \
		yarn build

# If we call mix phx.digest without mix compile, mix release will silently fail
# for some reason. Always make sure to run mix compile first.
build-prod: deps-ewallet build-assets
	env MIX_ENV=prod mix compile
	env MIX_ENV=prod mix phx.digest
	env MIX_ENV=prod mix release

build-test: deps-ewallet
	env MIX_ENV=test mix compile

#
# Testing
#

.PHONY: test test-ewallet test-assets

test: test-ewallet test-assets

test-ewallet: build-test
	env MIX_ENV=test mix do ecto.create, ecto.migrate, test

test-assets: build-assets
	cd apps/admin_panel/assets && \
		yarn test

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
