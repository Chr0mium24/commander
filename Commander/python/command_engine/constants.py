from __future__ import annotations

DEFAULT_PYTHON = "/usr/bin/python3"

SETTING_KEY_MAP = {
    "alias_py": ("aliasPy", "string"),
    "alias_def": ("aliasDef", "string"),
    "alias_ask": ("aliasAsk", "string"),
    "alias_ser": ("aliasSer", "string"),
    "python_path": ("pythonPath", "string"),
    "script_dir": ("scriptDirectory", "string"),
    "gemini_key": ("geminiApiKey", "string"),
    "gemini_model": ("geminiModel", "string"),
    "gemini_proxy": ("geminiProxy", "string"),
    "history_limit": ("historyLimit", "int"),
    "auto_copy": ("autoCopy", "bool"),
}

for _friendly, _tuple in list(SETTING_KEY_MAP.items()):
    _storage_key, _value_type = _tuple
    SETTING_KEY_MAP[_storage_key] = (_storage_key, _value_type)
