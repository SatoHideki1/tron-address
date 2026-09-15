CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra -pthread
LDFLAGS ?= -pthread -lcrypto

# Auto-detect OpenSSL on macOS (Homebrew) or Linux (Debian/Ubuntu)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    OPENSSL_PREFIX ?= $(shell brew --prefix openssl@3 2>/dev/null || echo "/opt/homebrew/opt/openssl@3")
    CFLAGS += -I$(OPENSSL_PREFIX)/include
    LDFLAGS += -L$(OPENSSL_PREFIX)/lib
else
    # Linux (Debian/Ubuntu)
    CFLAGS += -march=native
endif

SRC_DIR = src
OBJ_DIR = obj
TARGET = tron-gen

SRCS = $(SRC_DIR)/main.c $(SRC_DIR)/tron.c $(SRC_DIR)/match.c
OBJS = $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRCS))

all: $(TARGET)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	@echo "=========================================="
	@echo "编译成功 (Build Success): $(TARGET)"
	@echo "=========================================="

clean:
	rm -rf $(OBJ_DIR) $(TARGET)

install: $(TARGET)
	install -d /usr/local/bin
	install -m 755 $(TARGET) /usr/local/bin/

.PHONY: all clean install
