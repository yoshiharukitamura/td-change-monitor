from __future__ import annotations

import re

REDACTED_SECRET = "<REDACTED_SECRET>"

_SECRET_PATTERNS = (
    re.compile(r"https://hooks\.slack\.com/(?:services|workflows)/[^\s\"']+"),
    re.compile(r"\bxox[a-z]-[A-Za-z0-9-]{10,}\b"),
    re.compile(r"\bgh(?:p|o|u|s|r)_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    re.compile(r"\bsk_live_[0-9A-Za-z]{16,}\b"),
    re.compile(r"\bSG\.[0-9A-Za-z_-]{16,}\.[0-9A-Za-z_-]{16,}\b"),
    re.compile(
        r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
        r".*?"
        r"-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
        re.DOTALL,
    ),
)


def redact_detectable_secrets(content: str) -> str:
    """既知形式の秘密値を固定文字列へ置換する。

    引数:
        content: 検査対象のテキスト。
    戻り値:
        検出した秘密値を置換したテキスト。
    """
    redacted = content
    for pattern in _SECRET_PATTERNS:
        redacted = pattern.sub(REDACTED_SECRET, redacted)
    return redacted


def contains_detectable_secret(content: str) -> bool:
    """テキストに既知形式の秘密値が含まれるか判定する。

    引数:
        content: 検査対象のテキスト。
    戻り値:
        既知形式の秘密値が1件以上あればTrue。
    """
    return redact_detectable_secrets(content) != content
