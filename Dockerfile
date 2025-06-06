# Multi-stage build: First stage to extract params from zkwasm/params image
FROM zkwasm/params as params-source

# Main build stage
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server sudo cmake curl build-essential git wget \
    jq nano vim htop procps && \
    rm -rf /var/lib/apt/lists/* && \
    sudo apt update -y && sudo apt install -y apache2-utils && \
    mkdir /var/run/sshd && \
    /etc/init.d/ssh start && \
    useradd -rm -d /home/zkwasm -s /bin/bash -g root -G sudo -u 1001 zkwasm && \
    echo 'zkwasm:zkwasm' | chpasswd && \
    echo 'zkwasm ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

# Switch to the zkwasm user for subsequent commands
USER zkwasm

WORKDIR /home/zkwasm
# Support for cloning from github via https 
RUN git config --global url.https://github.com/.insteadOf git@github.com: 

RUN git clone https://github.com/DelphinusLab/prover-node-release && \
    cd prover-node-release && \
    git checkout 11bd77a4933fa4d289627e2b3e5d7e8be58a565f

WORKDIR /home/zkwasm/prover-node-release

# Unpack tarball
RUN tar -xvf prover_node_Ubuntu2204.tar

# Copy additional configuration files (override defaults from tarball)
COPY prover_config.json /home/zkwasm/prover-node-release/prover_config.json
COPY prover_system_config.json /home/zkwasm/prover-node-release/prover_system_config.json

# Create prover log folder and other necessary directories
RUN mkdir -p logs/prover && \
    mkdir -p workspace/static && \
    mkdir -p rocksdb

# Copy parameter files from zkwasm/params image (build-time copy)
COPY --from=params-source /home/ftpuser/params/* /home/zkwasm/prover-node-release/workspace/static/

# Copy the smart entrypoint script
COPY smart_entrypoint.sh /home/zkwasm/smart_entrypoint.sh

# Switch to root to set permissions 
USER root

# Set up permissions for all files
RUN chmod +x /home/zkwasm/smart_entrypoint.sh && \
    chown zkwasm:root /home/zkwasm/smart_entrypoint.sh && \
    chown zkwasm:root /home/zkwasm/prover-node-release/prover_config.json && \
    chown zkwasm:root /home/zkwasm/prover-node-release/prover_system_config.json && \
    chown -R zkwasm:root /home/zkwasm/prover-node-release/workspace/static/

# Expose SSH port
EXPOSE 22

# Switch back to zkwasm user
USER zkwasm

WORKDIR /home/zkwasm/prover-node-release

# Set environment variables for CUDA and logging
ENV CUDA_VISIBLE_DEVICES=0
ENV RUST_LOG=info
ENV RUST_BACKTRACE=1

# Use smart entrypoint as default
ENTRYPOINT ["/home/zkwasm/smart_entrypoint.sh"]
