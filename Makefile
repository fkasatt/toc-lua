NVIM     := nvim
TEST_DIR := tests
INIT     := $(TEST_DIR)/minimal_init.lua

.PHONY: test test-file

## 全テストを実行
test:
	$(NVIM) --headless -u $(INIT) \
	  -c "PlenaryBustedDirectory $(TEST_DIR)/ { minimal_init = '$(INIT)', sequential = true }" \
	  -c "qa!"

## 単一ファイルを実行: make test-file FILE=tests/toc_spec.lua
test-file:
	$(NVIM) --headless -u $(INIT) \
	  -c "PlenaryBustedFile $(FILE)" \
	  -c "qa!"
