-- tests/minimal_init.lua
-- 本番の init.lua を絶対にロードしない。テストに必要な最小限のみセットアップする。

-- plenary.nvim のパスを追加（nvim設定の .tests/ からシンボリックリンクか直接参照）
local plenary_path = vim.fn.expand("~/.config/nvim/.tests/plenary.nvim")
vim.opt.rtp:prepend(plenary_path)

-- プラグイン本体（lua/toc/ をrequireできるようにする）
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_root)

require("plenary")
