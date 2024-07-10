local M = {}
local H = {}

H.recommendations = {
	keys = {
		{
			"Buffer",
			j = { "]b", "bnext" },
			k = { "[b", "bprev" },
			start = function()
				local bufcount = #vim.api.nvim_list_wins()
				if bufcount < 2 then
					error("not enough buffers")
				end
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

function M.setup(opts)
	if opts.use_recommended then
		opts = vim.tbl_extend("force", H.recommendations, opts or {})
	else
		M.keys = opts.keys or {}
	end
	M.config = vim.tbl_extend("force", H.defaults, opts)
	H.get_old_jk()
	H.set_keymaps()
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
	M._j = j
	M._k = k
end

function M.restore_keymaps()
	if M._j.callback or M._j.rhs then
		vim.keymap.set("n", "j", M._j.callback or M._j.rhs, {
			desc = M._j.desc,
			expr = M._j.expr == 1,
			silent = M._j.silent == 1,
			nowait = M._j.nowait == 1,
		})
	end
	if M._k.callback or M._k.rhs then
		vim.keymap.set("n", "k", M._k.callback or M._k.rhs, {
			desc = M._k.desc,
			expr = M._k.expr == 1,
			silent = M._k.silent == 1,
			nowait = M._k.nowait == 1,
		})
	end
end

function H.stop_jk()
	vim.keymap.del("n", "j")
	vim.keymap.del("n", "k")
	M.restore_keymaps()
end

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
			vim.api.nvim_input(vim.api.nvim_replace_termcodes(char, true, true, true))
		end
	end
end

function H.exec_cmd(cmd)
	if type(cmd) == "string" then
		return pcall(vim.cmd, cmd)
	elseif type(cmd) == "function" then
		return pcall(cmd)
	else
		error("not a string or function")
	end
end

function H.safe_call_cmd(v, cmd)
	local ok, err = H.exec_cmd(cmd)
	if not ok then
		vim.notify("error on '" .. v[1] .. "\n" .. err, vim.log.levels.WARN)
	end
	return ok
end

function H.create_map(char, v)
	local function map(c)
		return function()
			local ok = H.safe_call_cmd(v, v[c][2])
			if ok then
				vim.api.nvim_input(vim.api.nvim_replace_termcodes(c, true, true, true))
			end
			return ok == false
		end
	end
	vim.keymap.set("n", v[char][1], function()
		if v.start then
			local ok = H.safe_call_cmd(v, v.start)
			if not ok then
				return
			end
		end
		local ok = H.exec_cmd(v[char][2])
		if not ok then
			return
		end
		vim.keymap.set("n", "j", H.gen_jk_func(map("j"), map("k")))
		vim.keymap.set("n", "k", H.gen_jk_func(map("j"), map("k")))
		vim.api.nvim_input(vim.api.nvim_replace_termcodes(char, true, true, true))
	end)
end

function H.set_keymaps()
	for _, v in ipairs(M.config.keys or {}) do
		H.create_map("j", v)
		H.create_map("k", v)
	end
end

M.setup({
	use_recommended = true,
})
