"""handle.py 中 normalize_phone() 的单元测试。

[INPUT]: scripts/utils/handle.py 中的 normalize_phone()
[OUTPUT]: 号码格式化逻辑的完整测试覆盖
[POS]: 客户端 SDK 手机号处理的单元测试

[PROTOCOL]:
1. 逻辑变更时同步更新此头部
2. 更新后检查所在文件夹的 CLAUDE.md
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# 将 scripts/ 加入路径以便导入 utils.handle
_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

from utils.handle import normalize_phone  # noqa: E402


class TestNormalizePhone:
    """normalize_phone() 手机号格式化测试。"""

    # ---- 中国本地号码 → 自动加 +86 ----

    @pytest.mark.parametrize(
        ("raw", "expected"),
        [
            ("13800138000", "+8613800138000"),
            ("15912345678", "+8615912345678"),
            ("19999999999", "+8619999999999"),
        ],
    )
    def test_chinese_local_numbers(self, raw: str, expected: str) -> None:
        """中国本地号码应自动加 +86 前缀。"""
        assert normalize_phone(raw) == expected

    # ---- 已有国际格式 → 保持不变 ----

    @pytest.mark.parametrize(
        "phone",
        [
            "+8613800138000",
            "+14155552671",
            "+447911123456",
            "+81312345678",
            "+85212345678",
        ],
    )
    def test_international_format_unchanged(self, phone: str) -> None:
        """已有国际格式的号码应保持不变。"""
        assert normalize_phone(phone) == phone

    # ---- 前后空格 → 自动 strip ----

    def test_strips_whitespace(self) -> None:
        """应自动去除前后空格。"""
        assert normalize_phone("  13800138000  ") == "+8613800138000"
        assert normalize_phone(" +14155552671 ") == "+14155552671"

    # ---- 无效号码 → ValueError ----

    @pytest.mark.parametrize(
        "phone",
        [
            "12345",       # 太短
            "abc",         # 非数字
            "+abc",        # + 后非数字
            "",            # 空字符串
            "+1234",       # 国际格式但太短
            "99999999999", # 11 位但不是 1[3-9] 开头
        ],
    )
    def test_invalid_phone_raises(self, phone: str) -> None:
        """无效号码应抛出 ValueError。"""
        with pytest.raises(ValueError):
            normalize_phone(phone)
