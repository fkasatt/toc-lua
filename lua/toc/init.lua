-- init.lua
-- プラグインの公開 API。外部から呼ぶのはこのモジュールのみ。
--
--   require("toc").setup(opts)  -- 設定オーバーライド（省略時はデフォルト値を使用）
--   require("toc").open(opts)   -- ToC を開く（既に開いていれば ToC ウィンドウにフォーカス）

local M = {}

--- ユーザー設定を適用する
--- setup() を呼ばなくてもデフォルト設定で動作する
---@param opts table|nil
---   - toc_max_width  (integer) ToCウィンドウの最大列幅（デフォルト: 50）
---   - src_min_width  (integer) ソースウィンドウの最小列幅（デフォルト: 50）
---   - bar_height     (integer) 棒グラフの最大高さ（デフォルト: 15）
---   - chart_win_height (integer) 棒グラフウィンドウの高さ（デフォルト: 16）
---   - bar_col_width  (integer) 棒グラフ1本の列幅（デフォルト: 3）
function M.setup(opts)
	require("toc.config").setup(opts)
end

--- ToC ウィンドウを開く
--- 同一ルートバッファのセッションが既に有効な場合は ToC ウィンドウにフォーカスするだけ
---@param opts table|nil
---   - width (integer) ToC 列の初期幅（省略時は toc_max_width に従う）
function M.open(opts)
	opts = opts or {}

	local session = require("toc.session")
	local config = require("toc.config")
	local highlight = require("toc.highlight")
	local parser = require("toc.parser")
	local layout = require("toc.layout")
	local keymaps = require("toc.keymaps")
	local autocmds = require("toc.autocmds")
	local util = require("toc.util")

	session.ensure_init()
	highlight.setup()

	local src_buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo[src_buf].filetype
	util.log(string.format("M.open: buf=%d ft=%s", src_buf, ft))
	local marker = config.heading_markers[ft]

	if not marker then
		vim.notify(
			"ToC: このファイルタイプには対応していません（markdown/typst/txt）",
			vim.log.levels.WARN
		)
		return
	end

	-- 子ファイルから開いた場合、記憶済みのルートバッファを使用する
	local root_buf = src_buf
	local include_to_root = session.get_include_to_root()
	local remembered = include_to_root[src_buf]
	if remembered and vim.api.nvim_buf_is_valid(remembered) then
		root_buf = remembered
	end

	local entries, inc_bufs = parser.build_all_entries(root_buf, marker, ft)

	if #entries == 0 then
		vim.notify("ToC: ヘッダーが見つかりません", vim.log.levels.INFO)
		return
	end

	-- インクルードマッピングを登録する（セッションを跨いで保持）
	for b, _ in pairs(inc_bufs) do
		include_to_root[b] = root_buf
	end

	-- 既存セッションが同一ルートバッファで有効ならフォーカスのみ
	local S = session.get()
	if S and S.root_buf == root_buf and S.toc_win and vim.api.nvim_win_is_valid(S.toc_win) then
		vim.api.nvim_set_current_win(S.toc_win)
		return
	end
	if S then
		session.close()
	end

	local src_win = vim.api.nvim_get_current_win()

	session.set({
		root_buf = root_buf, -- ルートファイル（include 解決済み、不変）
		src_buf = src_buf, -- ソースウィンドウに表示中のバッファ（カーソル移動で変わる）
		src_win = src_win, -- ソース表示ウィンドウ（固定追跡）
		included_bufs = inc_bufs, -- インクルード済みバッファ集合
		ft = ft,
		marker = marker,
		entries = entries,
		toc_buf = nil,
		toc_win = nil,
		title_buf = nil,
		title_win = nil,
		chart_buf = nil,
		chart_win = nil,
		entry_to_bar = {},
		bar_entries = {},
		chart_hls = {},
		total_bars = 0,
		pad_win = nil,
		pad_buf = nil,
		needs_hscroll = false,
		toc_width = 0, -- @ キーで管理する希望幅（0 = 未初期化）
	})

	layout.create_toc_layout(opts, #entries)
	session.refresh_toc()

	layout.create_chart_layout()
	if session.get().chart_buf then
		session.refresh_chart()
		session.get().needs_hscroll = session.get().total_bars >= 30
	end

	session.adjust_toc_width()
	keymaps.setup_keymaps()
	autocmds.setup_autocmds()

	-- ソースのカーソル位置に対応する ToCエントリにカーソルを合わせる
	local s = session.get()
	local src_lnum = vim.api.nvim_win_get_cursor(src_win)[1]
	local best_idx = 1
	for i, e in ipairs(s.entries) do
		if e.src_buf == src_buf and e.lnum <= src_lnum then
			best_idx = i
		end
	end
	vim.api.nvim_set_current_win(s.toc_win)
	pcall(vim.api.nvim_win_set_cursor, s.toc_win, { best_idx, 0 })
end

return M
