# syntax=docker/dockerfile:experimental

####################
#  Tools & Source  #
####################
FROM golang:1.13.8 AS tools

LABEL stage=builder

RUN mkdir -p /src
WORKDIR /src

COPY . ./

# For private repo
#RUN git config --global url."git@XXX:".insteadOf "https://XXX"

#RUN mkdir -p -m 0600 ~/.ssh && \
#    ssh-keyscan -t rsa xxx >> ~/.ssh/known_hosts

RUN --mount=type=ssh make tools build.vendor


#################
#  Build-time	#
#################
FROM tools AS build

LABEL stage=builder

ARG build_args
RUN GOOS=linux GOARCH=amd64 make build.local BUILD_ARGS="${build_args}"


#################
#	Run-time	#
#################
FROM gcr.io/distroless/base

COPY --from=build /src/target/server /usr/bin/server

# API port
EXPOSE 19101

ENTRYPOINT ["/usr/bin/server", "--host=0.0.0.0", "--port=19101"]
