# Build with Elixir 1.5/OTP 20
FROM elixir:1.5-slim as builder

RUN apt-get -qq update && apt-get -qq install git build-essential libssl-dev curl

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix hex.info

WORKDIR /build
ENV MIX_ENV prod

# Let's start by building VerneMQ 1.2.2
RUN git clone https://github.com/erlio/vernemq.git && \
		cd vernemq && \
		git checkout 1.2.2 && \
		make rel && \
		cd ..

# Time for VerneMQ's Astarte plugin
RUN git clone https://git.ispirata.com/Astarte-NG/astarte_vmq_plugin.git && \
		cd astarte_vmq_plugin && \
		mix deps.get && \
		mix release --env=$MIX_ENV && \
		cd ..

# Copy the schema over
RUN cp astarte_vmq_plugin/priv/astarte_vmq_plugin.schema vernemq/_build/default/rel/vernemq/share/schema/

# Copy configuration files here - mainly because we want to keep the target image as small as possible
# and avoid useless layers.
COPY files/vm.args /build/vernemq/_build/default/rel/vernemq/etc/
COPY files/vernemq.conf /build/vernemq/_build/default/rel/vernemq/etc/
COPY bin/rand_cluster_node.escript /build/vernemq/_build/default/rel/vernemq/bin/
COPY bin/vernemq.sh /build/vernemq/_build/default/rel/vernemq/bin/
RUN chmod +x /build/vernemq/_build/default/rel/vernemq/bin/vernemq.sh

# Note: it is important to keep Debian versions in sync, or incompatibilities between libcrypto will happen
FROM debian:jessie-slim

# Set the locale
ENV LANG C.UTF-8

# We need SSL, curl and jq - and to ensure /etc/ssl/astarte
RUN apt-get -qq update && apt-get -qq install libssl1.0.0 curl jq && apt-get clean && mkdir -p /etc/ssl/astarte

WORKDIR /opt
# Copy our built stuff (both are self-contained with their ERTS release)
COPY --from=builder /build/vernemq/_build/default/rel/vernemq .
COPY --from=builder /build/astarte_vmq_plugin/_build/prod/rel/astarte_vmq_plugin .

# MQTT
EXPOSE 1883

# MQTT for Reverse Proxy
EXPOSE 1885

# MQTT/SSL
EXPOSE 8883

# VerneMQ Message Distribution
EXPOSE 44053

# EPMD - Erlang Port Mapper Daemon
EXPOSE 4369

# Specific Distributed Erlang Port Range
EXPOSE 9100 9101 9102 9103 9104 9105 9106 9107 9108 9109

# Prometheus Metrics
EXPOSE 8888

CMD ["/opt/vernemq/bin/vernemq.sh"]
