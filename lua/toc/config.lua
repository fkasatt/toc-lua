-- config.lua
-- プラグインのデフォルト設定と定数を管理する。
-- setup(opts) によりユーザーが値をオーバーライドできる。

local M = {}

-- デフォルト設定
-- opts.width: ToC列の初期幅（nil = 自動）
M.defaults = {
	-- ToCウィンドウの最大列幅
	toc_max_width = 50,
	-- ソースウィンドウに確保する最小列幅（これを下回るとToCを縮小する）
	src_min_width = 50,
	-- 棒グラフの最大高さ（行数）
	bar_height = 15,
	-- 棒グラフウィンドウの高さ（棒グラフ + ラベル行 + パーセント行）
	chart_win_height = 16,
	-- 棒グラフ1本の列幅（バイト数）
	bar_col_width = 3,
}

-- 現在の設定（setup() で上書きされる）
M.options = vim.deepcopy(M.defaults)

-- デバッグログ。true にするとキャッシュディレクトリに toc-debug.log を書き込む
M.log_enabled = false

-- filetype → 見出しマーカー文字の対応表
-- build_toc_entries はこの文字の繰り返しで見出しレベルを判定する
M.heading_markers = {
	markdown = "#",
	typst = "=",
	text = "+",
	txt = "+",
}

-- ハイライトグループ → 見出しレベルの対応
M.level_hl = {
	[1] = "TocLevel1",
	[2] = "TocLevel2",
	[3] = "TocLevel3",
}

-- 棒グラフのセル文字（4段階解像度: 1/4 ～ 4/4 埋まり）
M.braille = { "⣀⣀", "⣤⣤", "⣶⣶", "⣿⣿" }
M.braille_empty = "  "

--- ユーザー設定をデフォルトにマージする
---@param opts table|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
