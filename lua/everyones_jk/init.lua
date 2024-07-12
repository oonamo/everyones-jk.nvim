---@class jk.module
--- Config Table
---@field config jk.config
--- Holds original j mapping
---@field _j table
--- Holds original k mapping
---@field _k table
local M = {}

---@class jk.config.keys.Spec
--- Key to trigger
---@field [1] string
--- Command or function to call after trigger
---@field [2] string
--- Keymap is expressive
---@field expr? boolean
--- Custom keymapping for this character
---@field map? fun(c: string)

---@class jk.config
M.config = {}

---@class jk._help
--- Recommended keymaps
---@field recommendations { keys: jk.config.keys[] }

---@class jk._help
local H = {}

---@class jk.config.keys
--- Name of jk spec
---@field [1] string
--- 'J' spec
---@field j jk.config.keys.Spec
--- 'K' spec
---@field k jk.config.keys.Spec
--- function to be called before starting. If it returns an error or false, action will not start
---@field start? string|fun(): boolean

---@class jk.config
--- Key specs for jk
---@field keys jk.config.keys[]
--- If true, stops 'jk' mode when an error occurs
---@field stop_on_err boolean
--- If true, merges recommended keys
---@field use_recommended boolean

H.recommendations = {
	keys = {
		{
			"Buffer",
			j = {
				"]b",
				"bnext",
			},
			k = { "[b", "bprev" },
			start = function()
				local wins = vim.api.nvim_list_bufs()
				local bufcount = 0
				for _, v in ipairs(wins) do
					if vim.api.nvim_buf_is_valid(v) and vim.api.nvim_buf_is_loaded(v) and vim.bo[v].ft ~= "" then
						bufcount = bufcount + 1
					end
				end
				if bufcount < 2 then
					H.message("not enough buffers")
					return false
				end
				return true
			end,
		},
		{
			"Quickfix",
			j = { "]q", "cnext" },
			k = { "[q", "cprev" },
			start = "copen",
		},
	},
}

H.defaults = {
	stop_on_err = true,
	keys = {},
}

---@param opts? jk.config
function M.setup(opts)
	if opts and opts.use_recommended then
		vim.tbl_map(function(k)
			table.insert(opts.keys or {}, k or {})
		end, H.recommendations.keys)
	else
		M.config.keys = opts and opts.keys or {}
	end
	M.config = vim.tbl_extend("force", H.defaults, opts or {})
	H.get_old_jk()
	H.set_keymaps()
end

function H.unmap_jk()
	pcall(vim.api.nvim_del_keymap, "n", "j")
	pcall(vim.api.nvim_del_keymap, "n", "k")
	pcall(vim.api.nvim_buf_del_keymap, 0, "n", "j")
	pcall(vim.api.nvim_buf_del_keymap, 0, "n", "k")
end

function H.get_old_jk()
	local j = {}
	local k = {}
	for _, v in ipairs(vim.api.nvim_get_keymap("n")) do
		if v.lhs == "j" then
			j = v
		elseif v.lhs == "k" then
			k = v
		end
	end
	for _, v in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
		if v.lhs == "j" then
			j = v
		elseif v.lhs == "k" then
			k = v
		end
	end
	M._j = j
	M._k = k
end

--- Restores j and k keymaps if they were ever created
function M.restore_keymaps()
	if M._j.callback or M._j.rhs then
		vim.keymap.set("n", "j", M._j.callback or M._j.rhs, {
			desc = M._j.desc,
			expr = M._j.expr == 1,
			silent = M._j.silent == 1,
			nowait = M._j.nowait == 1,
			buffer = M._j.buffer,
		})
	end
	if M._k.callback or M._k.rhs then
		vim.keymap.set("n", "k", M._k.callback or M._k.rhs, {
			desc = M._k.desc,
			expr = M._k.expr == 1,
			silent = M._k.silent == 1,
			nowait = M._k.nowait == 1,
			buffer = M._k.buffer,
		})
	end
end

---FROM: mini.ai
---@param msg string|string[]
function H.message(msg)
	---@cast msg string[]
	msg = type(msg) == "string" and { { msg } } or msg

	table.insert(msg, 1, { "(everyones-jk) ", "WarningMsg" })

	local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
	local chunks, tot_width = {}, 0
	for _, ch in ipairs(msg) do
		local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
		table.insert(chunks, new_ch)
		tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
		if tot_width >= max_width then
			break
		end
	end

	-- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
	vim.cmd([[echo '' | redraw]])

	vim.api.nvim_echo(chunks, true, {})
	vim.defer_fn(function()
		vim.cmd([[echo '' | redraw]])
	end, 1000)
end

function H.stop_jk()
	vim.keymap.del("n", "j")
	vim.keymap.del("n", "k")
	M.restore_keymaps()
end

function H.input(key)
	vim.schedule(function()
		vim.api.nvim_input(vim.api.nvim_replace_termcodes(key, true, true, true))
	end)
end

---@param j_f fun()
---@param k_f fun()
function H.gen_jk_func(j_f, k_f)
	return function()
		local char = vim.fn.getcharstr()
		if char == "j" then
			if j_f() then
				if M.config.stop_on_err then
					H.stop_jk()
				end
			end
		elseif char == "k" then
			if k_f() then
				if M.config.stop_on_err then
					H.stop_jk()
				end
			end
		else
			H.stop_jk()
			H.input(char)
		end
	end
end

---@param cmd string|function
---@return boolean, string
function H.exec_cmd(cmd)
	if type(cmd) == "string" then
		---@diagnostic disable-next-line: param-type-mismatch
		return pcall(vim.cmd, cmd)
	elseif type(cmd) == "function" then
		return pcall(cmd)
	else
		error("not a string or function")
	end
end

---Calls a command safely. Notifies user on error
---@param v jk.config.keys
---@param cmd string|function
---@return true|false
function H.safe_call_cmd(v, cmd)
	local ok, err = H.exec_cmd(cmd)
	if not ok then
		H.message("error on '" .. v[1] .. ": " .. err)
	end
	return ok
end

---Creates mappings for an action
---@param char string
---@param v jk.config.keys
function H.create_map(char, v)
	---@param c string
	local function map(c)
		if v[c].expr then
			if type(v[c][2]) == "string" then
				return function()
					H.input(v[c][2])
					H.input(c)
				end
			elseif type(v[c][2]) == "function" then
				return function()
					H.input(v[c][2]())
					H.input(c)
				end
			end
			error("expressive mapping is not a function that or string")
		end
		return function()
			local ok = H.safe_call_cmd(v, v[c][2])
			if ok then
				H.input(c)
			end
			return ok == false
		end
	end

	vim.keymap.set("n", v[char][1], function()
		if v.start then
			local ok, should_start = H.safe_call_cmd(v, v.start)
			if not ok or should_start == false then
				return
			end
		end

		if v[char].expr then
			if type(v[char][2]) == "string" then
				H.input(v[char][2])
			elseif type(v[char][2]) == "function" then
				H.input(v[char][2]())
			else
				error("expressive mapping is not a string or function")
			end
		else
			local ok = H.exec_cmd(v[char][2])
			if not ok then
				return
			end
		end
		H.unmap_jk()

		vim.keymap.set("n", "j", H.gen_jk_func(v.j.map or map("j"), v.k.map or map("k")))
		vim.keymap.set("n", "k", H.gen_jk_func(v.j.map or map("j"), v.k.map or map("k")))
		H.input(char)
	end)
end

---Sets keymap for jk
function H.set_keymaps()
	for _, v in ipairs(M.config.keys or {}) do
		H.create_map("j", v)
		H.create_map("k", v)
	end
end

function M.get_recommendations()
	return H.recommendations.keys
end

return M
