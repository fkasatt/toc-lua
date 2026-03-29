-- layout.lua
-- ToC ウィンドウ群（タイトル・本体・棒グラフ）のレイアウトを構築する。

local session = require("toc.session")
local util = require("toc.util")
local config = require("toc.config")

local M = {}

--- ToC バッファ・ウィンドウ、およびタイトルバッファ・ウィンドウを作成する
--- 端末幅に余裕がある場合は縦分割（vsplit）、ない場合は横分割（split）を使う
---@param opts table {width?: integer}
---@param entry_count integer
function M.create_toc_layout(opts, entry_count)
	local S = session.get()
	local cfg = config.options

	S.toc_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[S.toc_buf].buftype = "nofile"
	vim.bo[S.toc_buf].filetype = "toc"
	vim.bo[S.toc_buf].modifiable = false

	local cols = vim.o.columns
	local available = cols - cfg.src_min_width
	if available >= 20 then
		local width
		if opts.width then
			width = math.max(20, math.min(opts.width, available))
		else
			width = math.min(cfg.toc_max_width, available)
		end
		vim.cmd("botright vsplit")
		S.toc_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(S.toc_win, S.toc_buf)
		vim.api.nvim_win_set_width(S.toc_win, width)
	else
		vim.cmd("botright split")
		S.toc_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(S.toc_win, S.toc_buf)
		vim.api.nvim_win_set_height(S.toc_win, math.min(entry_count + 1, math.floor(vim.o.lines * 0.4)))
	end

	util.setup_win_opts(S.toc_win)
	vim.wo[S.toc_win].cursorline = true
	vim.wo[S.toc_win].winfixwidth = true
	local initial = vim.api.nvim_win_get_width(S.toc_win)
	S.toc_width = initial
	S.toc_initial_width = initial

	-- タイトルバッファを toc_win の上に 1 行ウィンドウとして作成する
	S.title_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[S.title_buf].buftype = "nofile"
	vim.bo[S.title_buf].modifiable = false

	vim.api.nvim_set_current_win(S.toc_win)
	vim.cmd("aboveleft split")
	S.title_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(S.title_win, S.title_buf)
	vim.api.nvim_win_set_height(S.title_win, 1)

	util.setup_win_opts(S.title_win)
	vim.wo[S.title_win].winfixheight = true
	vim.wo[S.title_win].winfixwidth = true
end

--- 棒グラフバッファ・ウィンドウを toc_win の下に作成する
---
--- 棒グラフを表示する条件:
---   1. ターミナルウィンドウの高さが 32 行以上であること
---      （短い端末では棒グラフのスペースが確保できないため）
---   2. ToCウィンドウ幅が toc_max_width - 2 以上であること
---      （狭すぎるとグラフが潰れて読めないため）
---
--- bar_height の自動計算:
---   ターミナル行数の 20% を棒グラフに割り当て、最小 5 行・最大 16 行とする。
---   S.bar_height に格納し、+ / - キーで実行中に変更できる。
function M.create_chart_layout()
	local S = session.get()
	local cfg = config.options

	local win_width = vim.api.nvim_win_get_width(S.toc_win)
	-- 条件1: ターミナル高さ 32 行未満では表示しない
	-- 条件2: ToC 幅が不足していれば表示しない
	if vim.o.lines < 32 or win_width < cfg.toc_max_width - 2 then
		return
	end

	-- ターミナル高さに応じて bar_height を自動計算する（未設定時のみ）
	-- ターミナル行数の 20% を割り当て、最小 5・最大 16 行に収める
	if not S.bar_height then
		S.bar_height = math.max(5, math.min(16, math.floor(vim.o.lines * 0.2)))
	end
	local chart_win_height = S.bar_height + 2 -- bar 行 + ラベル行 + パーセント行

	S.chart_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[S.chart_buf].buftype = "nofile"
	vim.bo[S.chart_buf].modifiable = false

	vim.api.nvim_set_current_win(S.toc_win)
	vim.cmd("belowright split")
	S.chart_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(S.chart_win, S.chart_buf)
	vim.api.nvim_win_set_height(S.chart_win, chart_win_height)

	util.setup_win_opts(S.chart_win)
	vim.wo[S.chart_win].cursorline = false
	vim.wo[S.chart_win].winfixheight = true
end

return M
