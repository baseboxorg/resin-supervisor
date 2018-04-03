ARG ARCH=amd64

# The node version here should match the version of the runtime image which is
# specified in the base-image subdirectory in the project
FROM resin/rpi-node:6.13.1-slim as rpi-node-base
FROM resin/armv7hf-node:6.13.1-slim as armv7hf-node-base
FROM resin/aarch64-node:6.13.1-slim as aarch64-node-base

FROM resin/amd64-node:6.13.1-slim as amd64-node-base
RUN echo '#!/bin/sh\nexit 0' > /usr/bin/cross-build-start && chmod +x /usr/bin/cross-build-start \
	&& echo '#!/bin/sh\nexit 0' > /usr/bin/cross-build-end && chmod +x /usr/bin/cross-build-end

FROM resin/i386-node:6.13.1-slim as i386-node-base
RUN echo '#!/bin/sh\nexit 0' > /usr/bin/cross-build-start && chmod +x /usr/bin/cross-build-start \
	&& echo '#!/bin/sh\nexit 0' > /usr/bin/cross-build-end && chmod +x /usr/bin/cross-build-end

FROM i386-node-base as i386-nlp-node-base

##############################################################################

# We always do the webpack build on amd64, cause it's way faster
FROM amd64-node-base as node-build

WORKDIR /usr/src/app

RUN apt-get update \
	&& apt-get install -y \
		g++ \
		git \
		libsqlite3-dev \
		make \
		python \
		rsync \
		wget \
	&& rm -rf /var/lib/apt/lists/

COPY package.json /usr/src/app/

RUN JOBS=MAX npm install --no-optional --unsafe-perm

COPY webpack.config.js fix-jsonstream.js hardcode-migrations.js /usr/src/app/
COPY src /usr/src/app/src

RUN npm run lint \
	&& npm run build

##############################################################################

# Build nodejs dependencies
FROM $ARCH-node-base as node-deps
ARG ARCH

RUN [ "cross-build-start" ]

WORKDIR /usr/src/app

RUN apt-get update \
	&& apt-get install -y \
		g++ \
		git \
		libsqlite3-dev \
		make \
		python \
		rsync \
		wget \
	&& rm -rf /var/lib/apt/lists/

RUN mkdir -p rootfs-overlay && \
	ln -s /lib rootfs-overlay/lib64

COPY package.json /usr/src/app/

# Install only the production modules that have C extensions
RUN JOBS=MAX npm install --production --no-optional --unsafe-perm \
	&& npm dedupe

# Remove various uneeded filetypes in order to reduce space
# We also remove the spurious node.dtps, see https://github.com/mapbox/node-sqlite3/issues/861
RUN find . -path '*/coverage/*' -o -path '*/test/*' -o -path '*/.nyc_output/*' \
		-o -name '*.tar.*'      -o -name '*.in'     -o -name '*.cc' \
		-o -name '*.c'          -o -name '*.coffee' -o -name '*.eslintrc' \
		-o -name '*.h'          -o -name '*.html'   -o -name '*.markdown' \
		-o -name '*.md'         -o -name '*.patch'  -o -name '*.png' \
		-o -name '*.yml' \
		-delete \
	&& find . -type f -path '*/node_modules/sqlite3/deps*' -delete \
	&& find . -type f -path '*/node_modules/knex/build*' -delete \
	&& rm -rf node_modules/sqlite3/node.dtps

COPY entry.sh package.json rootfs-overlay/usr/src/app/

RUN rsync -a --delete node_modules rootfs-overlay /build

RUN [ "cross-build-end" ]

##############################################################################

# Minimal runtime image
FROM resin/$ARCH-supervisor-base:node-6.13.1
ARG ARCH
ARG VERSION=master
ARG DEFAULT_PUBNUB_PUBLISH_KEY=pub-c-bananas
ARG DEFAULT_PUBNUB_SUBSCRIBE_KEY=sub-c-bananas
ARG DEFAULT_MIXPANEL_TOKEN=bananasbananas

WORKDIR /usr/src/app

COPY --from=node-build /usr/src/app/dist ./dist
COPY --from=node-deps /build/node_modules ./node_modules
COPY --from=node-deps /build/rootfs-overlay/ /

VOLUME /data

ENV CONFIG_MOUNT_POINT=/boot/config.json \
	LED_FILE=/dev/null \
	SUPERVISOR_IMAGE=resin/$ARCH-supervisor \
	VERSION=$VERSION \
	DEFAULT_PUBNUB_PUBLISH_KEY=$DEFAULT_PUBNUB_PUBLISH_KEY \
	DEFAULT_PUBNUB_SUBSCRIBE_KEY=$DEFAULT_PUBNUB_SUBSCRIBE_KEY \
	DEFAULT_MIXPANEL_TOKEN=$DEFAULT_MIXPANEL_TOKEN

HEALTHCHECK --interval=5m --start-period=1m --timeout=30s --retries=3 \
	CMD wget -qO- http://127.0.0.1:${LISTEN_PORT:-48484}/v1/healthy || exit 1

CMD [ "./entry.sh" ]
