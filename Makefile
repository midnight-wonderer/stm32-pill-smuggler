#######################################
# MAKE CONFIGS
#######################################
BASE_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BASE_PATH := $(BASE_PATH:/=)

#######################################
# DEPENDED VARIABLES
#######################################
USE_HAL ?= 0

#######################################
# INPUT PATHS
#######################################
VENDOR_DIR ?= ./vendor
TOOL_EXCLUDES += $(BASE_PATH)
TOOL_EXCLUDE_FLAGS := $(foreach EXCLUDE,$(TOOL_EXCLUDES),-not -path "$(EXCLUDE)/*")
AS_INCLUDE_PATHS ?=
C_INCLUDE_PATHS += $(shell find $(BASE_PATH)/st-support -type f -name '*.h' -exec dirname {} \; | sort | uniq)
C_INCLUDE_PATHS += $(shell (find $(VENDOR_DIR) -maxdepth 3 -type f -name '*.h' -exec dirname {} \; 2>/dev/null) | sort | uniq)
C_INCLUDE_PATHS += $(shell (find . -maxdepth 3 -type f -name '*.h' $(TOOL_EXCLUDE_FLAGS) -exec dirname {} \; 2>/dev/null) | sort | uniq)
SUPPORT_SOURCES := $(shell cd $(BASE_PATH) && (find ./st-support -type f -name '*.c' -not -path "./st-support/hal/*" 2>/dev/null))
ifeq ($(USE_HAL), 1)
SUPPORT_SOURCES += $(shell cd $(BASE_PATH) && (find ./st-support/hal -type f -name '*.c' 2>/dev/null))
endif
APPLICATION_SOURCES = $(shell (find . -type f -name '*.c' $(TOOL_EXCLUDE_FLAGS) 2>/dev/null))
LDSCRIPT ?= $(BASE_PATH)/st-support/STM32F103C8Tx.ld
BOOT_SOURCE ?= $(BASE_PATH)/st-support/startup_stm32f103xb.s

#######################################
# OUTPUT PATHS
#######################################
BUILD_DIR ?= build
CACHE_DIR ?= $(BUILD_DIR)/cache
BOOT_OBJECT ?= boot.o
SUPPORT_OBJECTS = $(subst /./,/,$(addprefix $(CACHE_DIR)/, $(SUPPORT_SOURCES:.c=.o)))
APPLICATION_OBJECTS = $(subst /./,/,$(addprefix $(CACHE_DIR)/, $(APPLICATION_SOURCES:.c=.o)))

$(BUILD_DIR) $(CACHE_DIR):
	mkdir -p $@

#######################################
# BUILD TOOLS
#######################################
CROSS_PREFIX ?= arm-none-eabi-
ifdef GCC_PATH
CC = $(GCC_PATH)/$(CROSS_PREFIX)gcc
AS = $(GCC_PATH)/$(CROSS_PREFIX)as
AR = $(GCC_PATH)/$(CROSS_PREFIX)ar
LD = $(GCC_PATH)/$(CROSS_PREFIX)ld
CP = $(GCC_PATH)/$(CROSS_PREFIX)objcopy
SZ = $(GCC_PATH)/$(CROSS_PREFIX)size
else
CC = $(CROSS_PREFIX)gcc
AS = $(CROSS_PREFIX)as
AR = $(CROSS_PREFIX)ar
LD = $(CROSS_PREFIX)ld
CP = $(CROSS_PREFIX)objcopy
SZ = $(CROSS_PREFIX)size
endif
HEX = $(CP) -O ihex
BIN = $(CP) -O binary -S


#######################################
# TARGET
#######################################
DEBUG ?= 1
OPT ?= -Og
CPU ?= -mcpu=cortex-m3
MCU = $(CPU) -mthumb

#######################################
# CUSTOMIZATION
#######################################
AS_DEFS ?=
C_DEFS ?= \
-DSTM32F103xB
ifeq ($(USE_HAL), 1)
C_DEFS += -DUSE_HAL_DRIVER
endif
AS_INCLUDES = $(addprefix -I,$(AS_INCLUDE_PATHS))
C_INCLUDES = $(addprefix -I,$(C_INCLUDE_PATHS))
ASFLAGS ?= $(AS_DEFS) $(AS_INCLUDES)
CFLAGS = $(MCU) $(C_DEFS) $(C_INCLUDES) $(OPT) -Wall -fdata-sections -ffunction-sections
ifeq ($(DEBUG), 1)
CFLAGS += -g -gdwarf-2
endif
# Generate dependency information
CFLAGS += -MMD -MP -MF"$(@:%.o=%.d)"

# libraries
LIBS = -lc -lm -lnosys
LIBDIR += $(BUILD_DIR)
# LIBDIR += $(strip $(patsubst %/,%,$(shell echo $(lastword $(shell $(CC) -print-search-dirs | grep -E "^libraries:\s+")) | tr -s =: \ )))
LDFLAGS = $(MCU) -specs=nano.specs -T$(LDSCRIPT) $(addprefix -L,$(LIBDIR)) $(LIBS) -Wl,--gc-sections

#######################################
# BUILD COMPONENTS
#######################################

$(CACHE_DIR)/$(BOOT_OBJECT): $(BOOT_SOURCE) | $(CACHE_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(CACHE_DIR)/%.o: $(BASE_PATH)/%.c | $(CACHE_DIR)
	mkdir -p $(dir $@) && \
	$(CC) -c $(strip $(CFLAGS)) -Wa,-a,-ad,-alms=$(CACHE_DIR)/$(notdir $(<:.c=.lst)) $< -o $@

$(CACHE_DIR)/%.o: ./%.c | $(CACHE_DIR)
	mkdir -p $(dir $@) && \
	$(CC) -c $(strip $(CFLAGS)) -Wa,-a,-ad,-alms=$(@:.o=.lst) $< -o $@

$(BUILD_DIR)/libstsupport.a: $(SUPPORT_OBJECTS)
	$(AR) rcs $@ $^ 

$(BUILD_DIR)/libapplication.a: $(APPLICATION_OBJECTS)
	$(AR) rcs $@ $^ 

$(BUILD_DIR)/application.elf: $(CACHE_DIR)/$(BOOT_OBJECT) $(BUILD_DIR)/libstsupport.a $(BUILD_DIR)/libapplication.a | $(BUILD_DIR)
	$(CC) $< $(LDFLAGS) -Wl,-Map=$(@:.elf=.map),--cref $(foreach ARCHIVE,$(filter-out $<,$^),$(shell echo $(ARCHIVE) | sed -E 's/^.*lib([a-z]*)\.a$$/-l\1/')) -o $@
	$(SZ) $@

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(HEX) $< $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(BIN) $< $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf | $(BUILD_DIR)
	$(BIN) $< $@	

# echo $(shell $(CC) -print-search-dirs) &&

# test: $(CACHE_DIR)/$(BOOT_OBJECT) $(BUILD_DIR)/libstsupport.a $(BUILD_DIR)/libapplication.a | $(BUILD_DIR)
# 	echo $(shell echo "$(filter-out $<,$^)" | sed -E 's/^.*lib([a-z]*)\.a$$/-l\1/')

test:
	echo $(SUPPORT_SOURCES)
