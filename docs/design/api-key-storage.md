# API Key 存储：平台凭证库与 SQLite 密文的主从关系

LT 的 LLM Provider API Key 采用 **平台凭证库优先、SQLite 密文回退** 的双层模型。

## 事实来源与主从关系

| 层级 | 实现 | 角色 |
| --- | --- | --- |
| 主 | `FlutterSecureKeyStore`（`flutter_secure_storage`） | 新写入的 Key 的唯一正式存放处；由 OS 负责加密、访问控制与设备绑定 |
| 从 | `EncryptedDatabaseKeyStore` + `KeyVault` | 兼容旧版本数据库与平台凭证库不可用时的回退；密文是应用层混淆，不等同于 OS 凭证保护 |

`MigratingSecureKeyStore` 是唯一编排入口，`SettingsProvider` 不直接接触 KeyVault：

- **读**：先读平台凭证库；命中即返回。未命中时解密 `api_keys` 旧密文，成功后写入平台凭证库，只有写入成功才删除数据库密文；平台写入失败则保留数据库密文供下次重试。
- **写**：先写平台凭证库，成功后清理同 Provider 的数据库残留密文；平台写入失败才回退写数据库密文。
- **删**：两个后端都尝试删除，单侧失败只记录诊断，不抛出到 UI。
- **并发**：同一 Provider 的读、迁移、写、删按顺序串行化，避免旧密文迁移覆盖用户刚保存的新 Key。

## 平台策略

| 平台 | 后端 | 不可用时的行为 |
| --- | --- | --- |
| Android / iOS / macOS | 系统 Keystore / Keychain | 插件异常时回退 SQLite 密文并记录诊断 |
| Windows / Linux | 插件支持的后端（Linux 可能依赖 libsecret） | 同上；`isAvailable()` 返回 false，`read/write` 自动回退 |

`isAvailable()` 只探测平台后端，不代表应用整体不可用：从库始终可用。

## 旧格式兼容

- `KeyVault` v2（`LTV2` + 独立 AES/HMAC 子密钥）是当前 SQLite 密文格式。
- 旧版单密钥密文仍可解密；读取旧记录时会在回退库内就地升级为 v2（仅在记录未被并发修改时）。
- 平台凭证库可用时，旧密文最终会被清空，数据库不再保存该 Provider 的副本。

## 安全约束

- 诊断日志只允许包含操作名与异常 `runtimeType`，禁止输出明文 Key、密文、Token 或完整响应。
- KeyVault 解密失败继续返回空值，不打印异常细节，避免形成解密 oracle。
- 平台凭证库不可用时不得丢失用户 Key：回退路径保留可解密的数据库密文。
- 相关测试：`test/unit/secure_key_store_test.dart`、`test/unit/key_vault_test.dart`、`test/unit/key_vault_migration_test.dart`。
