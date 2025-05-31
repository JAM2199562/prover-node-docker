# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if running in CI environment (GitHub Actions, etc.)
if [ -z "$CI" ]; then
    # Only run environment check if not in CI
    echo "Running environment check..."
    sh "$SCRIPT_DIR/check_env.sh"
    
    # If check_dependencies.sh failed, stop execution
    if [ $? -ne 0 ]; then
        echo "Environment check error. Stopping execution. Please check README Environment for how to set up environment."
        exit 1
    fi
else
    echo "CI environment detected, skipping local environment checks..."
fi

# Build Docker image
echo "Building Docker image..."
DOCKER_BUILDKIT=0 docker build --rm --network=host -t zkwasm .

if [ $? -eq 0 ]; then
    echo "Docker image built successfully!"
else
    echo "Docker image build failed!"
    exit 1
fi