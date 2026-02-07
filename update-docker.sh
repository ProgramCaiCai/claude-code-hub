#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
DEPLOY_DIR=""
BUILD_PLATFORM=""
NO_CACHE=false
SKIP_PULL=false

show_help() {
    cat << EOF
Claude Code Hub - Docker Update Script

Usage: $0 [OPTIONS]

Options:
  -d, --deploy-dir <path>    Deployment directory (required)
  -p, --platform <platform>  Build platform (e.g., linux/amd64, linux/arm64)
      --no-cache             Build without using cache
      --skip-pull            Skip git pull (use current code)
  -h, --help                 Show this help message

Examples:
  $0 -d /www/compose/claude-code-hub
  $0 -d ~/Applications/claude-code-hub --platform linux/amd64
  $0 -d /www/compose/claude-code-hub --no-cache

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--deploy-dir)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option $1 requires an argument"
                    exit 1
                fi
                DEPLOY_DIR="$2"
                shift 2
                ;;
            -p|--platform)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "Option $1 requires an argument"
                    exit 1
                fi
                BUILD_PLATFORM="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --skip-pull)
                SKIP_PULL=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$DEPLOY_DIR" ]]; then
        log_error "Deployment directory is required. Use -d or --deploy-dir"
        echo ""
        show_help
        exit 1
    fi
}

check_deploy_dir() {
    if [[ ! -d "$DEPLOY_DIR" ]]; then
        log_error "Deployment directory does not exist: $DEPLOY_DIR"
        exit 1
    fi

    if [[ ! -f "$DEPLOY_DIR/docker-compose.yaml" ]]; then
        log_error "docker-compose.yaml not found in: $DEPLOY_DIR"
        exit 1
    fi

    log_success "Found deployment directory: $DEPLOY_DIR"
}

get_current_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir"
}

pull_latest_code() {
    if [[ "$SKIP_PULL" == true ]]; then
        log_info "Skipping git pull (--skip-pull flag set)"
        return
    fi

    local repo_dir
    repo_dir=$(get_current_dir)

    log_info "Pulling latest code from git..."
    cd "$repo_dir"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository: $repo_dir"
        exit 1
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "Current branch: $current_branch"

    git pull origin "$current_branch"
    log_success "Code updated successfully"
}

get_app_version() {
    local repo_dir
    repo_dir=$(get_current_dir)

    if [[ -f "$repo_dir/VERSION" ]]; then
        cat "$repo_dir/VERSION"
    else
        echo "dev"
    fi
}

build_docker_image() {
    local repo_dir
    repo_dir=$(get_current_dir)

    log_info "Building Docker image..."
    cd "$repo_dir"

    local app_version
    app_version=$(get_app_version)
    log_info "App version: $app_version"

    local build_args=(
        "-f" "deploy/Dockerfile"
        "-t" "claude-code-hub:local"
        "--build-arg" "APP_VERSION=$app_version"
    )

    if [[ -n "$BUILD_PLATFORM" ]]; then
        build_args+=("--platform" "$BUILD_PLATFORM")
        log_info "Building for platform: $BUILD_PLATFORM"
    fi

    if [[ "$NO_CACHE" == true ]]; then
        build_args+=("--no-cache")
        log_info "Building without cache"
    fi

    build_args+=(".")

    docker build "${build_args[@]}"
    log_success "Docker image built successfully: claude-code-hub:local"
}

update_compose_file() {
    log_info "Updating docker-compose.yaml to use local image..."
    cd "$DEPLOY_DIR"

    # Backup original compose file
    if [[ ! -f "docker-compose.yaml.backup" ]]; then
        cp docker-compose.yaml docker-compose.yaml.backup
        log_info "Created backup: docker-compose.yaml.backup"
    fi

    # Replace image reference
    sed -i.tmp 's|image: ghcr.io/ding113/claude-code-hub:.*|image: claude-code-hub:local|g' docker-compose.yaml
    rm -f docker-compose.yaml.tmp

    log_success "docker-compose.yaml updated to use local image"
}

restart_services() {
    log_info "Restarting Docker services..."
    cd "$DEPLOY_DIR"

    if docker compose version &> /dev/null; then
        docker compose down
        docker compose up -d
    else
        docker-compose down
        docker-compose up -d
    fi

    log_success "Services restarted"
}

wait_for_health() {
    log_info "Waiting for app service to become healthy (max 60 seconds)..."
    cd "$DEPLOY_DIR"

    local max_attempts=12
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        local app_container
        app_container=$(docker compose ps -q app 2>/dev/null || docker-compose ps -q app 2>/dev/null || echo "")

        if [[ -z "$app_container" ]]; then
            log_warning "App container not found"
            sleep 5
            continue
        fi

        local app_health
        app_health=$(docker inspect --format='{{.State.Health.Status}}' "$app_container" 2>/dev/null || echo "unknown")

        log_info "Health status - App: $app_health (attempt $attempt/$max_attempts)"

        if [[ "$app_health" == "healthy" ]]; then
            log_success "App service is healthy!"
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            sleep 5
        fi
    done

    log_warning "App service did not become healthy within 60 seconds"
    log_info "Check logs with: cd $DEPLOY_DIR && docker compose logs -f app"
    return 1
}

print_success_message() {
    echo ""
    echo -e "${GREEN}+================================================================+${NC}"
    echo -e "${GREEN}|                                                                |${NC}"
    echo -e "${GREEN}|          Claude Code Hub Updated Successfully!                |${NC}"
    echo -e "${GREEN}|                                                                |${NC}"
    echo -e "${GREEN}+================================================================+${NC}"
    echo ""
    echo -e "${BLUE}Deployment Directory:${NC}"
    echo -e "   $DEPLOY_DIR"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "   View logs:    ${YELLOW}cd $DEPLOY_DIR && docker compose logs -f app${NC}"
    echo -e "   Stop services: ${YELLOW}cd $DEPLOY_DIR && docker compose down${NC}"
    echo -e "   Restart:      ${YELLOW}cd $DEPLOY_DIR && docker compose restart app${NC}"
    echo ""
}

main() {
    parse_args "$@"

    echo -e "${BLUE}"
    echo "+=================================================================+"
    echo "|                                                                 |"
    echo "|           Claude Code Hub - Docker Update Script               |"
    echo "|                                                                 |"
    echo "+=================================================================+"
    echo -e "${NC}"

    check_deploy_dir
    pull_latest_code
    build_docker_image
    update_compose_file
    restart_services

    if wait_for_health; then
        print_success_message
    else
        log_warning "Update completed but app service may not be fully healthy yet"
        log_info "Please check the logs: cd $DEPLOY_DIR && docker compose logs -f app"
        print_success_message
    fi
}

main "$@"
