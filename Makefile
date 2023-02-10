## High-level targets

.PHONY: tools build check serve deploy logs

help: help.all
tools: tools.clean tools.get
build: build.local
check: check.imports check.fmt check.lint check.test
serve: serve.local
deploy: deploy.app
logs: logs.k8s
changelog: changelog.generate

# Colors used in this Makefile
escape=$(shell printf '\033')
RESET_COLOR=$(escape)[0m
COLOR_YELLOW=$(escape)[38;5;220m
COLOR_RED=$(escape)[91m
COLOR_BLUE=$(escape)[94m

COLOR_LEVEL_TRACE=$(escape)[38;5;87m
COLOR_LEVEL_DEBUG=$(escape)[38;5;87m
COLOR_LEVEL_INFO=$(escape)[92m
COLOR_LEVEL_WARN=$(escape)[38;5;208m
COLOR_LEVEL_ERROR=$(escape)[91m
COLOR_LEVEL_FATAL=$(escape)[91m

define COLORIZE
sed -u -e "s/\\\\\"/'/g; \
s/method=\([^ ]*\)/method=$(COLOR_BLUE)\1$(RESET_COLOR)/g;        \
s/error=\"\([^\"]*\)\"/error=\"$(COLOR_RED)\1$(RESET_COLOR)\"/g;  \
s/msg=\"\([^\"]*\)\"/msg=\"$(COLOR_YELLOW)\1$(RESET_COLOR)\"/g;   \
s/level=trace/level=$(COLOR_LEVEL_TRACE)trace$(RESET_COLOR)/g;    \
s/level=debug/level=$(COLOR_LEVEL_DEBUG)debug$(RESET_COLOR)/g;    \
s/level=info/level=$(COLOR_LEVEL_INFO)info$(RESET_COLOR)/g;       \
s/level=warning/level=$(COLOR_LEVEL_WARN)warning$(RESET_COLOR)/g; \
s/level=error/level=$(COLOR_LEVEL_ERROR)error$(RESET_COLOR)/g;    \
s/level=fatal/level=$(COLOR_LEVEL_FATAL)fatal$(RESET_COLOR)/g"
endef


#####################
# Help targets      #
#####################

.PHONY: help.highlevel help.all

#help help.highlevel: show help for high level targets
help.highlevel:
	@grep -hE '^[a-z_-]+:' $(MAKEFILE_LIST) | LANG=C sort -d | \
	awk 'BEGIN {FS = ":"}; {printf("$(COLOR_YELLOW)%-25s$(RESET_COLOR) %s\n", $$1, $$2)}'

#help help.all: display all targets' help messages
help.all:
	@grep -hE '^#help|^[a-z_-]+:' $(MAKEFILE_LIST) | sed "s/#help //g" | LANG=C sort -d | \
	awk 'BEGIN {FS = ":"}; {if ($$1 ~ /\./) printf("    $(COLOR_BLUE)%-21s$(RESET_COLOR) %s\n", $$1, $$2); else printf("$(COLOR_YELLOW)%-25s$(RESET_COLOR) %s\n", $$1, $$2)}'


#####################
# Tools targets     #
#####################

TOOLS_DIR=$(CURDIR)/tools/bin

.PHONY: tools.clean tools.get

#help tools.clean: remove every tools installed in tools/bin directory
tools.clean:
	rm -fr $(TOOLS_DIR)/*

#help tools.get: retrieve all tools specified in gex
tools.get:
	cd $(CURDIR)/tools && go generate tools.go


#####################
# Build targets     #
#####################

VERSION=$(shell cat VERSION)
GIT_COMMIT=$(shell git rev-list -1 HEAD --abbrev-commit)

IMAGE_NAME=$(NAME)
IMAGE_TAG=$(VERSION)-$(GIT_COMMIT)

GO_ENV=GOPRIVATE=

.PHONY: build.prepare build.swagger build.vendor build.vendor.full build.local build.docker build.docker.clear

#help build.prepare: prepare target/ folder
build.prepare:
	@mkdir -p $(CURDIR)/target
	@rm -f $(CURDIR)/target/$(NAME)
	@rm -f $(CURDIR)/target/swagger.yaml

#help build.swagger: generate server & client stub from swagger file
build.swagger: build.prepare
	cp swagger.yaml $(CURDIR)/target/swagger.yaml
	sed "s/#VERSION#/$(VERSION)/g" -i $(CURDIR)/target/swagger.yaml
	$(TOOLS_DIR)/swagger generate server -f $(CURDIR)/target/swagger.yaml
	$(TOOLS_DIR)/swagger generate client -f $(CURDIR)/target/swagger.yaml

#help build.vendor: retrieve all the dependencies used for the project
build.vendor:
	$(GO_ENV) go mod vendor

#help build.vendor.full: retrieve all the dependencies after cleaning the go.sum
build.vendor.full:
	@rm -fr $(CURDIR)/vendor
	$(GO_ENV) go mod tidy
	$(GO_ENV) go mod vendor

#help build.local: build locally a binary, in target/ folder
build.local: build.prepare
	go build -mod=vendor $(BUILD_ARGS) -ldflags "-X github.com/pastequo/libs.golang.utils/gitutil.CommitID=$(GIT_COMMIT) -s -w" -o $(CURDIR)/target/server $(CURDIR)/cmd/$(NAME)-server/main.go

#help build.docker: build a docker image
build.docker:
	DOCKER_BUILDKIT=1 docker build --ssh default --build-arg build_args="$(BUILD_ARGS)" -t $(IMAGE_NAME):$(IMAGE_TAG) -f Dockerfile .


#####################
# Check targets     #
#####################

LINT_COMMAND=$(TOOLS_DIR)/golangci-lint run -c $(CURDIR)/.golangci.yml
FILES_LIST=$(shell ls -d */ | grep -v -E "vendor|tools|target")

.PHONY: check.fmt check.imports check.lint check.test check.licenses

#help check.fmt: format go code
check.fmt:
	$(TOOLS_DIR)/gofumpt -s -w $(FILES_LIST)

#help check.imports: fix and format go imports
check.imports:
	$(TOOLS_DIR)/goimports -w $(FILES_LIST)

#help check.lint: check if the go code is properly written, rules are in .golangci.yml
check.lint:
	$(TOOLS_DIR)/golangci-lint run -c $(CURDIR)/.golangci.yml

#help check.test: execute go unit tests
check.test:
	go test -mod=vendor ./...

#help check.licenses: check if the thirdparties' licences are whitelisted (in .wwhrd.yml)
check.licenses:
	$(TOOLS_DIR)/wwhrd check


#####################
# Serve targets     #
#####################

HOST=0.0.0.0
PORT=8080

.PHONY: serve.local serve.docker serve.docker.stop serve.docker.logs

#help serve.local: start server locally
serve.local:
	@$(CURDIR)/target/server --host=$(HOST) --port=$(PORT) -c $(CURDIR)/deploy/local/.$(NAME).yaml | $(COLORIZE)

#help serve.docker: 
serve.docker:
	docker run -d --rm -p $(PORT):$(PORT) -v $(CURDIR)/deploy/local/:/etc/$(NAME)/ --name $(NAME) $(IMAGE_NAME):$(IMAGE_TAG) -c /etc/$(NAME)/.$(NAME).yaml
	@docker logs -f $(NAME) | $(COLORIZE)

#help serve.docker.stop: stop docker container
serve.docker.stop:
	docker stop $(NAME)

#help serve.docker.logs: display docker container logs
serve.docker.logs:
	@docker logs -f $(NAME) | $(COLORIZE)



## Deploy targets

USERNAME=XXX
NAMESPACE=XXX

.PHONY: deploy.check deploy.check.notlocal deploy.docker.login deploy.docker deploy.app.prepare deploy.app

ifeq ($(ENV),local)
  ENV_SET=1
  DOCKER_IMAGE_FULL_NAME=$(DOCKER_IMAGE):$(TAG)
  K8S_CTX="minikube"
else ifeq ($(ENV),dev)
  ENV_SET=1
  DOCKER_REGISTRY="XXX"
  DOCKER_IMAGE_FULL_NAME=$(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(TAG)
  K8S_CTX="XXX"
else ifeq ($(ENV),prod)
  ENV_SET=1
  DOCKER_REGISTRY="XXX"
  DOCKER_IMAGE_FULL_NAME=$(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(TAG)
  K8S_CTX="XXX"
endif

deploy.check:
	@if [ "$(ENV_SET)" = "" ]; then echo "$(COLOR_RED)ERROR: ENV is mandatory, could be 'local', 'dev' or 'prod'$(RESET_COLOR)"; exit 1; fi

deploy.check.notlocal:
	@if [ "$(ENV)" = "local" ]; then echo "$(COLOR_RED)ERROR: 'local' ENV does not make sense for this target$(RESET_COLOR)"; exit 1; fi


deploy.docker.login: deploy.check deploy.check.notlocal
	docker login $(DOCKER_REGISTRY) -u $(USERNAME)

deploy.docker: deploy.check deploy.check.notlocal
	docker tag $(DOCKER_IMAGE):$(TAG) $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(TAG)
	docker push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(TAG)

deploy.app.prepare:
	mkdir -p $(CURDIR)/target
	rm -f $(CURDIR)/target/app.yaml

deploy.app: deploy.check deploy.app.prepare
	cd $(CURDIR)/deploy/base && $(TOOLS_DIR)/kustomize edit set image app-image=$(DOCKER_IMAGE_FULL_NAME)
	@kubectl config use-context $(K8S_CTX)
	$(TOOLS_DIR)/kustomize build $(CURDIR)/deploy/overlays/$(ENV) -o $(CURDIR)/target/app.yaml
	kubectl apply -f $(CURDIR)/target/app.yaml


#####################
# Logs targets      #
#####################

DEPLOYMENT=deployment/$(NAME)

.PHONY: logs.k8s

#help logs.k8s: display pod logs, use ENV to choose target cluster
logs.k8s:
	$(if $(ENV_SET), @kubectl config use-context $(K8S_CTX))
	@kubectl logs -n $(NAMESPACE) -f $(DEPLOYMENT) $(if $(TAIL), --tail=$(TAIL)) | $(COLORIZE)


#####################
# Changelog targets #
#####################

.PHONY: changelog.generate

#help changelog.generate: regenerate full changelog
changelog.generate:
	$(TOOLS_DIR)/git-chglog --output CHANGELOG.md ..v$(VERSION)


#####################
# Include section   #
#####################

# include custom targets and variable
-include ./custom.mk

