SHELL := /bin/sh

FLUTTER ?= flutter
BUILD_MODE ?= release
BUILD_ARGS ?=
DEV_ARGS ?=
ANDROID_ARGS ?=
ANDROID_OBFUSCATE ?= true
IOS_ARGS ?=
MACOS_ARGS ?=
WINDOWS_ARGS ?=
LINUX_ARGS ?=
WEB_ARGS ?=

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR := $(PROJECT_ROOT)/build
PACKAGE_DIR ?= $(BUILD_DIR)/packages
ANDROID_SYMBOLS_DIR ?= $(BUILD_DIR)/symbols/android
ANDROID_UNSIGNED_APK ?= $(PACKAGE_DIR)/recodex-$(APP_VERSION)-android-unsigned.apk
APP_VERSION ?= $(shell sed -n 's/^version:[[:space:]]*//p' "$(PROJECT_ROOT)/pubspec.yaml" | head -n 1 | cut -d+ -f1)
MACOS_APP_NAME ?= recodex
DMG_VOLUME_NAME ?= RecoDex
DMG_ARCH ?= $(shell uname -m)
DMG_NAME ?= recodex-$(APP_VERSION)-macos-$(DMG_ARCH).dmg
DMG_PATH := $(PACKAGE_DIR)/$(DMG_NAME)
DMG_STAGE := $(BUILD_DIR)/dmg-stage
MACOS_APP := $(BUILD_DIR)/macos/Build/Products/Release/$(MACOS_APP_NAME).app

UNAME_S := $(shell uname -s 2>/dev/null || echo unknown)
# Flutter prefers Android Studio's JDK even when JAVA_HOME is set. Pin the
# Gradle build JVM locally: Gradle 8.14's embedded Kotlin cannot parse Java 25.
# Prefer installed LTS JDKs on macOS; other hosts can use JAVA_HOME or an
# explicit ANDROID_GRADLE_JAVA_HOME. Do not change global Flutter settings.
ANDROID_GRADLE_JAVA_HOME ?= $(shell \
	if [ "$(UNAME_S)" = "Darwin" ] && [ -x /usr/libexec/java_home ]; then \
		/usr/libexec/java_home -F -v 21 2>/dev/null || \
		/usr/libexec/java_home -F -v 17 2>/dev/null || true; \
	else \
		printf '%s' "$$JAVA_HOME"; \
	fi)
# Quote once for the recipe shell and again for gradlew's JVM option parser,
# so a JDK path containing spaces remains one -D argument.
shell_quote = '$(subst ','"'"',$(1))'
android_gradle_env = $(if $(ANDROID_GRADLE_JAVA_HOME),GRADLE_OPTS=$(call shell_quote,$(GRADLE_OPTS) -Dorg.gradle.java.home=$(call shell_quote,$(ANDROID_GRADLE_JAVA_HOME))),)
ifeq ($(UNAME_S),Darwin)
DESKTOP_PLATFORM := macos
else ifeq ($(UNAME_S),Linux)
DESKTOP_PLATFORM := linux
else ifneq (,$(filter MINGW% MSYS% CYGWIN%,$(UNAME_S)))
DESKTOP_PLATFORM := windows
else ifeq ($(OS),Windows_NT)
DESKTOP_PLATFORM := windows
else
DESKTOP_PLATFORM :=
endif

.PHONY: all help deps check analyze test doctor devices dev build build-all package desktop \
	android android-jdk-check android-apk android-apk-unsigned android-appbundle apk apk-unsigned aab ios ipa macos windows linux web dmg \
	build-android build-ios build-macos build-windows build-linux build-web build-dmg clean

all: check build

help:
	@echo "RecoDex Flutter App"
	@echo ""
	@echo "开发与检查："
	@echo "  make dev                         启动当前系统的桌面调试版本"
	@echo "  make check                       运行静态分析和测试"
	@echo "  make doctor                      显示 Flutter 开发环境信息"
	@echo "  make clean                       清理 Flutter 构建产物"
	@echo ""
	@echo "桌面软件包："
	@echo "  make build                       编译当前系统的桌面 Release 版本"
	@echo "  make macos                       编译 macOS .app（仅 macOS）"
	@echo "  make dmg                         编译并封装 macOS DMG（仅 macOS）"
	@echo "  make windows                     编译 Windows Release（仅 Windows）"
	@echo "  make linux                       编译 Linux Release（仅 Linux）"
	@echo "  make build-all                   编译当前宿主支持的全部目标"
	@echo ""
	@echo "移动端与 Web 软件包："
	@echo "  make android                     同时编译 Android APK 和 AAB"
	@echo "  make apk                         编译签名并混淆的 Android APK"
	@echo "  make apk-unsigned                编译无需正式签名的 Android APK"
	@echo "  make aab                         编译签名并混淆的 Android App Bundle"
	@echo "  make ios                         编译 iOS IPA（仅 macOS，需签名配置）"
	@echo "  make web                         编译 Web Release"
	@echo ""
	@echo "可选变量：BUILD_MODE=release|profile|debug，以及 DEV_ARGS、BUILD_ARGS、"
	@echo "ANDROID_ARGS、IOS_ARGS、MACOS_ARGS、WINDOWS_ARGS、LINUX_ARGS、WEB_ARGS。"
	@echo "Android Dart 混淆默认启用；可用 ANDROID_OBFUSCATE=false 临时关闭。"
	@echo "Android Release 签名读取 android/key.properties 或 ANDROID_* 环境变量。"
	@echo "Android 构建在 macOS 自动选择 JDK 21/17；可用 ANDROID_GRADLE_JAVA_HOME 指定。"

deps:
	"$(FLUTTER)" pub get

analyze: deps
	"$(FLUTTER)" analyze

test: deps
	"$(FLUTTER)" test

check: analyze test

doctor:
	"$(FLUTTER)" doctor -v

devices:
	"$(FLUTTER)" devices

dev: deps
	@test -n "$(DESKTOP_PLATFORM)" || { echo "无法识别当前桌面平台：$(UNAME_S)"; exit 1; }
	@test -d "$(PROJECT_ROOT)/$(DESKTOP_PLATFORM)" || { \
		echo "项目尚未配置 $(DESKTOP_PLATFORM) 桌面平台。"; \
		echo "可执行 flutter create --platforms=$(DESKTOP_PLATFORM) . 后重试。"; \
		exit 1; \
	}
	"$(FLUTTER)" run -d "$(DESKTOP_PLATFORM)" $(DEV_ARGS)

build package desktop:
	@test -n "$(DESKTOP_PLATFORM)" || { echo "无法识别当前桌面平台：$(UNAME_S)"; exit 1; }
	@$(MAKE) --no-print-directory "$(DESKTOP_PLATFORM)"

# Portable targets can run on every host. Native targets are added only when
# this checkout contains the platform and the host can execute its toolchain.
BUILD_ALL_TARGETS := android web
ifneq ($(DESKTOP_PLATFORM),)
ifneq ($(wildcard $(PROJECT_ROOT)/$(DESKTOP_PLATFORM)),)
BUILD_ALL_TARGETS += $(DESKTOP_PLATFORM)
endif
endif
ifeq ($(DESKTOP_PLATFORM),macos)
BUILD_ALL_TARGETS += ios
endif

build-all: $(BUILD_ALL_TARGETS)

android: android-apk android-appbundle

android_obfuscation_args = $(if $(and $(filter release profile,$(BUILD_MODE)),$(filter true 1 yes,$(ANDROID_OBFUSCATE))),--obfuscate --split-debug-info="$(ANDROID_SYMBOLS_DIR)/$(1)")

android-jdk-check:
	@jdk_dir=$(call shell_quote,$(ANDROID_GRADLE_JAVA_HOME)); \
	if [ -z "$$jdk_dir" ]; then \
		if [ "$(UNAME_S)" = "Darwin" ]; then \
			echo "未找到 JDK 21/17。请安装后重试，或用 ANDROID_GRADLE_JAVA_HOME 指定 JDK 路径。"; exit 1; \
		fi; \
	else \
		test -x "$$jdk_dir/bin/java" && test -x "$$jdk_dir/bin/javac" || { echo "无效的 JDK 路径：$$jdk_dir"; exit 1; }; \
		jdk_major=$$("$$jdk_dir/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1); \
		case "$$jdk_major" in 17|18|19|20|21|22|23|24) ;; \
			*) echo "Gradle 8.14 不支持当前 JDK（$${jdk_major}），请用 ANDROID_GRADLE_JAVA_HOME 指定 JDK 21 或 17。"; exit 1 ;; \
		esac; \
		echo "Android Gradle 使用 JDK $${jdk_major}：$${jdk_dir}"; \
	fi

android-apk: android-jdk-check deps
	$(android_gradle_env) "$(FLUTTER)" build apk --$(BUILD_MODE) $(call android_obfuscation_args,apk) $(BUILD_ARGS) $(ANDROID_ARGS)

android-apk-unsigned: android-jdk-check deps
	$(android_gradle_env) ORG_GRADLE_PROJECT_allowUnsignedRelease=true "$(FLUTTER)" build apk --release $(call android_obfuscation_args,apk-unsigned) $(BUILD_ARGS) $(ANDROID_ARGS)
	@mkdir -p "$(PACKAGE_DIR)"
	@cp "$(BUILD_DIR)/app/outputs/flutter-apk/app-release.apk" "$(ANDROID_UNSIGNED_APK)"
	@echo "未签名 Android APK 已生成：$(ANDROID_UNSIGNED_APK)"

apk-unsigned: android-apk-unsigned

android-appbundle: android-jdk-check deps
	$(android_gradle_env) "$(FLUTTER)" build appbundle --$(BUILD_MODE) $(call android_obfuscation_args,aab) $(BUILD_ARGS) $(ANDROID_ARGS)

apk: android-apk

aab: android-appbundle

ios: deps
	@test "$(UNAME_S)" = "Darwin" || { echo "iOS IPA 只能在 macOS 上编译。"; exit 1; }
	"$(FLUTTER)" build ipa --$(BUILD_MODE) $(BUILD_ARGS) $(IOS_ARGS)

ipa: ios

macos: deps
	@test "$(UNAME_S)" = "Darwin" || { echo "macOS 软件只能在 macOS 上编译。"; exit 1; }
	"$(FLUTTER)" build macos --$(BUILD_MODE) $(BUILD_ARGS) $(MACOS_ARGS)

windows: deps
	@case "$(UNAME_S)" in MINGW*|MSYS*|CYGWIN*) ;; *) \
		if [ "$(OS)" != "Windows_NT" ]; then echo "Windows 软件只能在 Windows 上编译。"; exit 1; fi ;; \
		esac
	"$(FLUTTER)" build windows --$(BUILD_MODE) $(BUILD_ARGS) $(WINDOWS_ARGS)

linux: deps
	@test "$(UNAME_S)" = "Linux" || { echo "Linux 软件只能在 Linux 上编译。"; exit 1; }
	@test -d "$(PROJECT_ROOT)/linux" || { echo "项目尚未配置 Linux 桌面平台。"; exit 1; }
	"$(FLUTTER)" build linux --$(BUILD_MODE) $(BUILD_ARGS) $(LINUX_ARGS)

web: deps
	"$(FLUTTER)" build web --$(BUILD_MODE) $(BUILD_ARGS) $(WEB_ARGS)

build-android: android

build-ios: ios

build-macos: macos

build-windows: windows

build-linux: linux

build-web: web

build-dmg: dmg

dmg: override BUILD_MODE := release
dmg: macos
	@command -v hdiutil >/dev/null 2>&1 || { echo "缺少 macOS hdiutil，无法创建 DMG。"; exit 1; }
	@test -d "$(MACOS_APP)" || { echo "找不到 macOS App：$(MACOS_APP)"; exit 1; }
	@rm -rf "$(DMG_STAGE)"
	@mkdir -p "$(DMG_STAGE)" "$(PACKAGE_DIR)"
	@ditto "$(MACOS_APP)" "$(DMG_STAGE)/$(MACOS_APP_NAME).app"
	@ln -s /Applications "$(DMG_STAGE)/Applications"
	hdiutil create -volname "$(DMG_VOLUME_NAME)" -srcfolder "$(DMG_STAGE)" -ov -format UDZO "$(DMG_PATH)"
	@rm -rf "$(DMG_STAGE)"
	@echo "DMG 已生成：$(DMG_PATH)"

clean:
	"$(FLUTTER)" clean
	@rm -rf "$(PACKAGE_DIR)" "$(DMG_STAGE)"
