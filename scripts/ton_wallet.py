"""
TON钱包管理脚本 - 优化版

一个功能完整、健壮的 TON 区块链钱包工具：
1. 支持创建/导入钱包、本地加密存储助记词
2. 支持查询余额、发送交易、查询交易历史和状态
3. 支持修改密码、导出助记词、查看钱包信息
4. 提供非交互式 CLI 子命令，方便脚本和命令行调用
"""
import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from enum import Enum

# 第三方库
from pytoniq import LiteBalancer
from pytoniq.contract.wallets.wallet import WalletV3R2, WalletV4R2
from pytoniq.contract.wallets.wallet_v5 import WalletV5R1
from pytoniq_core import Address
from pytoniq_core.crypto.keys import mnemonic_is_valid
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import base64

# awiki skill config
from utils.ton_config import TonConfig


def _load_ton_config() -> TonConfig:
    """Load TON configuration for this skill.

    Vendored version inside awiki-agent-id-message ignores any local config.json
    file and instead relies on <DATA_DIR>/config/ton_wallet.json (TonConfig).
    """
    return TonConfig.load()


# 支持的钱包合约版本映射
WALLET_CLASSES = {
    "v3r2": WalletV3R2,
    "v4r2": WalletV4R2,
    "v5r1": WalletV5R1,
}

SUPPORTED_VERSIONS = list(WALLET_CLASSES.keys())


def _get_wallet_class(version: str):
    """根据版本字符串返回对应的钱包类"""
    if version not in WALLET_CLASSES:
        raise ValueError(
            f"不支持的钱包版本: {version}\n"
            f"支持的版本: {', '.join(SUPPORTED_VERSIONS)}"
        )
    return WALLET_CLASSES[version]


# 一些常见的弱密码，直接禁止使用
COMMON_WEAK_PASSWORDS = {
    "123456",
    "1234567",
    "12345678",
    "123456789",
    "111111",
    "000000",
    "password",
    "password1",
    "qwerty",
    "abc123",
    "test123",
    "test1234",
}


def _validate_password_strength(password: str) -> None:
    """
    校验钱包密码强度，不追求极其严格，但避免明显弱口令。

    要求：
    1. 长度至少 8 个字符
    2. 不能全是空白字符
    3. 不能是常见弱密码（如 123456、password 等）
    4. 至少包含「字母、数字、符号」三类中的两类
    """
    if not isinstance(password, str) or not password:
        raise ValueError("密码不能为空")

    if len(password) < 8:
        raise ValueError("密码长度至少为8个字符")

    if password.strip() == "":
        raise ValueError("密码不能全部为空白字符")

    lower = password.lower()
    if lower in COMMON_WEAK_PASSWORDS:
        raise ValueError("密码过于简单，请更换为更复杂的密码（避免常见弱口令）")

    has_letter = any(ch.isalpha() for ch in password)
    has_digit = any(ch.isdigit() for ch in password)
    has_other = any(not ch.isalnum() for ch in password)
    categories = sum([has_letter, has_digit, has_other])

    if categories < 2:
        raise ValueError(
            "密码强度太弱，建议同时包含字母、数字或符号中的至少两种字符类型"
        )


class NetworkType(Enum):
    """网络类型"""
    MAINNET = "mainnet"
    TESTNET = "testnet"


class WalletError(Exception):
    """钱包相关错误的基类"""
    pass


class WalletNotInitializedError(WalletError):
    """钱包未初始化错误"""
    pass


class InsufficientBalanceError(WalletError):
    """余额不足错误"""
    pass


class WalletNotDeployedError(WalletError):
    """钱包未部署错误"""
    pass


class NetworkError(WalletError):
    """网络连接错误"""
    pass


class SecureStorage:
    """安全存储管理器"""

    def __init__(self, storage_dir: Optional[str] = None):
        """
        初始化存储管理器

        Args:
            storage_dir: 存储目录；在 awiki skill 中必须显式传入，外部 CLI 可选。
        """
        if storage_dir is None:
            # 为了兼容独立 CLI 使用，仍然提供一个合理的默认路径。
            # 在 awiki skill 中，调用方应始终显式传入 per-credential 路径。
            storage_dir = "~/.ton_wallet"

        self.storage_dir = Path(os.path.expanduser(storage_dir))
        self.wallet_file = self.storage_dir / "wallet.enc"

    def save_wallet(self, mnemonic: str, password: str,
                    address: Optional[str] = None,
                    wallet_version: Optional[str] = None) -> None:
        """
        使用 AES-256-GCM 加密并保存助记词

        Args:
            mnemonic: 助记词字符串
            password: 加密密码
            address: 钱包地址（明文存储，可选）
            wallet_version: 钱包合约版本（如 v4r2，可选）

        Raises:
            WalletError: 保存失败时抛出
        """
        if not mnemonic or not mnemonic.strip():
            raise ValueError("助记词不能为空")

        # 统一的密码强度校验
        _validate_password_strength(password)

        try:
            # 确保目录在写入前已创建
            self.storage_dir.mkdir(parents=True, exist_ok=True)
            # 生成随机盐（32字节）
            salt = os.urandom(32)

            # 从密码派生 AES-256 密钥
            kdf = PBKDF2HMAC(
                algorithm=hashes.SHA256(),
                length=32,
                salt=salt,
                iterations=100000,
            )
            key = kdf.derive(password.encode())

            # AES-256-GCM 加密
            nonce = os.urandom(12)
            aesgcm = AESGCM(key)
            ciphertext = aesgcm.encrypt(nonce, mnemonic.encode(), None)

            # 保存到文件（为简化起见，不再维护文件格式版本号，仅保留必要字段）
            data = {
                "salt": base64.b64encode(salt).decode(),
                "nonce": base64.b64encode(nonce).decode(),
                "ciphertext": base64.b64encode(ciphertext).decode(),
                "address": address,
                "wallet_version": wallet_version,
            }

            with open(self.wallet_file, "w") as file:
                json.dump(data, file, indent=2)

        except (ValueError, WalletError):
            raise
        except Exception as e:
            raise WalletError(f"保存钱包文件失败: {e}")

    def load_wallet(self, password: str) -> str:
        """
        使用 AES-256-GCM 解密并加载助记词

        Args:
            password: 解密密码

        Returns:
            助记词字符串

        Raises:
            FileNotFoundError: 钱包文件不存在
            ValueError: 密码错误
            WalletError: 其他错误
        """
        if not self.wallet_file.exists():
            raise FileNotFoundError(
                f"钱包文件不存在: {self.wallet_file}\n"
                f"请先使用 create_new_wallet() 创建钱包"
            )

        try:
            with open(self.wallet_file, "r") as file:
                data = json.load(file)
        except json.JSONDecodeError as e:
            raise WalletError(f"钱包文件格式错误: {e}")
        except Exception as e:
            raise WalletError(f"读取钱包文件失败: {e}")

        try:
            salt = base64.b64decode(data["salt"])
            nonce = base64.b64decode(data["nonce"])
            ciphertext = base64.b64decode(data["ciphertext"])
        except KeyError as e:
            raise WalletError(f"钱包文件缺少必要字段: {e}")
        except Exception as e:
            raise WalletError(f"解析钱包文件失败: {e}")

        # 从密码派生密钥
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000,
        )
        key = kdf.derive(password.encode())

        # AES-256-GCM 解密
        try:
            aesgcm = AESGCM(key)
            mnemonic = aesgcm.decrypt(nonce, ciphertext, None).decode()
            return mnemonic
        except Exception:
            raise ValueError(
                "密码错误或文件已损坏\n"
                "请确认密码正确，或检查钱包文件是否完整"
            )

    def wallet_exists(self) -> bool:
        """检查钱包文件是否存在"""
        return self.wallet_file.exists()

    def delete_wallet(self) -> None:
        """删除钱包文件"""
        if self.wallet_file.exists():
            try:
                self.wallet_file.unlink()
            except Exception as e:
                raise WalletError(f"删除钱包文件失败: {e}")

    def get_wallet_metadata(self) -> Optional[Dict[str, Any]]:
        """
        读取钱包元数据（无需密码）

        Returns:
            包含 address 和 wallet_version 的字典，文件不存在时返回 None
        """
        if not self.wallet_file.exists():
            return None
        try:
            with open(self.wallet_file, "r") as f:
                data = json.load(f)
            return {
                "address": data.get("address"),
                "wallet_version": data.get("wallet_version"),
            }
        except Exception:
            return None


class TonWallet:
    """
    TON钱包类

    提供完整的TON钱包功能，包括创建、加载、转账、查询等
    """

    # 重试配置
    MAX_RETRIES = 3
    RETRY_DELAY = 2  # 秒

    def __init__(
        self,
        network: Optional[NetworkType] = None,
        api_endpoint: Optional[str] = None,
        storage_dir: Optional[str] = None
    ):
        """
        初始化TON钱包

        Args:
            network: 网络类型（主网或测试网），为 None 时从 TonConfig 的 "network" 字段读取
            api_endpoint: 自定义API端点（可选），当前未使用，保留作为扩展
            storage_dir: 钱包文件存储目录（可选，在 awiki skill 中应显式传入）
        """
        ton_cfg = _load_ton_config()

        if network is None:
            # TonConfig 中使用字符串 "mainnet"/"testnet"
            network_name = ton_cfg.network
            try:
                network = NetworkType(network_name)
            except ValueError:
                network = NetworkType.MAINNET

        self.network = network

        # 目前 LiteBalancer 使用内置 mainnet/testnet 配置，api_endpoint 预留为未来扩展
        self.api_endpoint = api_endpoint
        self.storage = SecureStorage(storage_dir=storage_dir)
        self.mnemonic: Optional[List[str]] = None
        self.wallet = None
        self.wallet_version: Optional[str] = None
        self.client: Optional[LiteBalancer] = None
        # 默认预留的手续费（单位：TON），由 TonConfig 控制
        # 如果配置缺失或非法，则在 TonConfig 内部回退到 0.01 TON，保证行为可预期
        self.fee_reserve: float = max(float(ton_cfg.default_fee_reserve), 0.0)

    async def create_new_wallet(self, password: str,
                               wallet_version: Optional[str] = None) -> List[str]:
        """
        创建新钱包并保存

        Args:
            password: 用于加密保存的密码（至少8个字符，且建议包含字母和数字）
            wallet_version: 钱包合约版本，默认从 config.json 读取，再 fallback 到 "v4r2"

        Returns:
            24个单词的助记词列表

        Raises:
            ValueError: 钱包已存在或密码不符合要求
            NetworkError: 网络连接失败
            WalletError: 其他错误
        """
        if self.storage.wallet_exists():
            raise ValueError(
                "钱包已存在\n"
                f"钱包文件位置: {self.storage.wallet_file}\n"
                "请先删除旧钱包或使用 load_wallet() 加载现有钱包"
            )

        # 确定钱包版本：传参 > TonConfig > 默认 v4r2
        if wallet_version is None:
            ton_cfg = _load_ton_config()
            wallet_version = ton_cfg.default_wallet_version or "v4r2"
        wallet_cls = _get_wallet_class(wallet_version)

        # 初始化网络客户端
        await self._init_client()

        try:
            mnemonics, wallet = await wallet_cls.create(
                self.client,
                wc=0,
                version=wallet_version
            )
            self.mnemonic = mnemonics
            self.wallet = wallet
            self.wallet_version = wallet_version

            # 计算钱包地址
            address = wallet.address.to_str(
                is_bounceable=True,
                is_test_only=(self.network == NetworkType.TESTNET)
            )

            # 保存加密的助记词（含地址和合约版本）
            mnemonic_str = " ".join(mnemonics)
            self.storage.save_wallet(mnemonic_str, password,
                                     address=address,
                                     wallet_version=wallet_version)

            return mnemonics

        except (ValueError, WalletError):
            raise
        except Exception as e:
            raise WalletError(f"创建钱包失败: {e}")

    async def load_wallet(self, password: str) -> None:
        """
        从加密文件加载钱包

        Args:
            password: 解密密码

        Raises:
            FileNotFoundError: 钱包文件不存在
            ValueError: 密码错误
            NetworkError: 网络连接失败
            WalletError: 其他错误
        """
        # 读取存储的钱包版本
        metadata = self.storage.get_wallet_metadata()
        wallet_version = (metadata.get("wallet_version") or "v4r2") if metadata else "v4r2"
        wallet_cls = _get_wallet_class(wallet_version)

        # 加载并解密助记词
        mnemonic_str = self.storage.load_wallet(password)
        mnemonics = mnemonic_str.split()

        if len(mnemonics) != 24:
            raise WalletError(
                f"助记词格式错误: 期望24个单词，实际{len(mnemonics)}个"
            )

        self.mnemonic = mnemonics
        self.wallet_version = wallet_version

        # 初始化网络客户端
        await self._init_client()

        try:
            kwargs = dict(wc=0)
            if wallet_cls is WalletV5R1:
                kwargs["network_global_id"] = -3 if self.network == NetworkType.TESTNET else -239
            self.wallet = await wallet_cls.from_mnemonic(
                self.client,
                mnemonics,
                **kwargs
            )
        except Exception as e:
            raise WalletError(f"从助记词恢复钱包失败: {e}")

    async def import_wallet(
        self,
        mnemonics: List[str],
        password: str,
        wallet_version: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        从助记词恢复已有钱包

        Args:
            mnemonics: 24个单词的助记词列表
            password: 加密密码（至少8个字符，且建议包含字母和数字）
            wallet_version: 钱包合约版本。为 None 时自动探测链上版本。

        Returns:
            钱包信息字典: { address, wallet_version, is_deployed, balance }

        Raises:
            ValueError: 助记词无效、密码不符合要求、钱包已存在
            NetworkError: 网络连接失败
            WalletError: 其他错误
        """
        if self.storage.wallet_exists():
            raise ValueError(
                "钱包已存在\n"
                f"钱包文件位置: {self.storage.wallet_file}\n"
                "请先删除旧钱包或使用 load_wallet() 加载现有钱包"
            )

        # 验证助记词
        if len(mnemonics) != 24:
            raise ValueError(f"助记词格式错误: 期望24个单词，实际{len(mnemonics)}个")

        if not mnemonic_is_valid(mnemonics):
            raise ValueError("助记词无效，请检查单词拼写是否正确")

        # 初始化网络客户端
        await self._init_client()

        if wallet_version is not None:
            # 手动指定版本，直接恢复
            wallet_cls = _get_wallet_class(wallet_version)
            kwargs = dict(wc=0)
            if wallet_cls is WalletV5R1:
                kwargs["network_global_id"] = -3 if self.network == NetworkType.TESTNET else -239
            wallet = await wallet_cls.from_mnemonic(self.client, mnemonics, **kwargs)
        else:
            # 自动探测：逐版本查链上状态
            wallet, wallet_version = await self._detect_wallet_version(mnemonics)

        self.mnemonic = mnemonics
        self.wallet = wallet
        self.wallet_version = wallet_version

        # 计算地址
        address = wallet.address.to_str(
            is_bounceable=True,
            is_test_only=(self.network == NetworkType.TESTNET)
        )

        # 查询链上信息
        try:
            account = await self.client.get_account_state(wallet.address)
            is_deployed = account.state.type_ == 'active'
            balance = account.balance / 1_000_000_000
        except Exception:
            is_deployed = False
            balance = 0.0

        # 加密保存
        mnemonic_str = " ".join(mnemonics)
        self.storage.save_wallet(mnemonic_str, password,
                                 address=address,
                                 wallet_version=wallet_version)

        return {
            "address": address,
            "wallet_version": wallet_version,
            "is_deployed": is_deployed,
            "balance": balance,
        }

    async def _detect_wallet_version(
        self, mnemonics: List[str]
    ) -> Tuple[Any, str]:
        """
        自动探测助记词对应的钱包合约版本

        逐版本推导地址并查链上状态，返回已部署或有余额的版本。

        Returns:
            (wallet_object, version_string)

        Raises:
            WalletError: 未探测到任何链上钱包
        """
        matches = []

        for version, wallet_cls in WALLET_CLASSES.items():
            try:
                kwargs = dict(wc=0)
                if wallet_cls is WalletV5R1:
                    kwargs["network_global_id"] = -3 if self.network == NetworkType.TESTNET else -239
                wallet = await wallet_cls.from_mnemonic(
                    self.client, mnemonics, **kwargs
                )
                account = await self.client.get_account_state(wallet.address)
                is_deployed = account.state.type_ == 'active'
                balance = account.balance

                if is_deployed or balance > 0:
                    matches.append((wallet, version, is_deployed, balance))
            except Exception:
                continue

        if not matches:
            raise WalletError(
                "未在链上找到与此助记词关联的钱包\n"
                "可能原因：\n"
                "1. 助记词对应的钱包从未使用过（无部署、无余额）\n"
                "2. 当前网络（主网/测试网）与钱包所在网络不一致\n"
                "请尝试手动指定版本：import_wallet(mnemonics, password, wallet_version='v4r2')"
            )

        # 优先选已部署的，其次选余额最高的
        deployed = [m for m in matches if m[2]]
        if deployed:
            wallet, version, _, _ = deployed[0]
        else:
            wallet, version, _, _ = matches[0]

        return wallet, version

    async def _init_client(self) -> None:
        """
        初始化网络客户端（带重试机制）

        Raises:
            NetworkError: 网络连接失败
        """
        is_testnet = self.network == NetworkType.TESTNET

        for attempt in range(self.MAX_RETRIES):
            try:
                if is_testnet:
                    self.client = LiteBalancer.from_testnet_config(
                        trust_level=2,
                        timeout=10
                    )
                else:
                    self.client = LiteBalancer.from_mainnet_config(
                        trust_level=2,
                        timeout=10
                    )

                await self.client.start_up()
                return  # 成功连接

            except Exception as e:
                if attempt < self.MAX_RETRIES - 1:
                    await asyncio.sleep(self.RETRY_DELAY)
                    continue
                else:
                    network_name = "测试网" if is_testnet else "主网"
                    raise NetworkError(
                        f"连接到TON {network_name}失败（尝试{self.MAX_RETRIES}次）: {e}\n"
                        f"请检查网络连接或稍后重试"
                    )

    def _ensure_initialized(self) -> None:
        """
        确保钱包已初始化

        Raises:
            WalletNotInitializedError: 钱包未初始化
        """
        if not self.wallet or not self.client:
            raise WalletNotInitializedError(
                "钱包未初始化\n"
                "请先使用 create_new_wallet() 创建钱包或 load_wallet() 加载钱包"
            )

    def get_address(self, bounceable: bool = True) -> str:
        """
        获取钱包地址

        Args:
            bounceable: 是否返回可弹回地址
                       True: 返回 EQ.../kQ... 格式（用于已部署的钱包）
                       False: 返回 UQ.../0Q... 格式（用于未部署的钱包）

        Returns:
            钱包地址字符串

        Raises:
            WalletNotInitializedError: 钱包未初始化
        """
        self._ensure_initialized()

        address = self.wallet.address.to_str(
            is_bounceable=bounceable,
            is_test_only=(self.network == NetworkType.TESTNET)
        )
        return address

    async def is_deployed(self) -> bool:
        """
        检查钱包是否已部署到区块链

        Returns:
            True: 已部署，False: 未部署

        Raises:
            WalletNotInitializedError: 钱包未初始化
            NetworkError: 网络查询失败
        """
        self._ensure_initialized()

        try:
            account = await self.client.get_account_state(self.wallet.address)
            return account.state.type_ == 'active'
        except Exception as e:
            raise NetworkError(f"查询钱包部署状态失败: {e}")

    async def check_destination_deployed(self, destination: str) -> bool:
        """
        检查目标地址是否已部署

        Args:
            destination: 目标地址

        Returns:
            True: 已部署，False: 未部署
        """
        self._ensure_initialized()

        try:
            dest_address = Address(destination)
            account = await self.client.get_account_state(dest_address)
            return account.state.type_ == 'active'
        except Exception as e:
            # 这里将查询失败视为网络错误而不是「未部署」，避免静默降级掩盖问题
            raise NetworkError(f"查询目标地址部署状态失败: {e}")

    async def deploy(self, wait_confirmation: bool = True) -> str:
        """
        部署钱包到区块链

        Args:
            wait_confirmation: 是否等待部署确认（默认True）

        Returns:
            部署结果消息

        Raises:
            WalletNotInitializedError: 钱包未初始化
            WalletError: 部署失败
        """
        self._ensure_initialized()

        # 检查是否已部署
        if await self.is_deployed():
            return "钱包已经部署"

        # 检查余额
        balance = await self.get_balance()
        if balance <= 0:
            raise WalletError(
                "钱包余额为0，无法部署\n"
                "请先向钱包地址发送一些TON（使用non-bounceable地址）"
            )

        try:
            # 发送部署交易
            await self.wallet.send_init_external()

            if wait_confirmation:
                # 等待部署确认
                await asyncio.sleep(10)

                # 检查是否部署成功
                if await self.is_deployed():
                    return "钱包部署成功"
                else:
                    return "钱包部署交易已提交，等待确认中"
            else:
                return "钱包部署交易已提交"

        except Exception as e:
            raise WalletError(f"部署钱包失败: {e}")

    async def ensure_deployed(self) -> None:
        """
        确保钱包已部署，如果未部署则自动部署

        Raises:
            WalletNotInitializedError: 钱包未初始化
            WalletError: 部署失败
        """
        if not await self.is_deployed():
            result = await self.deploy(wait_confirmation=True)
            if "成功" not in result and "已经部署" not in result:
                # 再等待一段时间
                await asyncio.sleep(5)
                if not await self.is_deployed():
                    raise WalletError("钱包部署失败，请稍后重试")

    def format_balance(self, balance: float) -> str:
        """
        格式化余额显示（保留6位小数）

        Args:
            balance: 余额（TON）

        Returns:
            格式化后的余额字符串
        """
        return f"{balance:.6f}"

    async def get_balance(self, formatted: bool = False) -> float:
        """
        获取钱包余额

        Args:
            formatted: 是否返回格式化的字符串（保留6位小数）

        Returns:
            余额（单位：TON）

        Raises:
            WalletNotInitializedError: 钱包未初始化
            NetworkError: 网络查询失败
        """
        self._ensure_initialized()

        try:
            account_state = await self.client.get_account_state(self.wallet.address)
            balance_nano = account_state.balance
            balance = balance_nano / 1_000_000_000

            if formatted:
                return self.format_balance(balance)
            return balance

        except Exception as e:
            raise NetworkError(f"查询余额失败: {e}")

    async def get_max_sendable_amount(self, fee_reserve: Optional[float] = None) -> float:
        """
        计算在预留手续费的前提下，可安全发送的最大金额

        Args:
            fee_reserve: 预留的手续费（TON），不传则使用钱包默认配置

        Returns:
            可发送的最大金额（TON），若余额不足以覆盖预留手续费则返回0
        """
        self._ensure_initialized()

        reserve = self.fee_reserve if fee_reserve is None else max(float(fee_reserve), 0.0)
        balance = await self.get_balance()
        max_amount = balance - reserve
        return max_amount if max_amount > 0 else 0.0

    async def send_ton(
        self,
        destination: str,
        amount: float,
        comment: Optional[str] = None,
        auto_deploy: bool = True,
        auto_detect_bounce: bool = True,
        wait_for_confirmation: bool = False,
        confirmation_timeout: int = 60,
        confirmation_check_interval: int = 5,
    ) -> Dict[str, Any]:
        """
        发送TON代币（优化版）

        Args:
            destination: 目标地址
            amount: 发送数量（单位：TON）
            comment: 转账备注（可选）
            auto_deploy: 是否自动部署钱包（默认True）
            auto_detect_bounce: 是否自动检测目标地址并选择合适的地址格式（默认True）
            wait_for_confirmation: 是否等待交易被链上确认（默认False）
            confirmation_timeout: 等待确认的超时时间（秒）
            confirmation_check_interval: 轮询确认状态的时间间隔（秒）

        Returns:
            包含交易信息的字典：
            {
                "success": bool,
                "message": str,
                "amount": float,
                "destination": str,
                "balance_before": float,
                "balance_after": float,
                "fee_estimated": float,
                "tx_hash": Optional[str],
                "confirmed": bool,
            }

        Raises:
            WalletNotInitializedError: 钱包未初始化
            InsufficientBalanceError: 余额不足
            WalletNotDeployedError: 钱包未部署且auto_deploy=False
            NetworkError: 网络查询失败
            WalletError: 其他错误
        """
        self._ensure_initialized()

        # 0. 基本参数校验
        if amount <= 0:
            raise ValueError("转账金额必须大于 0")

        if confirmation_timeout <= 0 or confirmation_check_interval <= 0:
            raise ValueError("confirmation_timeout 和 confirmation_check_interval 必须为正数")

        # 预先记录当前最新交易的数量和时间，用于后续确认新交易是否上链
        initial_count = 0
        initial_time = 0
        try:
            initial_txs = await self.get_transactions(limit=1, formatted=False)
            initial_count = len(initial_txs)
            initial_time = initial_txs[0]["time"] if initial_txs else 0
        except Exception:
            # 仅用于确认逻辑，失败时不影响发送流程本身
            initial_count = 0
            initial_time = 0

        # 1. 检查余额
        balance_before = await self.get_balance()
        if balance_before < amount:
            raise InsufficientBalanceError(
                f"余额不足\n"
                f"当前余额: {self.format_balance(balance_before)} TON\n"
                f"需要金额: {self.format_balance(amount)} TON\n"
                f"缺少: {self.format_balance(amount - balance_before)} TON"
            )

        # 预留gas费用检查，使用配置中的预留手续费
        estimated_fee = self.fee_reserve
        if balance_before < amount + estimated_fee:
            raise InsufficientBalanceError(
                f"余额不足（需要预留gas费用）\n"
                f"当前余额: {self.format_balance(balance_before)} TON\n"
                f"转账金额: {self.format_balance(amount)} TON\n"
                f"预估手续费: {self.format_balance(estimated_fee)} TON\n"
                f"建议保留至少 {self.format_balance(amount + estimated_fee)} TON"
            )

        # 2. 确保钱包已部署
        if auto_deploy:
            await self.ensure_deployed()
        else:
            if not await self.is_deployed():
                raise WalletNotDeployedError(
                    "钱包未部署，无法发送交易\n"
                    "请先调用 deploy() 部署钱包，或设置 auto_deploy=True"
                )

        # 3. 智能选择目标地址格式
        final_destination = destination
        if auto_detect_bounce:
            is_dest_deployed = await self.check_destination_deployed(destination)
            if not is_dest_deployed:
                # 目标未部署，使用non-bounceable地址
                try:
                    dest_addr = Address(destination)
                    final_destination = dest_addr.to_str(
                        is_bounceable=False,
                        is_test_only=(self.network == NetworkType.TESTNET)
                    )
                except Exception:
                    # 如果转换失败，使用原地址
                    pass

        # 4. 转换金额为nanoTON
        amount_nano = int(amount * 1_000_000_000)

        # 5. 发送交易
        tx_hash: Optional[str] = None
        confirmed = False
        try:
            if comment:
                await self.wallet.transfer(
                    destination=final_destination,
                    amount=amount_nano,
                    body=comment
                )
            else:
                await self.wallet.transfer(
                    destination=final_destination,
                    amount=amount_nano
                )

            # 等待一小段时间让交易提交
            await asyncio.sleep(2)

            # 如有需要，等待交易确认（检测是否产生新的交易记录）
            if wait_for_confirmation:
                try:
                    confirmed = await self.wait_for_transaction(
                        timeout=confirmation_timeout,
                        check_interval=confirmation_check_interval,
                        initial_count=initial_count,
                        initial_time=initial_time,
                    )
                except Exception:
                    confirmed = False

            # 再次查询余额
            balance_after = await self.get_balance()

            # 尝试抓取最新一笔交易的哈希（尽力而为，不作为失败条件）
            try:
                recent_txs = await self.get_transactions(limit=1, formatted=False)
                if recent_txs:
                    tx_hash = recent_txs[0]["hash"]
            except Exception:
                tx_hash = None

            return {
                "success": True,
                "message": "交易已提交" if not wait_for_confirmation or confirmed else "交易已提交，确认超时",
                "amount": amount,
                "destination": final_destination,
                "balance_before": balance_before,
                "balance_after": balance_after,
                "fee_estimated": balance_before - balance_after - amount,
                "tx_hash": tx_hash,
                "confirmed": confirmed,
            }

        except Exception as e:
            raise WalletError(f"发送交易失败: {e}")

    async def wait_for_transaction(
        self,
        timeout: int = 60,
        check_interval: int = 5,
        initial_count: Optional[int] = None,
        initial_time: Optional[int] = None,
    ) -> bool:
        """
        等待交易确认

        Args:
            timeout: 超时时间（秒）
            check_interval: 检查间隔（秒）

        Returns:
            True: 检测到新交易，False: 超时
        """
        self._ensure_initialized()

        # 获取当前交易数量（如果调用方未预先提供基准值）
        if initial_count is None or initial_time is None:
            try:
                initial_txs = await self.get_transactions(limit=1)
                initial_count = len(initial_txs)
                initial_time = initial_txs[0]['time'] if initial_txs else 0
            except Exception:
                initial_count = 0
                initial_time = 0

        elapsed = 0
        while elapsed < timeout:
            await asyncio.sleep(check_interval)
            elapsed += check_interval

            try:
                current_txs = await self.get_transactions(limit=1)
                if len(current_txs) > initial_count:
                    return True
                if current_txs and current_txs[0]['time'] > initial_time:
                    return True
            except Exception:
                continue

        return False

    async def get_transactions(
        self,
        limit: int = 10,
        formatted: bool = True
    ) -> List[Dict[str, Any]]:
        """
        获取交易历史（优化版）

        Args:
            limit: 返回的交易数量限制
            formatted: 是否格式化金额显示

        Returns:
            交易列表，每个交易包含：
            {
                "hash": str,
                "time": int,
                "in_msg": {
                    "source": str,
                    "value": float
                } or None,
                "out_msgs": [
                    {
                        "destination": str,
                        "value": float
                    }
                ]
            }

        Raises:
            WalletNotInitializedError: 钱包未初始化
            NetworkError: 网络查询失败
        """
        self._ensure_initialized()

        try:
            transactions = await self.client.get_transactions(
                address=self.wallet.address,
                count=limit
            )
        except AttributeError as e:
            # 钱包未部署，没有交易历史
            if "'NoneType' object has no attribute" in str(e):
                return []
            raise NetworkError(f"查询交易历史失败: {e}")
        except Exception as e:
            raise NetworkError(f"查询交易历史失败: {e}")

        result = []
        for tx in transactions:
            tx_info = {
                "hash": tx.cell.hash.hex(),
                "time": tx.now,
                "in_msg": None,
                "out_msgs": []
            }

            # 处理入账消息
            if tx.in_msg:
                # 检查消息类型，只有InternalMsgInfo才有value_coins
                if hasattr(tx.in_msg.info, 'value_coins'):
                    value = tx.in_msg.info.value_coins / 1_000_000_000
                    tx_info["in_msg"] = {
                        "source": (
                            tx.in_msg.info.src.to_str()
                            if hasattr(tx.in_msg.info, 'src') and tx.in_msg.info.src
                            else None
                        ),
                        "value": self.format_balance(value) if formatted else value,
                    }

            # 处理出账消息
            for out_msg in tx.out_msgs:
                if hasattr(out_msg.info, 'value_coins'):
                    value = out_msg.info.value_coins / 1_000_000_000
                    tx_info["out_msgs"].append({
                        "destination": (
                            out_msg.info.dest.to_str()
                            if hasattr(out_msg.info, 'dest') and out_msg.info.dest
                            else None
                        ),
                        "value": self.format_balance(value) if formatted else value,
                    })

            result.append(tx_info)

        return result

    async def get_transaction_status(self, tx_hash: str) -> Dict[str, Any]:
        """
        查询特定交易的状态

        Args:
            tx_hash: 交易哈希

        Returns:
            交易状态信息
        """
        self._ensure_initialized()

        try:
            # 获取最近的交易
            transactions = await self.get_transactions(limit=50, formatted=False)

            for tx in transactions:
                if tx['hash'] == tx_hash or tx['hash'].startswith(tx_hash):
                    return {
                        "found": True,
                        "confirmed": True,
                        "transaction": tx
                    }

            return {
                "found": False,
                "confirmed": False,
                "message": "交易未找到或尚未确认"
            }

        except Exception as e:
            raise NetworkError(f"查询交易状态失败: {e}")

    async def activate_wallet(
        self,
        destination: str,
        amount: float = 0.5
    ) -> Dict[str, Any]:
        """
        激活一个未部署的钱包（辅助方法）

        向目标地址发送TON以激活它

        Args:
            destination: 目标钱包地址
            amount: 发送金额（默认0.5 TON）

        Returns:
            交易结果
        """
        # 强制使用non-bounceable地址
        try:
            dest_addr = Address(destination)
            non_bounce_addr = dest_addr.to_str(
                is_bounceable=False,
                is_test_only=(self.network == NetworkType.TESTNET)
            )
        except Exception as e:
            raise ValueError(f"无效的目标地址: {e}")

        return await self.send_ton(
            destination=non_bounce_addr,
            amount=amount,
            comment="激活钱包",
            auto_deploy=True,
            auto_detect_bounce=False  # 已经手动设置为non-bounceable
        )

    async def close(self) -> None:
        """关闭网络连接"""
        if self.client:
            try:
                await self.client.close_all()
            except Exception:
                pass  # 忽略关闭时的错误

    def delete_wallet_file(self) -> None:
        """
        删除本地钱包文件

        警告：此操作不可恢复，请确保已备份助记词
        """
        self.storage.delete_wallet()
        self.mnemonic = None
        self.wallet = None

    def get_wallet_info(self) -> Dict[str, Any]:
        """
        获取钱包信息摘要

        Returns:
            钱包信息字典
        """
        if not self.wallet:
            metadata = self.storage.get_wallet_metadata()
            return {
                "initialized": False,
                "message": "钱包未初始化",
                "stored_address": metadata.get("address") if metadata else None,
                "wallet_version": metadata.get("wallet_version") if metadata else None,
            }

        return {
            "initialized": True,
            "network": self.network.value,
            "address_bounceable": self.get_address(bounceable=True),
            "address_non_bounceable": self.get_address(bounceable=False),
            "wallet_version": self.wallet_version,
            "storage_dir": str(self.storage.storage_dir),
            "wallet_file": str(self.storage.wallet_file)
        }

    def get_address_offline(self) -> Optional[str]:
        """获取钱包地址（无需密码，从本地文件读取）"""
        metadata = self.storage.get_wallet_metadata()
        return metadata.get("address") if metadata else None

    def get_wallet_info_offline(self) -> Optional[Dict[str, Any]]:
        """获取本地存储的钱包信息（无需密码、无需网络）"""
        return self.storage.get_wallet_metadata()

    def export_mnemonic(self, password: str) -> List[str]:
        """
        查看助记词（需要密码）

        Args:
            password: 解密密码

        Returns:
            24个单词的助记词列表

        Raises:
            FileNotFoundError: 钱包文件不存在
            ValueError: 密码错误
        """
        mnemonic_str = self.storage.load_wallet(password)
        return mnemonic_str.split()

    def change_password(self, old_password: str, new_password: str) -> None:
        """
        修改钱包加密密码

        Args:
            old_password: 当前密码
            new_password: 新密码（至少8个字符，且建议包含字母和数字）

        Raises:
            FileNotFoundError: 钱包文件不存在
            ValueError: 旧密码错误或新密码不符合要求
        """
        # 用旧密码解密
        mnemonic_str = self.storage.load_wallet(old_password)

        # 读取当前元数据
        metadata = self.storage.get_wallet_metadata()
        address = metadata.get("address") if metadata else None
        wallet_version = metadata.get("wallet_version") if metadata else None

        # 用新密码重新加密保存
        self.storage.save_wallet(mnemonic_str, new_password,
                                 address=address,
                                 wallet_version=wallet_version)


# =========================
# CLI 封装
# =========================

def _build_wallet_from_args(args: argparse.Namespace) -> TonWallet:
    """
    根据命令行参数构造 TonWallet 实例。

    network/storage_dir 都是可选的，未指定时走 config.json 默认值。
    """
    network: Optional[NetworkType] = None
    if getattr(args, "network", None):
        network = NetworkType(args.network)

    storage_dir = getattr(args, "storage_dir", None)
    return TonWallet(network=network, storage_dir=storage_dir)


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ton_wallet",
        description="TON 钱包命令行工具（非交互式）"
    )

    # 全局选项：网络与存储目录
    parser.add_argument(
        "--network",
        choices=[n.value for n in NetworkType],
        help="覆盖 config.json 中的网络配置（mainnet/testnet）"
    )
    parser.add_argument(
        "--storage-dir",
        help="钱包存储目录（默认从 config.json 的 wallet_storage_dir 读取）"
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # create: 创建新钱包
    p_create = subparsers.add_parser("create", help="创建新钱包")
    p_create.add_argument(
        "--password",
        required=True,
        help="用于加密保存钱包的密码（至少8个字符，建议包含字母与数字）"
    )
    p_create.add_argument(
        "--wallet-version",
        choices=SUPPORTED_VERSIONS,
        help="钱包合约版本，默认从 config.json 的 default_wallet_version 读取"
    )

    # import: 从助记词恢复钱包
    p_import = subparsers.add_parser("import", help="从助记词恢复钱包")
    group_mnemo = p_import.add_mutually_exclusive_group(required=True)
    group_mnemo.add_argument(
        "--mnemonic",
        help="24 个英文单词的助记词，使用空格分隔"
    )
    group_mnemo.add_argument(
        "--mnemonic-file",
        help="包含助记词的文本文件路径（单行或多行都会按空格拆分）"
    )
    p_import.add_argument(
        "--password",
        required=True,
        help="用于加密保存钱包的密码（至少8个字符，建议包含字母与数字）"
    )
    p_import.add_argument(
        "--wallet-version",
        choices=SUPPORTED_VERSIONS,
        help="钱包合约版本，为空时自动探测链上版本"
    )

    # info: 查看钱包信息（离线/在线）
    p_info = subparsers.add_parser("info", help="查看钱包信息")
    p_info.add_argument(
        "--password",
        help="在线模式需要密码；不提供则仅返回离线信息"
    )

    # balance: 查询余额
    p_balance = subparsers.add_parser("balance", help="查询钱包余额")
    p_balance.add_argument(
        "--password",
        required=True,
        help="钱包密码"
    )
    p_balance.add_argument(
        "--formatted",
        action="store_true",
        help="是否以格式化字符串返回余额（保留6位小数）"
    )

    # send: 发送 TON
    p_send = subparsers.add_parser("send", help="发送 TON 代币")
    p_send.add_argument(
        "--password",
        required=True,
        help="发送方钱包密码"
    )
    p_send.add_argument(
        "--to",
        required=True,
        help="接收方地址（支持 bounceable 或 non-bounceable 格式）"
    )
    p_send.add_argument(
        "--amount",
        type=float,
        required=True,
        help="发送数量（单位：TON）"
    )
    p_send.add_argument(
        "--comment",
        help="转账备注（可选）"
    )
    p_send.add_argument(
        "--no-auto-deploy",
        dest="auto_deploy",
        action="store_false",
        help="关闭自动部署钱包（默认开启）"
    )
    p_send.set_defaults(auto_deploy=True)
    p_send.add_argument(
        "--no-auto-detect-bounce",
        dest="auto_detect_bounce",
        action="store_false",
        help="关闭自动检测目标地址部署状态（默认开启）"
    )
    p_send.set_defaults(auto_detect_bounce=True)
    p_send.add_argument(
        "--wait",
        dest="wait_for_confirmation",
        action="store_true",
        help="发送后等待交易确认（默认只提交不等待）"
    )
    p_send.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="等待确认的最长时间（秒），默认 60"
    )
    p_send.add_argument(
        "--check-interval",
        type=int,
        default=5,
        help="轮询确认状态的时间间隔（秒），默认 5"
    )

    # tx-history: 查询交易历史
    p_txs = subparsers.add_parser("tx-history", help="查询交易历史")
    p_txs.add_argument(
        "--password",
        required=True,
        help="钱包密码"
    )
    p_txs.add_argument(
        "--limit",
        type=int,
        default=10,
        help="查询的交易数量（默认 10）"
    )
    p_txs.add_argument(
        "--formatted",
        action="store_true",
        help="是否格式化金额显示"
    )

    # tx-status: 查询单笔交易状态
    p_tx_status = subparsers.add_parser("tx-status", help="查询单笔交易状态")
    p_tx_status.add_argument(
        "--password",
        required=True,
        help="钱包密码"
    )
    p_tx_status.add_argument(
        "--hash",
        required=True,
        help="交易哈希（可使用前缀）"
    )

    # export-mnemonic: 导出助记词
    p_export = subparsers.add_parser("export-mnemonic", help="导出助记词（需要密码）")
    p_export.add_argument(
        "--password",
        required=True,
        help="钱包密码"
    )

    # change-password: 修改钱包密码
    p_chpw = subparsers.add_parser("change-password", help="修改钱包密码")
    p_chpw.add_argument(
        "--old-password",
        required=True,
        help="当前密码"
    )
    p_chpw.add_argument(
        "--new-password",
        required=True,
        help="新密码（至少8个字符，建议包含字母与数字）"
    )

    # delete-wallet: 删除本地钱包文件
    p_delete = subparsers.add_parser("delete-wallet", help="删除本地钱包文件（不可恢复）")
    p_delete.add_argument(
        "--yes",
        action="store_true",
        help="确认删除（必须提供，否则不会执行）"
    )

    # max-sendable: 计算在预留手续费下可发送的最大金额
    p_max = subparsers.add_parser("max-sendable", help="计算可发送的最大 TON 数量")
    p_max.add_argument(
        "--password",
        required=True,
        help="钱包密码"
    )

    return parser


async def _run_cli_command(args: argparse.Namespace) -> None:
    """
    根据解析好的参数执行具体子命令。

    所有结果统一以 JSON 打印到 stdout，错误信息打印到 stderr。
    """
    cmd = args.command

    if cmd == "create":
        wallet = _build_wallet_from_args(args)
        mnemonics = await wallet.create_new_wallet(
            password=args.password,
            wallet_version=args.wallet_version,
        )
        info = wallet.get_wallet_info()
        await wallet.close()
        result = {
            "mnemonic": mnemonics,
            "address_bounceable": info.get("address_bounceable"),
            "address_non_bounceable": info.get("address_non_bounceable"),
            "wallet_version": info.get("wallet_version"),
            "storage_dir": info.get("storage_dir"),
            "wallet_file": info.get("wallet_file"),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "import":
        if args.mnemonic:
            words = args.mnemonic.split()
        else:
            # 从文件读取助记词
            with open(args.mnemonic_file, "r") as f:
                content = f.read()
            words = content.split()

        wallet = _build_wallet_from_args(args)
        info = await wallet.import_wallet(
            mnemonics=words,
            password=args.password,
            wallet_version=args.wallet_version,
        )
        await wallet.close()
        result = {
            "address": info.get("address"),
            "wallet_version": info.get("wallet_version"),
            "is_deployed": info.get("is_deployed"),
            "balance": info.get("balance"),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "info":
        wallet = _build_wallet_from_args(args)
        if args.password:
            await wallet.load_wallet(args.password)
            info = wallet.get_wallet_info()
            await wallet.close()
        else:
            info = wallet.get_wallet_info_offline()
            # 未找到钱包文件时，给出友好提示
            if info is None:
                info = {
                    "initialized": False,
                    "message": "未找到本地钱包文件，请先创建或导入钱包",
                }
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return

    if cmd == "balance":
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        balance = await wallet.get_balance(formatted=args.formatted)
        await wallet.close()
        result = {
            "balance": balance,
            "formatted": args.formatted,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "send":
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        result = await wallet.send_ton(
            destination=args.to,
            amount=args.amount,
            comment=args.comment,
            auto_deploy=args.auto_deploy,
            auto_detect_bounce=args.auto_detect_bounce,
            wait_for_confirmation=args.wait_for_confirmation,
            confirmation_timeout=args.timeout,
            confirmation_check_interval=args.check_interval,
        )
        await wallet.close()
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "tx-history":
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        txs = await wallet.get_transactions(limit=args.limit, formatted=args.formatted)
        await wallet.close()
        print(json.dumps(txs, ensure_ascii=False, indent=2))
        return

    if cmd == "tx-status":
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        status = await wallet.get_transaction_status(args.hash)
        await wallet.close()
        print(json.dumps(status, ensure_ascii=False, indent=2))
        return

    if cmd == "export-mnemonic":
        wallet = _build_wallet_from_args(args)
        words = wallet.export_mnemonic(args.password)
        result = {"mnemonic": words}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "change-password":
        wallet = _build_wallet_from_args(args)
        wallet.change_password(args.old_password, args.new_password)
        result = {"success": True, "message": "密码修改成功"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "delete-wallet":
        wallet = _build_wallet_from_args(args)
        if not args.yes:
            print(
                "错误：删除钱包需要显式添加 --yes 以确认（操作不可恢复）",
                file=sys.stderr,
            )
            raise SystemExit(1)
        wallet.delete_wallet_file()
        result = {"success": True, "message": "钱包文件已删除"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if cmd == "max-sendable":
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        max_amount = await wallet.get_max_sendable_amount()
        await wallet.close()
        result = {"max_sendable": max_amount, "fee_reserve": wallet.fee_reserve}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    # 理论上不会走到这里
    raise SystemExit(f"未知命令: {cmd}")


async def _cli_main(argv: Optional[List[str]] = None) -> None:
    parser = _build_arg_parser()
    args = parser.parse_args(argv)
    try:
        await _run_cli_command(args)
    except (WalletError, NetworkError, ValueError, FileNotFoundError) as e:
        print(f"错误: {e}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(_cli_main())
