-- util.lua
-- 副作用のない純粋関数と、複数モジュールで共通して使う描画ヘルパーを提供する。

local config = require("toc.config")
local M = {}

-- ============================================================
-- デバッグログ
-- ============================================================

--- デバッグログを toc-debug.log に追記する（config.log_enabled = true 時のみ）
---@param msg string
function M.log(msg)
	if not config.log_enabled then
		return
	end
	local path = vim.fn.stdpath("cache") .. "/toc-debug.log"
	local f = io.open(path, "a")
	if f then
		local ts = vim.fn.strftime("%H:%M:%S")
			.. string.format(".%03d", math.floor((vim.uv.hrtime() / 1e6) % 1000))
		f:write(string.format("[%s] %s\n", ts, msg))
		f:close()
	end
end

-- ============================================================
-- テキスト処理
-- ============================================================

--- 文字列を表示幅 max_width 以内に切り詰め、末尾に "…" を付加する
--- 表示幅が max_width 以下であればそのまま返す
---@param str string
---@param max_width integer
---@return string
function M.truncate(str, max_width)
	if vim.fn.strdisplaywidth(str) <= max_width then
		return str
	end
	local result = ""
	local width = 0
	for i = 0, vim.fn.strchars(str) - 1 do
		local ch = vim.fn.strcharpart(str, i, 1)
		local ch_width = vim.fn.strdisplaywidth(ch)
		if width + ch_width > max_width - 1 then
			break
		end
		result = result .. ch
		width = width + ch_width
	end
	return result .. "…"
end

-- ============================================================
-- 行範囲ユーティリティ
-- ============================================================

--- lines から HEADER/FOOTER コメントを検索し、コンテンツ有効範囲を返す
--- /* HEADER */ より前と /* FOOTER */ より後の行は文字数カウントから除外される
---@param lines string[]
---@return integer content_from 1-based
---@return integer content_to 1-based
function M.find_content_range(lines)
	local content_from = 1
	local content_to = #lines
	for i, line in ipairs(lines) do
		if line:match("/%*%s*HEADER%s*%*/") then
			content_from = i + 1
		end
		if line:match("/%*%s*FOOTER%s*%*/") then
			content_to = i - 1
			break
		end
	end
	return content_from, content_to
end

--- lines の from〜to 行の文字数合計を返す
--- content_from/content_to が指定されている場合はその範囲にクランプする
---@param lines string[]
---@param from integer 1-based
---@param to integer 1-based
---@param content_from integer|nil
---@param content_to integer|nil
---@return integer
function M.count_chars(lines, from, to, content_from, content_to)
	local clamped_from = content_from and math.max(from, content_from) or from
	local clamped_to = content_to and math.min(to, content_to) or to
	local total = 0
	for i = clamped_from, clamped_to do
		if lines[i] then
			total = total + vim.fn.strchars(lines[i])
		end
	end
	return total
end

-- ============================================================
-- ToCツリー表示
-- ============================================================

--- entries[idx] のツリープレフィックス文字列を計算する
--- 兄弟ノードの有無に応じて "├─ " / "└─ " / "│  " / "   " を組み合わせる
---@param entries table[]
---@param idx integer
---@return string
function M.compute_tree_prefix(entries, idx)
	local entry = entries[idx]
	if entry.level == 1 then
		return ""
	end

	local parts = {}
	for depth = 2, entry.level do
		local has_future_sibling = false
		for j = idx + 1, #entries do
			if entries[j].level < depth then
				break
			end
			if entries[j].level == depth then
				has_future_sibling = true
				break
			end
		end

		if depth == entry.level then
			parts[#parts + 1] = has_future_sibling and "├─ " or "└─ "
		else
			parts[#parts + 1] = has_future_sibling and "│  " or "   "
		end
	end

	return table.concat(parts)
end

-- ============================================================
-- タイトル検出
-- ============================================================

--- typst の `title: [...]` 記法からドキュメントタイトルを検索して返す
--- 見つからなければ nil を返す
---@param lines string[]
---@return string|nil
function M.detect_title(lines)
	for _, line in ipairs(lines) do
		local title = line:match("title:%s*%[([^%]]+)%]")
		if title then
			return title
		end
	end
	return nil
end

-- ============================================================
-- 描画ヘルパー
-- ============================================================

--- バッファ buf の ns 名前空間にハイライトを一括適用する
--- 事前に名前空間をクリアしてから再設定するため、呼び出し前のクリア不要
---@param buf integer
---@param hl_ns integer namespace id
---@param highlights table[] {line_idx, group, col_start, col_end}
function M.apply_highlights(buf, hl_ns, highlights)
	vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(buf, hl_ns, hl.group, hl.line_idx, hl.col_start, hl.col_end)
	end
end

--- ウィンドウの行番号・サインカラム・折り返しなどを非表示に設定する
---@param win integer
function M.setup_win_opts(win)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].spell = false
end

return M
