nvidia-smi && \
# Check available memory
mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mem_available_gb=$((mem_available / 1024 / 1024))
echo "----------Available memory: $mem_available_gb GB---------------------------"

# Set your required memory threshold here (in GB)
required_memory=80

if [ "$mem_available_gb" -lt "$required_memory" ]; then
    echo "Error: Available memory ($mem_available_gb GB) is less than the required $required_memory GB."
    exit 1
fi

# Huge Pages
echo 'Checking Huge Pages configuration:'
cat /proc/meminfo | grep Huge
ls -lh /dev/hugepages

# Check HugePages_Free
hugepages_free=$(cat /proc/meminfo | grep -i hugepages_free | awk '{print $2}')
echo "HugePages_Free: $hugepages_free"

if [ $hugepages_free -lt 15000 ]; then
    echo "Error: HugePages_Free ($hugepages_free) is less than 15000. Please make sure HugePages is configured correctly on the host machine. Requires 15000 HugePages configured per node."
    exit 1
fi

sudo chown -R 1001:1001 rocksdb

# Verify parameter files (now built into the image)
echo "Checking parameter files..."
if [ ! -d "workspace/static" ] || [ -z "$(ls -A workspace/static/*.params 2>/dev/null)" ]; then
    echo "Error: Parameter files not found in workspace/static/"
    echo "Parameter files should be built into the Docker image."
    echo "Please rebuild the image to include parameter files."
    exit 1
fi

echo "Parameter files found:"
ls -la workspace/static/*.params

# Start the prover
time=$(date +%Y-%m-%d-%H-%M-%S) && \
CUDA_VISIBLE_DEVICES=0 RUST_LOG=info RUST_BACKTRACE=1 ./target/release/zkwasm-playground --config prover_config.json -w workspace --proversystemconfig prover_system_config.json -p --rocksdbworkspace rocksdb \
      2>&1 | rotatelogs -e -n 10 logs/prover/prover_${time}.log 100M