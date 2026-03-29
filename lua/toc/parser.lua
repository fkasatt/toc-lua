-- parser.lua
-- ソースバッファから目次エントリを構築する。
-- typst の #include "path" を展開し、複数ファイルをまたいだエントリリストも生成できる。

local util = require("toc.util")
local M = {}

-- ============================================================
-- 内部ヘルパー
-- ============================================================

--- ファイルパスに対応するバッファを取得または新規作成してロードする
--- ウィンドウの切り替えは行わない
---@param path string 絶対パス
---@return integer bufnr
local function get_or_load_buf(path)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(b) == path then
			if not vim.api.nvim_buf_is_loaded(b) then
				vim.fn.bufload(b)
			end
			return b
		end
	end
	local b = vim.fn.bufadd(path)
	vim.fn.bufload(b)
	return b
end

-- ============================================================
-- エントリ構築
-- ============================================================

--- ソース行リストから ToCエントリを構築する
--- marker の繰り返し数（`#`、`=`、`+`）で見出しレベルを判定する
--- コードフェンス（``` または ~~~）内の見出しは除外する
---@param lines string[]
---@param marker string 見出しマーカー文字（"#", "=", "+"）
---@return table[] entries {level, title, lnum, char_count, section_end}
function M.build_toc_entries(lines, marker)
	-- パターンは1回だけコンパイル（繰り返し呼び出しのコスト削減）
	local pattern = "^(" .. vim.pesc(marker) .. "+)%s+(.+)$"
	local headings = {}
	local in_code_fence = false

	for i, line in ipairs(lines) do
		-- コードフェンス（``` または ~~~）の開閉を追跡して、
		-- フェンス内の見出しマーカーを誤検知しないようにする
		if line:match("^```") or line:match("^~~~") then
			in_code_fence = not in_code_fence
		end
		if not in_code_fence then
			local level_str, title = line:match(pattern)
			if level_str and #level_str >= 1 then
				headings[#headings + 1] = { level = #level_str, title = title, lnum = i }
			end
		end
	end

	local content_from, content_to = util.find_content_range(lines)

	local entries = {}
	for idx, h in ipairs(headings) do
		-- 次の同レベル以上の見出しの直前までをセクション範囲とする
		local section_end = #lines
		for j = idx + 1, #headings do
			if headings[j].level <= h.level then
				section_end = headings[j].lnum - 1
				break
			end
		end
		entries[#entries + 1] = {
			level = h.level,
			title = h.title,
			lnum = h.lnum,
			char_count = util.count_chars(lines, h.lnum + 1, section_end, content_from, content_to),
			section_end = section_end,
		}
	end
	return entries
end

--- typst ファイルの `#include "path"` 行を解析して順序付きリストを返す
---@param buf integer
---@return {path: string, lnum: integer}[]
function M.collect_typst_includes(buf)
	local bufname = vim.api.nvim_buf_get_name(buf)
	if bufname == "" then
		return {}
	end
	local dir = vim.fn.fnamemodify(bufname, ":h")
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local includes = {}
	for lnum, line in ipairs(lines) do
		local path = line:match('^#include%s+"([^"]+)"')
		if path then
			local abs_path = vim.fn.resolve(dir .. "/" .. path)
			includes[#includes + 1] = { path = abs_path, lnum = lnum }
		end
	end
	return includes
end

--- ルートバッファのエントリと typst #include ファイルのエントリをインターリーブで構築する
--- typst 以外のファイルタイプの場合はルートエントリのみを返す
--- 各エントリに src_buf フィールド（所属バッファ番号）を付加する
---@param root_buf integer
---@param marker string
---@param ft string filetype
---@return table[] entries 全エントリ（src_buf付き）
---@return table<integer, true> included_bufs インクルード済みバッファ集合
function M.build_all_entries(root_buf, marker, ft)
	local root_lines = vim.api.nvim_buf_get_lines(root_buf, 0, -1, false)
	local root_entries = M.build_toc_entries(root_lines, marker)
	for _, e in ipairs(root_entries) do
		e.src_buf = root_buf
	end

	if ft ~= "typst" then
		return root_entries, {}
	end

	local includes = M.collect_typst_includes(root_buf)
	if #includes == 0 then
		return root_entries, {}
	end

	local result = {}
	local inc_bufs = {}
	local root_idx = 1
	for _, inc in ipairs(includes) do
		-- include 行より前の root エントリを先に追加
		while root_idx <= #root_entries and root_entries[root_idx].lnum < inc.lnum do
			result[#result + 1] = root_entries[root_idx]
			root_idx = root_idx + 1
		end
		-- include ファイルが存在する場合のみエントリを追加
		local stat = vim.uv.fs_stat(inc.path)
		if stat then
			local inc_buf = get_or_load_buf(inc.path)
			if inc_buf and vim.api.nvim_buf_is_valid(inc_buf) then
				inc_bufs[inc_buf] = true
				local inc_lines = vim.api.nvim_buf_get_lines(inc_buf, 0, -1, false)
				local inc_entries = M.build_toc_entries(inc_lines, marker)
				for _, e in ipairs(inc_entries) do
					e.src_buf = inc_buf
					result[#result + 1] = e
				end
			end
		end
	end
	-- 残りの root エントリを末尾に追加
	while root_idx <= #root_entries do
		result[#result + 1] = root_entries[root_idx]
		root_idx = root_idx + 1
	end
	return result, inc_bufs
end

return M
