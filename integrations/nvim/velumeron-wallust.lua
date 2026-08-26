-- Applies the velumeron colour scheme, from ~/.config/nvim/after/plugin/.
--
-- after/plugin is the one hook every Neovim config has, whatever plugin manager
-- it uses: it is sourced at the end of startup, so this runs after a distro like
-- LazyVim has picked its own scheme, and wins. Nothing else about the config is
-- touched.
--
-- To keep the palette but choose the scheme yourself, put
--   vim.g.velumeron_colorscheme = false
-- in your init.lua. `:colorscheme velumeron` then still works, it just is not
-- forced on you at startup.
if vim.g.velumeron_colorscheme == false then
  return
end

-- pcall, because the scheme file and this hook are installed together but a user
-- is free to delete one: a missing scheme must not break startup.
pcall(vim.cmd.colorscheme, "velumeron")
