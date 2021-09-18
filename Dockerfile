# syntax=docker/dockerfile:1.2

####################
#  Tools & Source  #
####################
FROM golang:1.17 AS build

LABEL stage=builder

RUN mkdir -p /src
WORKDIR /src

COPY . ./

# For private repo
#RUN git config --global url."git@XXX:".insteadOf "https://XXX"

#RUN mkdir -p -m 0600 ~/.ssh && \
#    ssh-keyscan -t rsa xxx >> ~/.ssh/known_hosts

RUN --mount=type=ssh if [ ! -d "./vendor" ]; then make build.vendor; fi

ARG build_args
RUN GOOS=linux GOARCH=amd64 make build.local BUILD_ARGS="${build_args}"


#################
#	Run-time	#
#################
FROM gcr.io/distroless/base

COPY --from=build /src/target/server /usr/bin/server

# API port
EXPOSE 8080

# Metrics port
EXPOSE 7777

ENTRYPOINT ["/usr/bin/server", "--port", "8080"]


