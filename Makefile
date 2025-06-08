# Список сервисов, у которых есть постоянные данные для очистки
SERVICES_WITH_DATA = grafana loki prometheus jaeger vector

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  OS_TYPE := Linux
  HOSTS_FILE := /etc/hosts
  FLUSH_DNS_CMD := sudo systemctl restart NetworkManager # или equivalent
else ifeq ($(UNAME_S),Darwin)
  OS_TYPE := Darwin # macOS
  HOSTS_FILE := /etc/hosts
  FLUSH_DNS_CMD := sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
else ifeq ($(OS),Windows_NT)
  OS_TYPE := Windows
  HOSTS_FILE := C:/Windows/System32/drivers/etc/hosts
  FLUSH_DNS_CMD := ipconfig /flushdns
else
  OS_TYPE := Unknown
  HOSTS_FILE := /etc/hosts # Default to Unix-like
  FLUSH_DNS_CMD := echo "Please consult your OS documentation to flush DNS cache."
endif


HOSTS_SERVICES = grafana jaeger loki otel-collector prometheus vector

validate-vector:
	@echo "Validating Vector configuration with Docker..."
	docker run --rm \
		--network=promgraph_monitoring \
		-v "$(PWD)/config/vector/vector.yaml:/etc/vector/vector.yaml:ro" \
		timberio/vector:0.47.0-alpine \
		validate /etc/vector/vector.yaml
	@echo "Vector configuration validated successfully."

# for debug purposes
full-reload-grafana:
	docker-compose stop grafana && docker-compose rm grafana -f && \
	rm -rf ./data/grafana && sleep 1 && docker-compose up -d grafana

# --- Основные цели (Targets) ---

# Запускает весь стек в фоновом режиме
up:
	@echo "🚀 Запускаем все сервисы..."
	@docker-compose up -d

# Останавливает и удаляет все контейнеры
down:
	@echo "🔥 Останавливаем и удаляем все сервисы..."
	@docker-compose down

# Показывает логи всех сервисов
logs:
	@echo "📄 Показываем логи..."
	@docker-compose logs -f --tail=100

# Показывает логи конкретного сервиса (например, make logs s=grafana)
logs-s:
	@echo "📄 Показываем логи для сервиса $(s)..."
	@docker-compose logs -f --tail=100 $(s)

# --- Цели для очистки данных ---

# Приватная "функция" для очистки данных одного сервиса
# Вызывается как $(call clean_service_data, <имя_сервиса>)
define clean_service_data
    @echo "🧹 Очищаем данные для сервиса: $1..."
    @if [ -d "./data/$1" ]; then \
        rm -rf ./data/$1/*; \
        echo "   -> Данные для $1 очищены."; \
    else \
        echo "   -> Директория ./data/$1 не найдена, пропускаем."; \
    fi
endef

# Цель для очистки данных Grafana
clean-grafana:
	$(call clean_service_data,grafana)

# Цель для очистки данных Loki
clean-loki:
	$(call clean_service_data,loki)

# Цель для очистки данных Prometheus
clean-prometheus:
	$(call clean_service_data,prometheus)

# Цель для очистки данных Jaeger
clean-jaeger:
	$(call clean_service_data,jaeger)

# Цель для очистки данных Vector
clean-vector:
	$(call clean_service_data,vector)

# ГЛАВНАЯ ЦЕЛЬ: очистить данные ВСЕХ сервисов
clean: down
	@echo "--- Начинаем полную очистку всех данных ---"
	@for service in $(SERVICES_WITH_DATA); do \
        $(call clean_service_data,$$service); \
    done
	@echo "--- Полная очистка завершена ---"

rebuild: clean
	@echo "♻️ Выполняем полный перезапуск с пересозданием образов..."
	@docker-compose up -d --build
	@echo "✅ Все сервисы перезапущены с чистого листа."

# Справка по командам
help:
	@echo "Доступные команды:"
	@echo "  make up          - Запустить все сервисы в фоновом режиме."
	@echo "  make down        - Остановить и удалить все контейнеры."
	@echo "  validate-vector  - Валидация конфига vector"
	@echo "  make logs        - Показать логи всех сервисов."
	@echo "  make logs-s s=<имя> - Показать логи конкретного сервиса (например, make logs-s s=loki)."
	@echo "  make clean       - Остановить стек и ОЧИСТИТЬ ВСЕ ДАННЫЕ."
	@echo "  make clean-grafana - Очистить данные только для Grafana."
	@echo "  make clean-loki    - Очистить данные только для Loki."
	@echo "  ... и так далее для prometheus, jaeger, vector."
	@echo "  make rebuild     - Полностью остановить стек, удалить все данные и перезапустить сервисы."


# Добавляет записи сервисов в файл hosts
add-hosts:
	@echo "Adding service entries to $(HOSTS_FILE)..."
	@for service in $(HOSTS_SERVICES); do \
		if ! grep -q "127.0.0.1 $${service}" $(HOSTS_FILE); then \
			echo "127.0.0.1 $${service}" | sudo tee -a $(HOSTS_FILE) > /dev/null; \
			echo "  -> Added $${service}"; \
		else \
			echo "  -> $${service} already exists, skipping."; \
		fi; \
	done

# Удаляет записи сервисов из файла hosts
remove-hosts:
	@echo "Removing service entries from $(HOSTS_FILE)..."
	@for service in $(HOSTS_SERVICES); do \
		if grep -q "127.0.0.1 $${service}" $(HOSTS_FILE); then \
			echo "  -> Removing $${service} from $(HOSTS_FILE)"; \
			sudo sh -c "awk -v SERVICE=\"$${service}\" '!( (\$1 == \"127.0.0.1\" && $$2 == SERVICE) ) { print }' $(HOSTS_FILE) > $(HOSTS_FILE).tmp && mv $(HOSTS_FILE).tmp $(HOSTS_FILE)"; \
		else \
			echo "  -> $${service} not found, skipping."; \
		fi; \
	done

.PHONY: up down logs logs-s clean clean-grafana clean-loki clean-prometheus clean-jaeger clean-vector help rebuild validate-vector add-hosts remove-hosts
