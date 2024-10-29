# simpleindent.nvim

An Simple Indent Plugin for Nvim.

## Install

### Lazy

```lua
{
    "M-wind/simpleindent.nvim",
    opts = {}
}
```

## Default Config

```lua
{
    char = "│",
    priority = 2,
    exclude = {
        filetype = { "checkhealth", "help" },
        buftype = { "nofile", "quickfix", "terminal", "prompt" },
    },
}
```

## Highlight Group

```lua
-- There is no default value.

-- indent default highlight
IndentLine
-- Current indent line highlight
IndentLineCurrent
```
