## High-level targets

NAME=

.PHONY: tools build check serve run deploy logs publish

tools: tools.clean tools.get
build: build.local
check: check.imports check.fmt check.lint check.test
serve: serve.local
run: run.push.device
deploy: deploy.app
logs: logs.k8s
publish: publish.types


## Tools targets

TOOLS_DIR=$(PWD)/tools/bin

.PHONY: tools.clean tools.get

tools.clean:
	rm -fr $(TOOLS_DIR)/*

tools.get:
	cd $(PWD)/tools && go generate tools.go


## Build targets

DOCKER_IMAGE=$(NAME)

VERSION=$(shell cat VERSION)
GIT_COMMIT=$(shell git rev-list -1 HEAD --abbrev-commit)
TAG=$(VERSION)-$(GIT_COMMIT)

GO_ENV="GO111MODULE=on GOPRIVATE="

.PHONY: build.prepare build.swagger build.vendor build.vendor.full build.local build.docker build.docker.clear

build.prepare:
	@mkdir -p $(PWD)/target
	@rm -f $(PWD)/target/$(NAME)
	@rm -f $(PWD)/target/swagger.yaml

build.swagger: build.prepare
	cp swagger.yaml $(PWD)/target/swagger.yaml
	sed "s/#VERSION#/$(VERSION)/g" -i $(PWD)/target/swagger.yaml
	$(TOOLS_DIR)/swagger generate server -f $(PWD)/target/swagger.yaml
	$(TOOLS_DIR)/swagger generate client -f $(PWD)/target/swagger.yaml

build.vendor:
	$(GO_ENV) go mod vendor

build.vendor.full:
	@rm -fr $(PWD)/vendor
	$(GO_ENV) go mod tidy
	$(GO_ENV) go mod vendor

build.local: build.prepare
	GO111MODULE=on go build -mod=vendor $(BUILD_ARGS) -ldflags "-X full_package_name/gitutil.CommitID=$(GIT_COMMIT) -s -w" -o $(PWD)/target/$(NAME) $(PWD)/cmd/XXX_server

build.docker:
	DOCKER_BUILDKIT=1 docker build --ssh default --build-arg build_args="$(BUILD_ARGS)" -t $(DOCKER_IMAGE):$(TAG) -f Dockerfile .

build.docker.clear:
	docker image prune --filter label=stage=builder


## Check targets

LINT_COMMAND=$(TOOLS_DIR)/golangci-lint run -c $(PWD)/.golangci.yml
LINT_RESULT=$(PWD)/lint/result.txt
FILES_LIST=./internal/* ./restapi/configure_XXX.go

.PHONY: check.fmt check.imports check.lint check.test

check.fmt:
	GO111MODULE=on gofmt -s -w $(FILES_LIST)

check.imports:
	GO111MODULE=on goimports -w $(FILES_LIST)

check.lint:
	@rm -fr $(PWD)/lint
	@mkdir -p $(PWD)/lint
	GO111MODULE=on $(LINT_COMMAND) ./... >> $(LINT_RESULT) 2>&1
	
check.test:
	GO111MODULE=on go test XXX


## Serve targets

HOST=0.0.0.0
PORT=8080

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

COLORIZE=sed -u -e "s/\\\\\"/'/g; s/method=\([^ ]*\)/method=$(COLOR_BLUE)\1$(RESET_COLOR)/g; s/error=\"\([^\"]*\)\"/error=\"$(COLOR_RED)\1$(RESET_COLOR)\"/g; s/msg=\"\([^\"]*\)\"/msg=\"$(COLOR_YELLOW)\1$(RESET_COLOR)\"/g; s/level=trace/level=$(COLOR_LEVEL_TRACE)trace$(RESET_COLOR)/g; s/level=debug/level=$(COLOR_LEVEL_DEBUG)debug$(RESET_COLOR)/g; s/level=info/level=$(COLOR_LEVEL_INFO)info$(RESET_COLOR)/g; s/level=warning/level=$(COLOR_LEVEL_WARN)warning$(RESET_COLOR)/g; s/level=error/level=$(COLOR_LEVEL_ERROR)error$(RESET_COLOR)/g"

.PHONY: serve.local serve.docker serve.docker.stop serve.docker.logs

serve.local:
	@$(PWD)/target/$(NAME) --host=$(HOST) --port=$(PORT) -c $(PWD)/deploy/local/.$(NAME).yaml | $(COLORIZE)

serve.docker:
	docker run -d --rm -p $(PORT):$(PORT) -v $(PWD)/deploy/local/:/etc/$(NAME)/ --name $(NAME) $(DOCKER_IMAGE):$(TAG) -c /etc/$(NAME)/.$(NAME).yaml
	@docker logs -f $(NAME) | $(COLORIZE)

serve.docker.stop:
	docker stop $(NAME)

serve.docker.logs:
	@docker logs -f $(NAME) | $(COLORIZE)


## Run targets



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
	mkdir -p $(PWD)/target
	rm -f $(PWD)/target/app.yaml

deploy.app: deploy.check deploy.app.prepare
	cd $(PWD)/deploy/base && $(TOOLS_DIR)/kustomize edit set image app-image=$(DOCKER_IMAGE_FULL_NAME)
	@kubectl config use-context $(K8S_CTX)
	$(TOOLS_DIR)/kustomize build $(PWD)/deploy/overlays/$(ENV) -o $(PWD)/target/app.yaml
	kubectl apply -f $(PWD)/target/app.yaml


## Logs targets

DEPLOYMENT=deployment/$(NAME)

.PHONY: logs.k8s

logs.k8s:
	$(if $(ENV_SET), @kubectl config use-context $(K8S_CTX))
	@kubectl logs -n $(NAMESPACE) -f $(DEPLOYMENT) $(if $(TAIL), --tail=$(TAIL)) | $(COLORIZE)

