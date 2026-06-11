# Pinned to a published hexpm/elixir tag (the 1.18.4/28.0/20250317 combo was
# never published to Docker Hub, so this image could never build).
ARG ELIXIR_VERSION=1.18.2
ARG OTP_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Set build-time env
ENV MIX_ENV="prod"

# Copy the lantern library (dep of demo via path)
COPY mix.exs mix.lock ./
COPY lib ./lib
COPY priv ./priv

# Copy the demo app at the same relative path as in the repo so the
# `path: "../.."` dep in mix.exs resolves to /app (the lantern root).
COPY examples/demo ./examples/demo

WORKDIR /app/examples/demo

# Fetch dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Compile the demo app
RUN mix compile

# Build release
RUN mix phx.gen.release 2>/dev/null || true
RUN mix release

# Runner stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /app

RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/examples/demo/_build/prod/rel/lantern_demo ./

USER nobody

CMD ["/app/bin/server"]
