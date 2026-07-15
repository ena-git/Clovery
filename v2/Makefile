SHELL := /bin/sh

FLUTTER ?= flutter
GO ?= go
FLUTTER_BIN := $(shell command -v $(FLUTTER))
DART ?= $(dir $(FLUTTER_BIN))cache/dart-sdk/bin/dart
DATABASE_URL ?= postgres://clovery:clovery_dev_only@localhost:5432/clovery?sslmode=disable

.PHONY: generate verify verify-api verify-contract verify-generated verify-infra verify-migrations verify-mobile verify-release verify-staging

generate:
	cd apps/mobile && $(DART) run pigeon --input pigeons/clovery_platform.dart
	cd apps/mobile && $(DART) format lib/core/platform/generated/clovery_platform.g.dart

verify-api:
	cd services/api && DATABASE_URL='$(DATABASE_URL)' $(GO) test ./...

verify-contract:
	cd services/api && $(GO) test ./internal/contract

verify-infra: verify-staging
	docker compose -f infra/compose.yaml config --quiet

verify-staging:
	sh -n scripts/staging-*.sh scripts/lib/staging-*.sh scripts/test-staging-*.sh scripts/testlib/staging-fixture.sh
	./scripts/test-staging-configuration.sh
	./scripts/test-staging-data-safety.sh
	./scripts/test-staging-smoke-evidence.sh

verify-migrations:
	cd services/api && DATABASE_URL='$(DATABASE_URL)' $(GO) test -count=1 ./internal/database

verify-mobile:
	cd apps/mobile && $(FLUTTER) pub get --enforce-lockfile
	$(MAKE) generate
	cd apps/mobile && $(DART) format --output=none --set-exit-if-changed lib/app.dart lib/main.dart lib/core/config test pigeons
	cd apps/mobile && $(FLUTTER) analyze
	cd apps/mobile && $(FLUTTER) test

verify-generated: verify-mobile
	git diff --exit-code -- apps/mobile/lib/core/platform/generated apps/mobile/ios/Runner/CloveryPlatform.g.swift apps/mobile/android/app/src/main/kotlin/com/clovery/app/CloveryPlatform.g.kt

verify-release:
	./scripts/verify-release-identities.sh

verify: verify-infra verify-release verify-contract verify-api verify-migrations verify-generated
