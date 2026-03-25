Commander Plugin Samples

1. Copy `edgefn_chat_plugin.py` to:
`~/Library/Application Support/Commander/plugins/`
2. In Commander, run:
`set ai_api_key <YOUR_KEY>`
3. Optional:
`set ai_base_url https://api.edgefn.net/v1/chat/completions`
`set ai_model DeepSeek-V3.2`
4. Use:
`edge hello`

Plugin attachment interface

- `context.attachments` is a list of dicts with:
  - `path`
  - `name`
  - `kind` (`image` or `file`)
  - `mime_type`
- Files selected from the input button or pasted with `Command+V` are exposed here.
