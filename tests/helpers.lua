-- tests/helpers.lua
local M = {}

--- スクラッチバッファを作成して内容を設定し、カレントバッファにする
---@param lines string[]
---@param ft string|nil  filetype（省略可）
---@return integer bufnr
function M.scratch_buf(lines, ft)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if ft then
		vim.bo[buf].filetype = ft
	end
	return buf
end

--- バッファの全行を文字列テーブルで返す
---@param bufnr integer|nil  省略時はカレントバッファ
---@return string[]
function M.buf_lines(bufnr)
	return vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
end

--- テスト後にバッファを破棄する after_each 用クリーンアップ
function M.cleanup_buf(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
end

--- 全ウィンドウを閉じて1つにする（テスト間の状態リセット）
function M.close_extra_wins()
	while #vim.api.nvim_list_wins() > 1 do
		local wins = vim.api.nvim_list_wins()
		vim.api.nvim_win_close(wins[#wins], true)
	end
end

return M
