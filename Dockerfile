FROM nvidia/cuda:12.2.0-devel-ubuntu22.04
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install required packages and setup ssh access
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server sudo cmake curl build-essential git wget \
    jq nano vim htop procps pure-ftpd supervisor && \
    rm -rf /var/lib/apt/lists/* && \
    sudo apt update -y && sudo apt install -y apache2-utils && \
    mkdir /var/run/sshd && \
    /etc/init.d/ssh start && \
    useradd -rm -d /home/zkwasm -s /bin/bash -g root -G sudo -u 1001 zkwasm && \
    echo 'zkwasm:zkwasm' | chpasswd && \
    echo 'zkwasm ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

# Setup FTP server for params
RUN useradd -rm -d /home/ftpuser -s /bin/bash -u 1002 ftpuser && \
    echo 'ftpuser:ftppassword' | chpasswd && \
    mkdir -p /home/ftpuser/params && \
    chown -R ftpuser:ftpuser /home/ftpuser

# Configure pure-ftpd
RUN echo "ftpuser:ftppassword:1002:1002::/home/ftpuser:/bin/bash" > /etc/pure-ftpd/pureftpd.passwd && \
    pure-pw mkdb && \
    echo "yes" > /etc/pure-ftpd/conf/CreateHomeDir && \
    echo "yes" > /etc/pure-ftpd/conf/ChrootEveryone && \
    echo "no" > /etc/pure-ftpd/conf/AnonymousOnly && \
    echo "21" > /etc/pure-ftpd/conf/Bind && \
    echo "30000 30100" > /etc/pure-ftpd/conf/PassivePortRange

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
    mkdir -p workspace && \
    mkdir -p rocksdb

# Copy scripts
COPY smart_entrypoint.sh /home/zkwasm/smart_entrypoint.sh
COPY vast_ai_launcher.sh /home/zkwasm/vast_ai_launcher.sh
COPY download_params.sh /home/zkwasm/download_params.sh

# Switch to root to set permissions and setup supervisor
USER root

# Set up permissions
RUN chmod +x /home/zkwasm/smart_entrypoint.sh && \
    chown zkwasm:root /home/zkwasm/smart_entrypoint.sh && \
    chmod +x /home/zkwasm/vast_ai_launcher.sh && \
    chown zkwasm:root /home/zkwasm/vast_ai_launcher.sh && \
    chmod +x /home/zkwasm/download_params.sh && \
    chown zkwasm:root /home/zkwasm/download_params.sh && \
    chown zkwasm:root /home/zkwasm/prover-node-release/prover_config.json && \
    chown zkwasm:root /home/zkwasm/prover-node-release/prover_system_config.json

# Create supervisor configuration for managing both FTP and zkwasm services
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY unified_entrypoint.sh /home/zkwasm/unified_entrypoint.sh
RUN chmod +x /home/zkwasm/unified_entrypoint.sh && \
    chown zkwasm:root /home/zkwasm/unified_entrypoint.sh

# Expose SSH and FTP ports for vast.ai access
EXPOSE 22 21 30000-30100

# Switch back to zkwasm user
USER zkwasm

WORKDIR /home/zkwasm/prover-node-release

# Set environment variables for CUDA and logging
ENV CUDA_VISIBLE_DEVICES=0
ENV RUST_LOG=info
ENV RUST_BACKTRACE=1

# Use unified entrypoint that manages both FTP server and zkwasm prover
ENTRYPOINT ["/home/zkwasm/unified_entrypoint.sh"]
