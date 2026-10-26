.PHONY: all test build build-companion build-android clean

all: test build

test:
	@echo "Running Companion Python unit tests..."
	@python3 companion/test_companion.py
	@echo "Running Flutter unit tests..."
	@cd codeflow_app && flutter test

build: build-companion build-android

build-companion:
	@echo "Building standalone companion executable..."
	@./scripts/build_companion.sh

build-android:
	@echo "Building Android release APK..."
	@./scripts/build_android.sh

clean:
	@rm -rf release companion/dist companion/build companion/release codeflow_app/build
