Commander Plugin Samples

No built-in provider-specific chat plugin is bundled here.
Use the built-in `ai` routing with `gemini` or `openai_compatible`.

Plugin attachment interface

- `context.attachments` is a list of dicts with:
  - `path`
  - `name`
  - `kind` (`image` or `file`)
  - `mime_type`
- Files selected from the input button or pasted with `Command+V` are exposed here.
