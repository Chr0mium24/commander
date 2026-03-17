from __future__ import annotations

from pathlib import Path

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
    "ai_provider": ("aiProvider", "string"),
    "ai_base_url": ("aiBaseURL", "string"),
    "ai_api_key": ("aiApiKey", "string"),
    "ai_model": ("aiModel", "string"),
    "plugin_dir": ("pluginDirectory", "string"),
    "enabled_plugins": ("enabledPlugins", "string"),
    "disabled_plugins": ("disabledPlugins", "string"),
}

for _friendly, _tuple in list(SETTING_KEY_MAP.items()):
    _storage_key, _value_type = _tuple
    SETTING_KEY_MAP[_storage_key] = (_storage_key, _value_type)

SETTING_SCHEMA = [
    {"key": "aliasPy", "type": "string", "label": "Alias: Python", "group": "aliases"},
    {"key": "aliasDef", "type": "string", "label": "Alias: Dictionary", "group": "aliases"},
    {"key": "aliasAsk", "type": "string", "label": "Alias: Ask", "group": "aliases"},
    {"key": "aliasSer", "type": "string", "label": "Alias: Search", "group": "aliases"},
    {"key": "pythonPath", "type": "string", "label": "Python Path", "group": "runtime"},
    {"key": "scriptDirectory", "type": "string", "label": "Script Directory", "group": "runtime"},
    {"key": "pluginDirectory", "type": "string", "label": "Plugin Directory", "group": "runtime"},
    {"key": "enabledPlugins", "type": "string", "label": "Enabled Plugins", "group": "plugins"},
    {"key": "disabledPlugins", "type": "string", "label": "Disabled Plugins", "group": "plugins"},
    {"key": "geminiApiKey", "type": "secret", "label": "Gemini API Key", "group": "ai"},
    {"key": "geminiModel", "type": "string", "label": "Gemini Model", "group": "ai"},
    {"key": "geminiProxy", "type": "string", "label": "Gemini Proxy", "group": "ai"},
    {"key": "aiProvider", "type": "string", "label": "AI Provider", "group": "ai"},
    {"key": "aiBaseURL", "type": "string", "label": "AI Base URL", "group": "ai"},
    {"key": "aiApiKey", "type": "secret", "label": "AI API Key", "group": "ai"},
    {"key": "aiModel", "type": "string", "label": "AI Model", "group": "ai"},
    {"key": "historyLimit", "type": "int", "label": "History Limit", "group": "general"},
    {"key": "autoCopy", "type": "bool", "label": "Auto Copy", "group": "general"},
]

DEFAULT_SETTINGS = {
    "aliasPy": "py",
    "aliasDef": "def",
    "aliasAsk": "ask",
    "aliasSer": "ser",
    "pythonPath": DEFAULT_PYTHON,
    "scriptDirectory": "",
    "pluginDirectory": "",
    "enabledPlugins": "",
    "disabledPlugins": "",
    "geminiApiKey": "",
    "geminiModel": "gemini-1.5-flash",
    "geminiProxy": "",
    "aiProvider": "",
    "aiBaseURL": "",
    "aiApiKey": "",
    "aiModel": "",
    "historyLimit": 50,
    "autoCopy": False,
}

PACKAGE_ROOT = Path(__file__).resolve().parent
DEFAULTS_PATH = PACKAGE_ROOT / "config" / "defaults.json"
if not DEFAULTS_PATH.is_file():
    flattened_defaults = PACKAGE_ROOT / "defaults.json"
    if flattened_defaults.is_file():
        DEFAULTS_PATH = flattened_defaults
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "Commander"
USER_CONFIG_PATH = APP_SUPPORT_DIR / "config.json"
PLUGIN_DIR_PATH = APP_SUPPORT_DIR / "plugins"
