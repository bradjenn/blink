local colors = require("kanagawa.colors").setup({ theme = "wave" })
local theme = colors.theme

return {
  normal = {
    a = { bg = theme.syn.keyword, fg = theme.ui.bg_m3, gui = "bold" },
    b = { bg = theme.ui.bg_p1, fg = theme.syn.keyword },
    c = { bg = theme.ui.bg, fg = theme.ui.fg },
  },
  insert = {
    a = { bg = theme.syn.string, fg = theme.ui.bg_m3, gui = "bold" },
    b = { bg = theme.ui.bg_p1, fg = theme.syn.string },
  },
  command = {
    a = { bg = theme.syn.operator, fg = theme.ui.bg_m3, gui = "bold" },
    b = { bg = theme.ui.bg_p1, fg = theme.syn.operator },
  },
  visual = {
    a = { bg = theme.syn.special1, fg = theme.ui.bg_m3, gui = "bold" },
    b = { bg = theme.ui.bg_p1, fg = theme.syn.special1 },
  },
  replace = {
    a = { bg = theme.syn.number, fg = theme.ui.bg_m3, gui = "bold" },
    b = { bg = theme.ui.bg_p1, fg = theme.syn.number },
  },
  inactive = {
    a = { bg = theme.ui.bg_m3, fg = theme.ui.fg_dim },
    b = { bg = theme.ui.bg_m3, fg = theme.ui.fg_dim },
    c = { bg = theme.ui.bg_m3, fg = theme.ui.fg_dim },
  },
}
