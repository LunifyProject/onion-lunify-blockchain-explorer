# Use ubuntu:20.04 as base for builder stage image
FROM ubuntu:20.04 as builder

# Set lunify branch/tag to be used for lunifyd compilation

ARG LUNIFY_BRANCH=release-v0.18

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install dependencies for lunifyd and lfiblocks compilation
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    cmake \
    miniupnpc \
    graphviz \
    doxygen \
    pkg-config \
    ca-certificates \
    zip \
    libboost-all-dev \
    libunbound-dev \
    libunwind8-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgtest-dev \
    libreadline-dev \
    libzmq3-dev \
    libsodium-dev \
    libhidapi-dev \
    libhidapi-libusb0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set compilation environment variables
ENV CFLAGS='-fPIC'
ENV CXXFLAGS='-fPIC'
ENV USE_SINGLE_BUILDDIR 1
ENV BOOST_DEBUG         1

WORKDIR /root

# Clone and compile lunifyd with all available threads
ARG NPROC
RUN git clone --recursive --branch ${LUNIFY_BRANCH} https://github.com/LunifyProject/Lunfiy.git \
    && cd Lunify \
    && test -z "$NPROC" && nproc > /nproc || echo -n "$NPROC" > /nproc && make -j"$(cat /nproc)"


# Copy and cmake/make lfiblocks with all available threads
COPY . /root/onion-lunify-blockchain-explorer/
WORKDIR /root/onion-lunify-blockchain-explorer/build
RUN cmake .. && make -j"$(cat /nproc)"

# Use ldd and awk to bundle up dynamic libraries for the final image
RUN zip /lib.zip $(ldd lfiblocks | grep -E '/[^\ ]*' -o)

# Use ubuntu:20.04 as base for final image
FROM ubuntu:20.04

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install unzip to handle bundled libs from builder stage
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /lib.zip .
RUN unzip -o lib.zip && rm -rf lib.zip

# Add user and setup directories for lunifyd and lfiblocks
RUN useradd -ms /bin/bash lunify \
    && mkdir -p /home/Lunify/.Lunify \
    && chown -R lunify:lunify /home/Lunify/.Lunify
USER lunify

# Switch to home directory and install newly built lfiblocks binary
WORKDIR /home/Lunify
COPY --chown=lunify:lunify --from=builder /root/onion-lunify-blockchain-explorer/build/lfiblocks .
COPY --chown=lunify:lunify --from=builder /root/onion-lunify-blockchain-explorer/build/templates ./templates/

# Expose volume used for lmdb access by lfiblocks
VOLUME /home/Lunify/.Lunify

# Expose default explorer http port
EXPOSE 8081

ENTRYPOINT ["/bin/sh", "-c"]

# Set sane defaults that are overridden if the user passes any commands
CMD ["./lfiblocks --enable-json-api --enable-autorefresh-option  --enable-pusher"]
