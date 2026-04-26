.PHONY: up
up:
	@if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then \
		echo "NVIDIA GPU detected, enabling GPU support..."; \
		docker compose -f docker-compose.yaml -f docker-compose.gpu.yaml up -d ollama open-webui ollama-init; \
	else \
		echo "No NVIDIA GPU detected, using CPU..."; \
		docker compose up -d ollama open-webui ollama-init; \
	fi

.PHONY: down
down:
	docker compose down


.PHONY: open-ui
open-ui:
	open http://localhost:$${WEBUI_PORT:-3000} 2>/dev/null || \
	  xdg-open http://localhost:$${WEBUI_PORT:-3000} 2>/dev/null || \
	  echo "Open http://localhost:$${WEBUI_PORT:-3000}"

.PHONY: exec-shell
exec-shell:
	docker compose --profile cli run --rm --entrypoint bash cli

.PHONY: list-models
list-models:
	docker exec ollama ollama list

.PHONY: model-pull
model-pull:
	docker exec ollama ollama pull $(if $(MODEL),$(MODEL),qwen2.5:7b)

.PHONY: chat
chat:
	@model="$(if $(MODEL),$(MODEL),qwen25:latest)"; \
	case "$$model" in \
		super-gemma) resolved_model="super-gemma:latest" ;; \
		llama4) resolved_model="llama4:latest" ;; \
		qwen25) resolved_model="qwen25:latest" ;; \
		qwen36) resolved_model="qwen36:latest" ;; \
		dark-champion) resolved_model="dark-champion:latest" ;; \
		*:*) resolved_model="$$model" ;; \
		*) resolved_model="$$model:latest" ;; \
	esac; \
	docker compose --profile cli run --rm \
		-e AIDER_MODEL="ollama_chat/$$resolved_model" \
		cli \
		--no-git \
		--no-auto-commits \
		--no-dirty-commits \
		--map-tokens 0

.PHONY: code
code:
	@model="$(if $(MODEL),$(MODEL),qwen25:latest)"; \
	case "$$model" in \
		super-gemma) resolved_model="super-gemma:latest" ;; \
		llama4) resolved_model="llama4:latest" ;; \
		qwen25) resolved_model="qwen25:latest" ;; \
		qwen36) resolved_model="qwen36:latest" ;; \
		dark-champion) resolved_model="dark-champion:latest" ;; \
		*:*) resolved_model="$$model" ;; \
		*) resolved_model="$$model:latest" ;; \
	esac; \
	docker compose --profile cli run --rm \
		-e AIDER_MODEL="ollama_chat/$$resolved_model" \
		cli \
		--no-auto-commits \
		--no-dirty-commits \
		$(ARGS)
