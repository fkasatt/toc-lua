-- session.lua
-- アクティブな ToC セッションの状態を管理する。
-- セッションとは「1つの ToC ウィンドウが開いている状態」を指す。
-- S（セッションテーブル）を唯一の真実として保持し、get/set/close で外部から操作する。

local parser = require("toc.parser")
local renderer = require("toc.renderer")
local util = require("toc.util")
local config = require("toc.config")

local M = {}

-- アクティブセッション（nil = 閉じている）
local S = nil

-- namespace は初回 ensure_init() 時に作成し、以降再利用する
local ns = nil
local chart_ns = nil
local initialized = false

-- インクルードバッファ → ルートバッファのマッピング（セッションを跨いで保持）
-- typst の #include で読み込まれた子ファイルから open() したとき、
-- ルートファイルのセッションを引き継ぐために使う
local include_to_root = {}

-- ============================================================
-- 初期化
-- ============================================================

--- namespace を初回呼び出し時に一度だけ作成する
--- 起動時の副作用を防ぐため、open() 内で遅延初期化する
function M.ensure_init()
	if initialized then
		return
	end
	initialized = true
	ns = vim.api.nvim_create_namespace("toc_highlight")
	chart_ns = vim.api.nvim_create_namespace("toc_chart_highlight")
end

--- ハイライト用 namespace を返す
---@return integer
function M.get_ns()
	return ns
end

--- 棒グラフ用 namespace を返す
---@return integer
function M.get_chart_ns()
	return chart_ns
end

-- ============================================================
-- セッションアクセス
-- ============================================================

--- アクティブセッションを返す（nil = 閉じている）
---@return table|nil
function M.get()
	return S
end

--- セッションを設定する
---@param s table
function M.set(s)
	S = s
end

--- include_to_root マッピングを返す
---@return table<integer, integer>
function M.get_include_to_root()
	return include_to_root
end

-- ============================================================
-- ソースウィンドウ特定
-- ============================================================

--- ソースバッファを表示しているウィンドウを返す
--- S.src_win が有効ならそれを優先し、なければ src_buf を表示中の先頭ウィンドウを返す
---@return integer|nil
function M.find_src_win()
	if S.src_win and vim.api.nvim_win_is_valid(S.src_win) then
		return S.src_win
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == S.src_buf then
			return win
		end
	end
	return nil
end

-- ============================================================
-- タイトル表示
-- ============================================================

--- ルートバッファからドキュメントタイトルを取得してタイトルバッファに描画する
--- full = true のとき折り返しを許可して全文表示する（タイトルウィンドウにフォーカスしているとき）
--- full = false のとき 1 行に収まるよう切り詰める
---@param entries table[]
---@param win_width integer
---@param full boolean
function M.refresh_title(entries, win_width, full)
	local lines = vim.api.nvim_buf_get_lines(S.root_buf, 0, -1, false)
	local header_line = util.detect_title(lines)
	if not header_line then
		-- タイトル未検出時はファイル名をフォールバック表示
		local bufname = vim.api.nvim_buf_get_name(S.root_buf)
		if bufname ~= "" then
			header_line = "📄 " .. vim.fn.fnamemodify(bufname, ":t")
		end
	end
	if not header_line then
		return
	end

	local total_chars = 0
	for _, e in ipairs(entries) do
		total_chars = total_chars + e.char_count
	end
	local total_suffix = string.format("[%d字]", total_chars)
	local suffix_w = vim.fn.strdisplaywidth(total_suffix)

	local display_title
	if full then
		display_title = header_line
	else
		local max_title_w = math.max(4, win_width - suffix_w - 1)
		display_title = util.truncate(header_line, max_title_w)
	end

	local title_w = vim.fn.strdisplaywidth(display_title)
	local pad = math.max(1, win_width - title_w - suffix_w)
	local full_header = display_title .. string.rep(" ", pad) .. total_suffix

	vim.bo[S.title_buf].modifiable = true
	vim.api.nvim_buf_set_lines(S.title_buf, 0, -1, false, { full_header })
	vim.bo[S.title_buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(S.title_buf, ns, 0, -1)
	vim.api.nvim_buf_add_highlight(S.title_buf, ns, "TocDocTitle", 0, 0, #display_title)
	vim.api.nvim_buf_add_highlight(S.title_buf, ns, "TocCharCount", 0, #full_header - #total_suffix, #full_header)

	-- full 表示時は wrap + 高さ拡張、通常時は 1 行に戻す
	if S.title_win and vim.api.nvim_win_is_valid(S.title_win) then
		if full then
			vim.wo[S.title_win].wrap = true
			local header_w = vim.fn.strdisplaywidth(full_header)
			local lines_needed = math.ceil(header_w / math.max(1, win_width))
			vim.api.nvim_win_set_height(S.title_win, math.max(1, lines_needed))
		else
			vim.wo[S.title_win].wrap = false
			vim.api.nvim_win_set_height(S.title_win, 1)
		end
	end
end

-- ============================================================
-- リフレッシュ
-- ============================================================

--- ToCバッファを最新のソース内容で更新する
--- エントリ数が 0 の場合はエントリを返すだけでバッファを更新しない
---@return table[] entries
function M.refresh_toc()
	if not vim.api.nvim_win_is_valid(S.toc_win) then
		return S.entries
	end

	local entries, inc_bufs = parser.build_all_entries(S.root_buf, S.marker, S.ft)
	S.included_bufs = inc_bufs
	if #entries == 0 then
		return entries
	end

	local win_width = vim.api.nvim_win_get_width(S.toc_win)
	local display_lines, highlights = renderer.render_entries(entries, win_width)

	vim.bo[S.toc_buf].modifiable = true
	vim.api.nvim_buf_set_lines(S.toc_buf, 0, -1, false, display_lines)
	vim.bo[S.toc_buf].modifiable = false

	util.apply_highlights(S.toc_buf, ns, highlights)

	if S.title_buf and vim.api.nvim_buf_is_valid(S.title_buf) then
		M.refresh_title(entries, win_width, false)
	end

	S.entries = entries
	return entries
end

--- 棒グラフバッファを最新のエントリで更新する
function M.refresh_chart()
	if not S.chart_buf or not vim.api.nvim_buf_is_valid(S.chart_buf) then
		return
	end

	local chart_lines, chart_hls, total_bars, entry_to_bar, bar_entries =
		renderer.render_bar_chart(S.entries, S.bar_height)
	if #chart_lines == 0 then
		return
	end

	vim.bo[S.chart_buf].modifiable = true
	vim.api.nvim_buf_set_lines(S.chart_buf, 0, -1, false, chart_lines)
	vim.bo[S.chart_buf].modifiable = false

	util.apply_highlights(S.chart_buf, ns, chart_hls)

	S.entry_to_bar = entry_to_bar
	S.chart_hls = chart_hls
	S.total_bars = total_bars
	S.bar_entries = bar_entries
end

--- ToC と棒グラフを両方リフレッシュする
---@return table[] entries
function M.do_refresh()
	local t0 = vim.uv.hrtime()
	util.log("do_refresh: start")
	local entries = M.refresh_toc()
	local t1 = vim.uv.hrtime()
	util.log(string.format("do_refresh: refresh_toc done (%.1fms, %d entries)", (t1 - t0) / 1e6, #entries))
	if S.chart_buf then
		M.refresh_chart()
		local t2 = vim.uv.hrtime()
		util.log(string.format("do_refresh: refresh_chart done (%.1fms)", (t2 - t1) / 1e6))
	end
	util.log(string.format("do_refresh: total %.1fms", (vim.uv.hrtime() - t0) / 1e6))
	return entries
end

-- ============================================================
-- カーソル位置
-- ============================================================

--- toc_buf 上のカーソル行に対応するエントリを返す
---@return table|nil entry
---@return integer lnum
---@return integer idx
function M.entry_at_cursor()
	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local idx = lnum
	return S.entries[idx], lnum, idx
end

-- ============================================================
-- 棒グラフカレントハイライト
-- ============================================================

--- ToCカーソル位置に対応する棒グラフ列をハイライトし、横スクロールを追従させる
---@param entry_idx integer
function M.update_chart_current(entry_idx)
	if not S.chart_buf or not vim.api.nvim_buf_is_valid(S.chart_buf) then
		return
	end

	local bar_col = S.entry_to_bar[entry_idx]
	vim.api.nvim_buf_clear_namespace(S.chart_buf, chart_ns, 0, -1)
	if not bar_col then
		return
	end

	-- L1 エントリの場合は同じ l1_group の全棒をハイライトする
	local target_cols = { [bar_col] = true }
	local entry = S.entries[entry_idx]
	if entry and entry.level == 1 and S.bar_entries then
		local l1_group = nil
		for _, be in ipairs(S.bar_entries) do
			if be.entry_idx >= entry_idx then
				l1_group = be.l1_group
				break
			end
		end
		if l1_group then
			target_cols = {}
			for col_i, be in ipairs(S.bar_entries) do
				if be.l1_group == l1_group then
					target_cols[col_i] = true
				end
			end
		end
	end

	for _, hl in ipairs(S.chart_hls) do
		if hl.group == "TocBarBlock" and target_cols[hl.bar_col] then
			vim.api.nvim_buf_add_highlight(
				S.chart_buf,
				chart_ns,
				"TocBarCurrent",
				hl.line_idx,
				hl.col_start,
				hl.col_end
			)
		end
	end

	-- 棒グラフ横スクロール追従（左 5 本残し、末尾は右寄せ）
	if S.chart_win and vim.api.nvim_win_is_valid(S.chart_win) then
		local cfg = config.options
		local chart_w = vim.api.nvim_win_get_width(S.chart_win)
		local bars_visible = math.floor(chart_w / cfg.bar_col_width)
		local max_leftcol = math.max(0, S.total_bars * cfg.bar_col_width - chart_w)
		local target_leftcol = math.max(0, (bar_col - 6) * cfg.bar_col_width)
		if S.total_bars - bar_col < bars_visible - 5 then
			target_leftcol = max_leftcol
		end
		vim.api.nvim_win_call(S.chart_win, function()
			vim.fn.winrestview({ leftcol = target_leftcol })
		end)
	end
end

-- ============================================================
-- 幅調整
-- ============================================================

--- ターミナルリサイズ時に棒グラフの高さを再計算し、ウィンドウを調整する
--- 端末高さ 24 行未満になった場合、または L1/L2 が 14 以上で高さ 7 行未満になった場合は
--- 棒グラフウィンドウを閉じる
function M.adjust_chart_height()
	if not S then
		return
	end

	-- 棒グラフが存在しない場合は何もしない
	if not S.chart_win or not vim.api.nvim_win_is_valid(S.chart_win) then
		return
	end

	local cfg = config.options
	local win_width = vim.api.nvim_win_get_width(S.toc_win)

	-- 端末高さまたは幅が不足したら棒グラフを閉じる
	if vim.o.lines < 24 or win_width < cfg.toc_max_width - 2 then
		vim.api.nvim_win_close(S.chart_win, false)
		S.chart_win = nil
		S.chart_buf = nil
		return
	end

	-- ターミナル高さから新しい bar_height を計算する
	local new_height = math.max(7, math.min(16, math.floor(vim.o.lines * 0.35)))

	-- L1/L2 タイトル行が 14 以上なら縮小する
	local l1l2_count = 0
	for _, e in ipairs(S.entries) do
		if e.level == 1 or e.level == 2 then
			l1l2_count = l1l2_count + 1
		end
	end
	if l1l2_count >= 14 then
		local reduced = math.floor(vim.o.lines * 0.2)
		new_height = math.min(new_height, reduced)
		if new_height < 7 then
			vim.api.nvim_win_close(S.chart_win, false)
			S.chart_win = nil
			S.chart_buf = nil
			S.bar_height = nil
			return
		end
	end

	S.bar_height = new_height
	vim.wo[S.chart_win].winfixheight = false
	vim.api.nvim_win_set_height(S.chart_win, S.bar_height + 2)
	vim.wo[S.chart_win].winfixheight = true
	M.refresh_chart()
end

--- ソース幅を src_min_width 以上に保つよう ToC 列幅を調整する
--- VimResized イベント時や初期化時に呼ばれる
function M.adjust_toc_width()
	if not S or not vim.api.nvim_win_is_valid(S.toc_win) then
		return
	end
	local src_win = M.find_src_win()
	if not src_win then
		return
	end
	local cfg = config.options
	-- separator(1列) を除いた利用可能幅から ToC 幅を決定する
	local cols = vim.o.columns - 1
	local desired = S.toc_width
	local new_toc_w = math.min(desired, math.max(20, cols - cfg.src_min_width))
	local toc_w = vim.api.nvim_win_get_width(S.toc_win)
	if new_toc_w ~= toc_w then
		vim.wo[S.toc_win].winfixwidth = false
		vim.api.nvim_win_set_width(S.toc_win, new_toc_w)
		vim.wo[S.toc_win].winfixwidth = true
		M.do_refresh()
	end
end

-- ============================================================
-- クローズ
-- ============================================================

--- セッションを閉じてすべてのウィンドウ・バッファ・オートコマンドを破棄する
function M.close()
	if not S then
		return
	end
	util.log("close_session: called")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_scroll_sync")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_auto_refresh")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_src_follow")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_title_enter")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_title_leave")
	pcall(vim.api.nvim_del_augroup_by_name, "toc_vim_resized")
	if S.chart_win and vim.api.nvim_win_is_valid(S.chart_win) then
		vim.api.nvim_win_close(S.chart_win, false)
	end
	if S.toc_win and vim.api.nvim_win_is_valid(S.toc_win) then
		vim.api.nvim_win_close(S.toc_win, false)
	end
	if S.title_win and vim.api.nvim_win_is_valid(S.title_win) then
		vim.api.nvim_win_close(S.title_win, false)
	end
	if S.pad_win and vim.api.nvim_win_is_valid(S.pad_win) then
		vim.api.nvim_win_close(S.pad_win, false)
	end
	if S.pad_buf and vim.api.nvim_buf_is_valid(S.pad_buf) then
		vim.api.nvim_buf_delete(S.pad_buf, { force = true })
	end
	S = nil
end

return M
