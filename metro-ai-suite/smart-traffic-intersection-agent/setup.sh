#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verifiying intersection config file and setting project name based on intersection name defined in config
INTERSECTION_CONFIG_FILE="$APP_DIR/intersection-config.json"
if [ ! -f "$INTERSECTION_CONFIG_FILE" ]; then
    echo -e "${RED}Intersection configuration file not found: $INTERSECTION_CONFIG_FILE${NC}"
    return 1
fi
export INTERSECTION_NAME=$(grep -oP '"intersection-name"\s*:\s*"\K[^"]+' "$INTERSECTION_CONFIG_FILE")
PROJECT_NAME=${INTERSECTION_NAME:-trafficagent}

# Setting command usage and invalid arguments handling before the actual setup starts
if [ "$#" -eq 0 ] || ([ "$#" -eq 1 ] && [ "$1" = "--help" ]); then
    # If no valid argument is passed, print usage information
    echo -e "-----------------------------------------------------------------"
    echo -e "${YELLOW}USAGE: ${GREEN}source setup.sh ${BLUE}[--setenv | --run | --setup | --restart [agent|prerequisite] | --stop | --clean | --help]"
    echo -e "${YELLOW}"
    echo -e "  --setenv:                Set environment variables without starting any containers"
    echo -e "  --run:                   Start the services"
    echo -e "  --setup:                 Build and run the services (first time setup)"
    echo -e "  --restart [service]:     Restart services with updated environment variables"
    echo -e "                           • agent         - Restart only Smart-Traffic-Intersection-Agent services"
    echo -e "                           • prerequisite  - Restart only prerequisite services (edge-ai-suites)"
    echo -e "                           • (no argument) - Restart all services"
    echo -e "  --stop:                  Stop the services"
    echo -e "  --clean:                 Clean up containers, volumes, and logs"
    echo -e "  --help:                  Show this help message${NC}"
    echo -e "-----------------------------------------------------------------"
    return 0

elif [ "$#" -gt 2 ]; then
    echo -e "${RED}ERROR: Too many arguments provided.${NC}"
    echo -e "${YELLOW}Use --help for usage information${NC}"
    return 1

elif [ "$1" != "--help" ] && [ "$1" != "--setenv" ] && [ "$1" != "--run" ] && [ "$1" != "--setup" ] && [ "$1" != "--restart" ] && [ "$1" != "--stop" ] && [ "$1" != "--clean" ]; then
    # Default case for unrecognized option
    echo -e "${RED}Unknown option: $1 ${NC}"
    echo -e "${YELLOW}Use --help for usage information${NC}"
    return 1

elif [ "$1" = "--restart" ] && [ "$#" -eq 2 ] && [ "$2" != "agent" ] && [ "$2" != "prerequisite" ]; then
    echo -e "${RED}ERROR: Invalid restart argument: $2${NC}"
    echo -e "${YELLOW}Valid options: agent, prerequisite${NC}"
    echo -e "${YELLOW}Use --help for usage information${NC}"
    return 1

elif [ "$1" = "--stop" ] || [ "$1" = "--clean" ]; then
    echo -e "${YELLOW}Stopping Smart-Traffic-Intersection-Agent... ${NC}"
    
    # check if ri-compose.yaml exists and run docker compose down accordingly
    if [ -L "docker/ri-compose.yaml" ]; then
        docker compose -f docker/ri-compose.yaml -f docker/agent-compose.yaml -p ${PROJECT_NAME} down 2> /dev/null
    else
        docker compose -f docker/agent-compose.yaml -p ${PROJECT_NAME} down 2> /dev/null
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to stop Smart-Traffic-Intersection-Agent services. ${NC}"
        return 1
    fi
    echo -e "${GREEN}All containers for Smart-Traffic-Intersection-Agent stopped and removed! ${NC}"

    if [ "$1" = "--clean" ]; then
        echo -e "${YELLOW}Removing volumes for Smart-Traffic-Intersection-Agent ... ${NC}"
        docker volume ls | grep $PROJECT_NAME | awk '{ print $2 }' | xargs docker volume rm 2>/dev/null || true
        echo -e "${GREEN}Docker cleanup completed successfully. ${NC}"
    fi

    return 0
fi

# ============================================================================
# PREREQUISITES: Setup edge-ai-suites before running the application
# ============================================================================

# Set application-specific environment variables
export SAMPLE_APP="smart-intersection"
export APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOST_IP=$(ip route get 1 2>/dev/null | awk '{print $7}')
if [ -z "$HOST_IP" ]; then
    export HOST_IP="localhost"
fi

SUBMODULE="deps/metro-vision"
SUBMODULE_PATH="$APP_DIR/$SUBMODULE"
export DEPS_DIR="$SUBMODULE_PATH/metro-ai-suite/metro-vision-ai-app-recipe"
export RI_DIR="$DEPS_DIR/$SAMPLE_APP"

# Function to check if prerequisites are met
check_and_setup_prerequisites() {
    echo -e "${BLUE}==> Setting up required submodules ...${NC}"

    if [ ! -d "$DEPS_DIR" ]; then
        # Run git submodule init and update to fetch the dependencies
        echo -e "${YELLOW}Dependencies not found. Initializing and updating git submodules...${NC}"
        git -C $APP_DIR submodule update --init --depth 1 $SUBMODULE
        git -C $SUBMODULE_PATH sparse-checkout init --cone
        git -C $SUBMODULE_PATH sparse-checkout set metro-ai-suite/metro-vision-ai-app-recipe

        # Verify if the git commands were successful
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to initialize and update dependencies${NC}"
            return 1
        fi
    fi

    # Check if install.sh exists
    if [ ! -f "$RI_DIR/install.sh" ]; then
        echo -e "${RED}Installation script not found for dependency : $SAMPLE_APP ${NC}"
        return 1
    fi
    
    # Run the installation script
    echo -e "${BLUE}==> Running installation script for smart-intersection...${NC}"
    cd $RI_DIR && ./install.sh $HOST_IP && cd - > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to run install.sh for smart-intersection${NC}"
        cd - > /dev/null
        return 1
    fi
    echo -e "${GREEN}Installation script completed successfully${NC}"

    # Create symbolic link to compose-scenescape.yml in docker dir of agent application
    rm "$APP_DIR/docker/ri-compose.yaml" 2> /dev/null 
    ln -sf "$DEPS_DIR/compose-scenescape.yml" "$APP_DIR/docker/ri-compose.yaml"
    
    return 0
}

# Run prerequisites check and setup (skip if only shopwing help or setting envs)
if [ "$1" != "--help" ] && [ "$1" != "--setenv" ] && [ "$1" != "--clean" ] && [ "$1" != "--stop" ]; then
    check_and_setup_prerequisites
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to setup prerequisites. Please check the errors above.${NC}"
        return 1
    fi
fi

# ============================================================================
# END PREREQUISITES
# ============================================================================

# Export required environment variables (HOST_IP already set above)
export TAG=${TAG:-latest}
export REGISTRY=${REGISTRY:-}

# Smart-Traffic-Intersection-Agent Configuration
export APP_BACKEND_PORT=${TRAFFIC_AGENT_BACKEND_PORT:-8081}
export APP_UI_PORT=${TRAFFIC_AGENT_UI_PORT:-7860}
export REFRESH_INTERVAL=${REFRESH_INTERVAL:-15}

# User and group IDs for containers
export USER_GROUP_ID=$(id -g)
export VIDEO_GROUP_ID=$(getent group video | awk -F: '{printf "%s\n", $3}' 2>/dev/null || echo "44")
export RENDER_GROUP_ID=$(getent group render | awk -F: '{printf "%s\n", $3}' 2>/dev/null || echo "109")

# Traffic Analysis Configuration
export TRAFFIC_BUFFER_DURATION=${TRAFFIC_BUFFER_DURATION:-60}
export LOG_LEVEL=${LOG_LEVEL:-INFO}
export DATA_RETENTION_HOURS=${DATA_RETENTION_HOURS:-24}

# VLM Service Configuration
export VLM_SERVICE_PORT=${VLM_SERVICE_PORT:-9764}
export VLM_MODEL_NAME=${VLM_MODEL_NAME:-microsoft/Phi-3.5-vision-instruct}
export VLM_TIMEOUT_SECONDS=${VLM_TIMEOUT_SECONDS:-300}
export VLM_MAX_COMPLETION_TOKENS=${VLM_MAX_COMPLETION_TOKENS:-1500}
export VLM_TEMPERATURE=${VLM_TEMPERATURE:-0.1}
export VLM_TOP_P=${VLM_TOP_P:-0.1}

# VLM OpenVINO Configuration
export VLM_DEVICE=${VLM_DEVICE:-CPU}
export VLM_COMPRESSION_WEIGHT_FORMAT=${VLM_COMPRESSION_WEIGHT_FORMAT:-int8}
export VLM_SEED=${VLM_SEED:-42}
export VLM_WORKERS=${VLM_WORKERS:-1}
export VLM_LOG_LEVEL=${VLM_LOG_LEVEL:-info}
export VLM_ACCESS_LOG_FILE=${VLM_ACCESS_LOG_FILE:-/dev/null}

# Automatically adjust VLM settings for GPU
if [[ "$VLM_DEVICE" == "GPU" ]]; then
    export VLM_COMPRESSION_WEIGHT_FORMAT=int4
    export VLM_WORKERS=1  # GPU works best with single worker
fi

# Health Check Configuration
export HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30s}
export HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10s}
export HEALTH_CHECK_RETRIES=${HEALTH_CHECK_RETRIES:-3}
export HEALTH_CHECK_START_PERIOD=${HEALTH_CHECK_START_PERIOD:-10s}

# Proxy settings
export no_proxy_env=${no_proxy}

# Function to build and start the services
build_and_start_service() {
    echo -e "${BLUE}==> Starting Smart-Traffic-Intersection-Agent ...${NC}"

    # set intersection-specific environment variables based on intersection-config.json 
    export INTERSECTION_LATITUDE=$(grep -oP '"latitude"\s*:\s*\K-?[\d.]+(?=,|$)' "$INTERSECTION_CONFIG_FILE")
    export INTERSECTION_LONGITUDE=$(grep -oP '"longitude"\s*:\s*\K-?[\d.]+' "$INTERSECTION_CONFIG_FILE")
    export APP_BACKEND_PORT=$(grep -oP '"backend_port"\s*:\s*\K\d+' "$INTERSECTION_CONFIG_FILE")
    export APP_UI_PORT=$(grep -oP '"ui_port"\s*:\s*\K\d+' "$INTERSECTION_CONFIG_FILE")

    if [ "$APP_BACKEND_PORT" = "" ] || [ "$APP_UI_PORT" = "" ]; then
        unset APP_BACKEND_PORT
        unset APP_UI_PORT
    fi    

    # Build and start the services
    docker compose --project-directory $DEPS_DIR -f docker/ri-compose.yaml -f docker/agent-compose.yaml -p $PROJECT_NAME up -d --build 2>&1 1>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Smart-Traffic-Intersection-Agent Services built and started successfully!${NC}"
    else
        echo -e "${RED}Failed to build and start Smart-Traffic-Intersection-Agent Services${NC}"
        return 1
    fi
}

# Function to start the services
start_service() {
    echo -e "${BLUE}==> Starting Smart-Traffic-Intersection-Agent Services...${NC}"
    
    # Start the services
    docker compose --project-directory $DEPS_DIR -f docker/ri-compose.yaml -f docker/agent-compose.yaml -p $PROJECT_NAME up -d 2>&1 1>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Smart-Traffic-Intersection-Agent Services started successfully!${NC}"
    else
        echo -e "${RED}Failed to start Smart-Traffic-Intersection-Agent Services${NC}"
        return 1
    fi
}

# Function to restart the services (for env var changes)
restart_service() {
    local SERVICE_TYPE="${1:-all}"
    
    case "$SERVICE_TYPE" in
        agent)
            echo -e "${BLUE}==> Restarting Smart-Traffic-Intersection-Agent Services with updated environment variables...${NC}"
            
            # Stop the Smart-Traffic-Intersection-Agent services
            docker compose -f docker/agent-compose.yaml down
            
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to stop Smart-Traffic-Intersection-Agent services${NC}"
                return 1
            fi
            
            # Start with force-recreate to ensure env vars are picked up
            docker compose -f docker/agent-compose.yaml -p $PROJECT_NAME up -d --force-recreate
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Smart-Traffic-Intersection-Agent Services restarted successfully with updated configuration!${NC}"
            else
                echo -e "${RED}Failed to restart Smart-Traffic-Intersection-Agent Services${NC}"
                return 1
            fi
            ;;
            
        prerequisite)
            #TODO update this case implementation based on new submodule structure
            echo -e "${BLUE}==> Restarting Prerequisite Services (edge-ai-suites)...${NC}"
            
            local METRO_DIR="edge-ai-suites/metro-ai-suite/metro-vision-ai-app-recipe"
            
            if [ ! -d "$METRO_DIR" ]; then
                echo -e "${RED}Directory $METRO_DIR not found${NC}"
                echo -e "${YELLOW}Please run 'source setup.sh --setup' first to set up prerequisites${NC}"
                return 1
            fi
            
            cd "$METRO_DIR"
            
            # Stop the prerequisite services
            echo -e "${BLUE}==> Stopping prerequisite services...${NC}"
            docker compose down
            
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to stop prerequisite services${NC}"
                cd - > /dev/null
                return 1
            fi
            
            # Start with force-recreate to ensure env vars are picked up
            echo -e "${BLUE}==> Starting prerequisite services with updated configuration...${NC}"
            docker compose up -d --force-recreate
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Prerequisite Services restarted successfully with updated configuration!${NC}"
                
                echo ""
                echo -e "${BLUE}Edge AI Suites Services:${NC}"
                echo -e "  • SceneScape Web UI: ${YELLOW}https://${HOST_IP}:443${NC}"
                echo -e "  • DLStreamer Pipeline Server API: ${YELLOW}http://${HOST_IP}:8080${NC}"
                echo -e "  • InfluxDB UI: ${YELLOW}http://${HOST_IP}:8086${NC}"
                echo -e "  • Grafana Dashboard: ${YELLOW}http://${HOST_IP}:3000${NC}"
                echo -e "  • Node-RED UI: ${YELLOW}http://${HOST_IP}:1880${NC}"
                echo ""
            else
                echo -e "${RED}Failed to restart Prerequisite Services${NC}"
                cd - > /dev/null
                return 1
            fi
            
            cd - > /dev/null
            ;;
            
        all)
            #TODO update based on new submodule structure
            echo -e "${BLUE}==> Restarting All Services with updated environment variables...${NC}"
            
            # Restart prerequisite services first
            local METRO_DIR="edge-ai-suites/metro-ai-suite/metro-vision-ai-app-recipe"
            
            if [ -d "$METRO_DIR" ]; then
                cd "$METRO_DIR"
                
                echo -e "${BLUE}==> Restarting prerequisite services...${NC}"
                docker compose down
                docker compose up -d --force-recreate
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Prerequisite Services restarted successfully!${NC}"
                else
                    echo -e "${RED}Failed to restart Prerequisite Services${NC}"
                    cd - > /dev/null
                    return 1
                fi
                
                cd - > /dev/null
            else
                echo -e "${YELLOW}Prerequisite services directory not found, skipping...${NC}"
            fi
            
            # Restart Smart-Traffic-Intersection-Agent services
            echo -e "${BLUE}==> Restarting Smart-Traffic-Intersection-Agent Services...${NC}"
            docker compose -f docker/compose.yaml down
            docker compose -f docker/compose.yaml up -d --force-recreate
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}All services restarted successfully with updated configuration!${NC}"
                
                echo ""
                echo -e "${BLUE}Edge AI Suites Services:${NC}"
                echo -e "  • SceneScape Web UI: ${YELLOW}https://${HOST_IP}:443${NC}"
                echo -e "  • DLStreamer Pipeline Server API: ${YELLOW}http://${HOST_IP}:8080${NC}"
                echo -e "  • InfluxDB UI: ${YELLOW}http://${HOST_IP}:8086${NC}"
                echo -e "  • Grafana Dashboard: ${YELLOW}http://${HOST_IP}:3000${NC}"
                echo -e "  • Node-RED UI: ${YELLOW}http://${HOST_IP}:1880${NC}"
                echo ""
                echo -e "${BLUE}Smart-Traffic-Intersection-Agent Services:${NC}"
                echo -e "  • Backend API: ${YELLOW}http://${HOST_IP}:${APP_BACKEND_PORT}${NC}"
                echo -e "  • UI: ${YELLOW}http://${HOST_IP}:${APP_UI_PORT}${NC}"
                echo -e "  • VLM Service: ${YELLOW}http://${HOST_IP}:${VLM_SERVICE_PORT}${NC}"
                echo ""
            else
                echo -e "${RED}Failed to restart Smart-Traffic-Intersection-Agent Services${NC}"
                return 1
            fi
            ;;
    esac
}

# if only base environment variables are to be set without deploying application, exit here
if [ "$1" = "--setenv" ]; then
    echo -e "${BLUE}Done setting up all environment variables. ${NC}"
    return 0
fi

# Main logic based on command
case $1 in
    --setup)
        build_and_start_service
        ;;
    --restart)
        restart_service "$2"
        ;;
    --run|*)
        start_service
        ;;
esac

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${RED}Setup failed. Check the logs above for details.${NC}"
    return 1
fi
