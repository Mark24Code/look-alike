.PHONY: build run dev clean install test help

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
NC     := \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Look-Alike Golang Server - Available Commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

build: ## Build the server executable
	@echo "$(GREEN)Building server...$(NC)"
	cd go-server && GOPROXY=https://goproxy.cn,direct go build -o ../look-alike-server ./cmd/server
	@echo "$(GREEN)Build complete: ./look-alike-server$(NC)"

run: build ## Build and run the server
	@echo "$(GREEN)Starting server...$(NC)"
	./look-alike-server

dev: ## Run server in development mode (no build)
	@echo "$(GREEN)Starting server in dev mode...$(NC)"
	cd go-server && GOPROXY=https://goproxy.cn,direct go run ./cmd/server

install: ## Install all dependencies (Go + client)
	@echo "$(GREEN)Installing Go dependencies...$(NC)"
	cd go-server && GOPROXY=https://goproxy.cn,direct go mod download
	@echo "$(GREEN)Installing client dependencies...$(NC)"
	cd client && npm install
	@echo "$(GREEN)Dependencies installed$(NC)"

install-go: ## Install only Go dependencies
	@echo "$(GREEN)Installing Go dependencies...$(NC)"
	cd go-server && GOPROXY=https://goproxy.cn,direct go mod download

install-client: ## Install only client dependencies
	@echo "$(GREEN)Installing client dependencies...$(NC)"
	cd client && npm install

build-client: ## Build client for production
	@echo "$(GREEN)Building client...$(NC)"
	cd client && npm run build
	@echo "$(GREEN)Client build complete: client/dist/$(NC)"

start-dev: ## Start both server and client in dev mode
	@echo "$(GREEN)Starting development mode...$(NC)"
	@echo "This will start both backend (4568) and frontend (5174)"
	@echo "Open http://localhost:5174 in your browser"
	@echo ""
	@echo "Backend: http://localhost:4568/api/health"
	@echo "Frontend: http://localhost:5174"
	@echo ""
	@echo "Press Ctrl+C to stop all services"
	@trap 'kill 0' EXIT; \
	(cd go-server && go run ./cmd/server) & \
	(cd client && npm run dev)

start-prod: build-client build ## Build and start in production mode
	@echo "$(GREEN)Starting production mode...$(NC)"
	@echo "Server will serve both API and frontend at http://localhost:4568"
	./look-alike-server

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning...$(NC)"
	rm -f look-alike-server
	rm -rf go-server/tmp
	rm -rf client/dist
	@echo "$(GREEN)Clean complete$(NC)"

test: ## Run tests
	@echo "$(GREEN)Running Go tests...$(NC)"
	cd go-server && go test ./...

fmt: ## Format Go code
	@echo "$(GREEN)Formatting Go code...$(NC)"
	cd go-server && go fmt ./...

lint: ## Lint Go code
	@echo "$(GREEN)Linting Go code...$(NC)"
	cd go-server && go vet ./...

tidy: ## Tidy Go modules
	@echo "$(GREEN)Tidying Go modules...$(NC)"
	cd go-server && go mod tidy

.DEFAULT_GOAL := help
