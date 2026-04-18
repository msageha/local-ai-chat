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
