-- renderer.lua
-- ToCエントリの表示行生成と棒グラフ描画を担う。
-- バッファへの書き込みは行わず、表示行文字列とハイライト情報のみを返す。

local util = require("toc.util")
local config = require("toc.config")
local M = {}

-- ============================================================
-- ToCエントリ描画
-- ============================================================

--- entries を win_width 幅の表示行リストとハイライト情報に変換する
---@param entries table[]
---@param win_width integer
---@return string[] display_lines
---@return table[] highlights {line_idx, group, col_start, col_end}
function M.render_entries(entries, win_width)
	local display_lines = {}
	local highlights = {}
	local cfg = config.options
	local level_hl = config.level_hl

	local l1_num = 0
	for idx, entry in ipairs(entries) do
		local tree_prefix = util.compute_tree_prefix(entries, idx)
		local count_suffix = string.format("[%d字]", entry.char_count)

		local num_prefix = ""
		if entry.level == 1 then
			l1_num = l1_num + 1
			num_prefix = string.format("%d. ", l1_num)
		end

		local prefix_w = vim.fn.strdisplaywidth(tree_prefix) + vim.fn.strdisplaywidth(num_prefix)
		local suffix_w = vim.fn.strdisplaywidth(count_suffix)
		local available = math.max(8, win_width - prefix_w - suffix_w - 2)
		local title_display = util.truncate(entry.title, available)
		local title_w = vim.fn.strdisplaywidth(title_display)

		local pad = math.max(1, win_width - prefix_w - title_w - suffix_w)
		local line = tree_prefix .. num_prefix .. title_display .. string.rep(" ", pad) .. count_suffix

		local line_idx = #display_lines
		display_lines[#display_lines + 1] = line

		if #tree_prefix > 0 then
			highlights[#highlights + 1] =
				{ line_idx = line_idx, group = "TocTreeLine", col_start = 0, col_end = #tree_prefix }
		end
		if #num_prefix > 0 then
			highlights[#highlights + 1] = {
				line_idx = line_idx,
				group = "TocBarLabel",
				col_start = #tree_prefix,
				col_end = #tree_prefix + #num_prefix,
			}
		end

		local title_byte_end = #tree_prefix + #num_prefix + #title_display
		highlights[#highlights + 1] = {
			line_idx = line_idx,
			group = level_hl[entry.level] or "TocLevel4",
			col_start = #tree_prefix + #num_prefix,
			col_end = title_byte_end,
		}
		highlights[#highlights + 1] = {
			line_idx = line_idx,
			group = "TocCharCount",
			col_start = #line - #count_suffix,
			col_end = #line,
		}
	end

	return display_lines, highlights
end

-- ============================================================
-- 棒グラフ描画
-- ============================================================

--- 棒グラフ用エントリを収集する
--- L2 が存在すれば L2 単位でグラフ化し、存在しない場合は L1 単位でグラフ化する
--- L2 を持つ L1 はグラフに含めない（子 L2 で代表させる）
---@param entries table[]
---@return table[] bar_entries {char_count, l1_group, entry_idx}
local function collect_bar_entries(entries)
	local has_l2 = false
	for _, e in ipairs(entries) do
		if e.level == 2 then
			has_l2 = true
			break
		end
	end

	local bar_entries = {}
	local l1_count, current_l1 = 0, 0

	for i, entry in ipairs(entries) do
		if entry.level == 1 then
			l1_count = l1_count + 1
			current_l1 = l1_count
			if not has_l2 then
				-- L2 が存在しない文書: L1 を直接グラフ化
				bar_entries[#bar_entries + 1] = { char_count = entry.char_count, l1_group = l1_count, entry_idx = i }
			else
				-- L2 が存在する文書: L2 を持たない L1 のみグラフ化（孤立した L1 章）
				local has_child_l2 = false
				for j = i + 1, #entries do
					if entries[j].level == 1 then
						break
					end
					if entries[j].level == 2 then
						has_child_l2 = true
						break
					end
				end
				if not has_child_l2 then
					bar_entries[#bar_entries + 1] =
						{ char_count = entry.char_count, l1_group = current_l1, entry_idx = i }
				end
			end
		elseif has_l2 and entry.level == 2 then
			bar_entries[#bar_entries + 1] = { char_count = entry.char_count, l1_group = current_l1, entry_idx = i }
		end
	end
	return bar_entries
end

--- entry_idx → 棒グラフ列番号（1-based）の対応マップを構築する
--- bar_entries に含まれないエントリは前後の最近傍バーに割り当てる
---@param entries table[]
---@param bar_entries table[]
---@return table<integer, integer> map
local function build_entry_to_bar(entries, bar_entries)
	local map = {}
	for bar_idx, be in ipairs(bar_entries) do
		map[be.entry_idx] = bar_idx
	end
	for i = 1, #entries do
		if not map[i] then
			-- 前方に最近傍を探す
			for j = i, 1, -1 do
				if map[j] then
					map[i] = map[j]
					break
				end
			end
		end
		if not map[i] then
			-- 後方に最近傍を探す
			for j = i, #entries do
				if map[j] then
					map[i] = map[j]
					break
				end
			end
		end
	end
	return map
end

--- エントリリストから棒グラフ（点字記号による4段階解像度）を描画する
---
--- 描画条件（create_chart_layout での呼び出し前提）:
---   - bar_entries が空でないこと（全 char_count = 0 の場合も空を返す）
---   - 実際の表示可否は create_chart_layout の条件（行数 >= 32, 幅 >= toc_max_width - 2）で制御する
---
---@param entries table[]
---@return string[] chart_lines
---@return table[] chart_hls {line_idx, group, col_start, col_end, bar_col?}
---@return integer total_bars
---@return table<integer, integer> entry_to_bar
---@return table[] bar_entries
function M.render_bar_chart(entries)
	local cfg = config.options
	local bar_entries = collect_bar_entries(entries)
	if #bar_entries == 0 then
		return {}, {}, 0, {}, {}
	end

	local max_count = 0
	for _, e in ipairs(bar_entries) do
		if e.char_count > max_count then
			max_count = e.char_count
		end
	end
	if max_count == 0 then
		return {}, {}, 0, {}, {}
	end

	local bar_height = cfg.bar_height
	local bar_col_width = cfg.bar_col_width
	local braille = config.braille
	local braille_empty = config.braille_empty
	local total_units = bar_height * 4

	-- 各バーの高さ（4分の1単位）を事前計算
	-- char_count > 0 のバーは最低 1 単位を保証する
	local bar_units = {}
	for _, e in ipairs(bar_entries) do
		local units = math.floor(e.char_count / max_count * total_units + 0.5)
		if units == 0 and e.char_count > 0 then
			units = 1
		end
		bar_units[#bar_units + 1] = units
	end

	local chart_lines = {}
	local chart_hls = {}

	-- 棒グラフ本体（上から下へ行を生成）
	-- 各セルは「埋まり段数 / 4 行分の解像度」で braille 文字を選択する
	for row = bar_height, 1, -1 do
		local parts = {}
		local line_idx = #chart_lines
		local byte_offset = 0
		for col_idx, units in ipairs(bar_units) do
			local filled = math.floor(units / 4)
			local remainder = units % 4

			local cell
			if row <= filled then
				cell = braille[4]
			elseif row == filled + 1 and remainder > 0 then
				cell = braille[remainder]
			else
				cell = braille_empty
			end
			parts[#parts + 1] = cell .. " "

			if cell ~= braille_empty then
				chart_hls[#chart_hls + 1] = {
					line_idx = line_idx,
					group = "TocBarBlock",
					col_start = byte_offset,
					col_end = byte_offset + #cell,
					bar_col = col_idx,
				}
			end
			byte_offset = byte_offset + #cell + 1
		end
		chart_lines[#chart_lines + 1] = table.concat(parts)
	end

	-- L1 グループごとの文字数合計と列数を集計（ラベル・パーセント行の表示幅計算に使う）
	local group_chars = {}
	local group_cols = {}
	local total_chars = 0
	for _, e in ipairs(bar_entries) do
		group_chars[e.l1_group] = (group_chars[e.l1_group] or 0) + e.char_count
		group_cols[e.l1_group] = (group_cols[e.l1_group] or 0) + 1
		total_chars = total_chars + e.char_count
	end

	-- ラベル行（L1 章番号）
	local label_parts = {}
	local seen = {}
	for _, e in ipairs(bar_entries) do
		if not seen[e.l1_group] and e.l1_group > 0 then
			seen[e.l1_group] = true
			local s = tostring(e.l1_group)
			label_parts[#label_parts + 1] = s .. string.rep(" ", bar_col_width - #s)
		else
			label_parts[#label_parts + 1] = string.rep(" ", bar_col_width)
		end
	end

	local label_line_idx = #chart_lines
	chart_lines[#chart_lines + 1] = table.concat(label_parts)

	local seen2 = {}
	for col_i, e in ipairs(bar_entries) do
		if not seen2[e.l1_group] and e.l1_group > 0 then
			seen2[e.l1_group] = true
			local s = tostring(e.l1_group)
			local byte_start = (col_i - 1) * bar_col_width
			chart_hls[#chart_hls + 1] = {
				line_idx = label_line_idx,
				group = "TocBarLabel",
				col_start = byte_start,
				col_end = byte_start + #s,
			}
		end
	end

	-- パーセンテージ行（L1 グループ占有率）
	local pct_parts = {}
	local seen3 = {}
	for _, e in ipairs(bar_entries) do
		if not seen3[e.l1_group] and e.l1_group > 0 then
			seen3[e.l1_group] = true
			local pct = total_chars > 0 and math.floor(group_chars[e.l1_group] / total_chars * 100 + 0.5) or 0
			local s = tostring(pct) .. "%"
			local col_width = group_cols[e.l1_group] * bar_col_width
			if #s < col_width then
				pct_parts[#pct_parts + 1] = s .. string.rep(" ", col_width - #s)
			else
				pct_parts[#pct_parts + 1] = s
			end
			seen3[e.l1_group] = "done"
		elseif seen3[e.l1_group] ~= "done" then
			pct_parts[#pct_parts + 1] = string.rep(" ", bar_col_width)
		end
	end

	local pct_line_idx = #chart_lines
	chart_lines[#chart_lines + 1] = table.concat(pct_parts)

	local seen4 = {}
	local pct_byte_pos = 0
	for _, e in ipairs(bar_entries) do
		if not seen4[e.l1_group] and e.l1_group > 0 then
			seen4[e.l1_group] = true
			local pct = total_chars > 0 and math.floor(group_chars[e.l1_group] / total_chars * 100 + 0.5) or 0
			local s = tostring(pct) .. "%"
			chart_hls[#chart_hls + 1] = {
				line_idx = pct_line_idx,
				group = "TocCharCount",
				col_start = pct_byte_pos,
				col_end = pct_byte_pos + #s,
			}
		end
		pct_byte_pos = pct_byte_pos + bar_col_width
	end

	return chart_lines, chart_hls, #bar_entries, build_entry_to_bar(entries, bar_entries), bar_entries
end

return M
