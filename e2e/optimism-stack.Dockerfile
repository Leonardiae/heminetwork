# Copyright (c) 2024 Hemi Labs, Inc.
# Use of this source code is governed by the MIT License,
# which can be found in the LICENSE file.

FROM golang:1.23.4-bookworm@sha256:ef30001eeadd12890c7737c26f3be5b3a8479ccdcdc553b999c84879875a27ce AS build_1

WORKDIR /git

ARG OP_GETH_CACHE_BREAK=12F2
RUN git clone https://github.com/hemilabs/op-geth
WORKDIR /git/op-geth
RUN git checkout f145b7de4198386c628891bdc39642642375c6bf

RUN go run build/ci.go install -static ./cmd/geth

FROM golang:1.22-alpine AS build_2

# store the latest geth here, build with go 1.23
COPY --from=build_1 /git/op-geth/build/bin/geth /bin/geth

RUN apk add jq nodejs npm just curl bash git

ENV SHELL="/bin/bash"

RUN curl -L https://foundry.paradigm.xyz | bash

RUN . /root/.bashrc

ENV PATH="${PATH}:/root/.foundry/bin"

RUN foundryup

RUN npm install -g pnpm

WORKDIR /git
COPY --from=build_1 /git/op-geth /git/op-geth
WORKDIR /git
RUN git clone https://github.com/hemilabs/optimism
WORKDIR /git/optimism
RUN git checkout 94c9daa37edc9ad3cabbba21c24d4842f07ef5a9

# as of now, we have the pop points address hard-coded as the rewards address
# for pop miners, this should change once we do TGE and mint HEMI
# we have no way to configure this AFAIK, so just replace the address in the 
# file so we reward to the GovernanceTokenAddr
# once this is changed back in optimism, remove this line
RUN sed -i 's/predeploys.PoPPointsAddr/predeploys.GovernanceTokenAddr/g' ./op-node/rollup/derive/pop_payout.go

RUN git submodule update --init --recursive
RUN pnpm install
RUN pnpm install:abigen
WORKDIR /git/optimism/packages/contracts-bedrock
RUN sed -e '/build_info/d' -i ./foundry.toml

FROM golang:1.24.2-alpine3.21@sha256:7772cb5322baa875edd74705556d08f0eeca7b9c4b5367754ce3f2f00041ccee AS build_3

RUN apk add jq nodejs npm just curl bash git

COPY --from=build_2 /git/optimism /git/optimism
COPY --from=build_2 /bin/geth /bin/geth

WORKDIR /git/optimism
RUN go mod tidy

WORKDIR /git/optimism/op-node
RUN just op-node

WORKDIR /git/optimism/op-batcher
RUN just op-batcher

WORKDIR /git/optimism/op-proposer
RUN just op-proposer

WORKDIR /git/optimism/op-conductor
RUN just op-conductor

WORKDIR /git/optimism
RUN pnpm build

WORKDIR /git/optimism/packages/contracts-bedrock
RUN forge install
RUN forge build

WORKDIR /git/optimism

RUN make devnet-allocs

RUN apk add netcat-openbsd
