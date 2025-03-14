# LlamaGen
Use Llama.cpp with Neovim

<div align="center">

![Local LLMs in Neovim: llamagen.nvim](/llamagen.png)

</div>

## Requires

- [Llama.cpp](https://github.com/ggml-org/llama.cpp) with any local model (GGUF models are recommended)
- [Curl](https://curl.se/)

## Installation

Install with your favorite plugin manager, e.g. [lazy.nvim](https://github.com/folke/lazy.nvim)

Example with Lazy

```lua
	-- Custom Parameters (with defaults)
	{
		"MHD-GDev/LlamaGen.nvim",
		dependencies = {
			"nvim-lualine/lualine.nvim",
		},
		config = function()
			require("LlamaGen").setup({
				quit_map = "q",
				retry_map = "<c-r>",
				accept_map = "<c-cr>",
				host = "localhost",
				port = "8080",
				display_mode = "float",
				show_prompt = true,
				show_model = false,
				no_auto_close = false,
				json_response = true,
				result_filetype = "markdown",
				debug = false,
			})

			-- Key mappings
			vim.keymap.set({ "n", "v" }, "<leader>]", ":llamagen<CR>")
			vim.keymap.set("n", "<leader>gc", "<CMD>llamagen Chat<CR>", { noremap = true })
			vim.keymap.set("n", "<leader>gg", "<CMD>llamagen Generate<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gD", ":'<,'>llamagen Document_Code<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gx", ":'<,'>llamagen Explain_Code<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gC", ":'<,'>llamagen Change_Code<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>ge", ":'<,'>llamagen Enhance_Code<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gR", ":'<,'>llamagen Review_Code<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gs", ":'<,'>llamagen Summarize<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>ga", ":'<,'>llamagen Ask<CR>", { noremap = true })
			vim.keymap.set("v", "<leader>gF", ":'<,'>llamagen Fix_Code<CR>", { noremap = true })
			vim.keymap.set("n", "<leader>gl", "<CMD>GenLoadModel<CR>", { noremap = true })
			vim.keymap.set("n", "<leader>gu", "<CMD>GenUnloadModel<CR>", { noremap = true })
		end,
	},
```

## Usage

Use command `llamagen` to generate text based on predefined and customizable prompts.

Example key maps:

```lua
vim.keymap.set({ 'n', 'v' }, '<leader>]', ':llamagen<CR>')
```

You can also directly invoke it with one of the [predefined prompts](./lua/llamagen/prompts.lua) or your custom prompts:

```lua
vim.keymap.set('v', '<leader>]', ':llamagen Enhance_Grammar_Spelling<CR>')
```

After a conversation begins, the entire context is sent to the LLM. That allows you to ask follow-up questions with

```lua
:llamagen Chat
```

and once the window is closed, you start with a fresh conversation.

For prompts which don't automatically replace the previously selected text (`replace = false`), you can replace the selected text with the generated output with `<c-cr>`.

### Note:
To use llamagen you need to load or unload models with these commands ```:GenUnloadModel``` and ```:GenLoadModel``` .

##### Models:

- You can downlaod models from [Hugingface](https://huggingface.co/models) <img height="20" src="https://unpkg.com/@lobehub/icons-static-svg@latest/icons/huggingface-color.svg"/>

## Custom Prompts

[All prompts](./lua/llamagen/prompts.lua) are defined in `require('llamagen').prompts`, you can enhance or modify them.

Example:

````lua
require('llamagen').prompts['Elaborate_Text'] = {
  prompt = "Elaborate the following text:\n$text",
  replace = true
}
require('llamagen').prompts['Fix_Code'] = {
  prompt = "Fix the following code. Only output the result in format ```$filetype\n...\n```:\n```$filetype\n$text\n```",
  replace = true,
  extract = "```$filetype\n(.-)```"
}
````

You can use the following properties per prompt:

- `prompt`: (string | function) Prompt either as a string or a function which should return a string. The result can use the following placeholders:
  - `$text`: Visually selected text or the content of the current buffer
  - `$filetype`: File type of the buffer (e.g. `javascript`)
  - `$input`: Additional user input
  - `$register`: Value of the unnamed register (yanked text)
- `replace`: `true` if the selected text shall be replaced with the generated output
- `extract`: Regular expression used to extract the generated result
- `model`: The model to use, default: `local-model`

## Tip

User selections can be delegated to [Telescope](https://github.com/nvim-telescope/telescope.nvim) with [telescope-ui-select](https://github.com/nvim-telescope/telescope-ui-select.nvim).
