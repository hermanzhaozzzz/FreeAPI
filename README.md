# FreeAPI

<img src="Resources/AppIcon.png" alt="FreeAPI icon" width="120">

**自用项目，仅供别人参考。** 按作者自己的使用习惯维护，其他环境需要自行调整；不承诺通用兼容性或长期支持。

一个 macOS 菜单栏 SSH 隧道工具：当本机无法访问某个模型 API、但 SSH 跳板机可以访问时，把该接口转发到本机回环地址。使用者需要自己的 SSH 访问权限和 API 凭据。

```text
客户端 → 127.0.0.1:18189 → SSH 跳板机 → 模型 API
```

## 使用方式

打开 FreeAPI，菜单栏出现链环图标和状态圆点。使用期间保持它运行，退出时关闭隧道。没有 launchd 服务、登录启动项或系统代理设置。

| 状态 | 含义 |
| --- | --- |
| 绿色 | 上游 HTTP 接口可达 |
| 橙色 | 正在连接、恢复连接或上游异常 |
| 灰色 | 已主动断开 |

菜单支持复制 API 地址、重新连接、断开连接、查看详情和退出。最近的连接日志只保存在内存中。

SSH 每 10 秒保活，连续 3 次无响应后断开；重试间隔逐步增加到 15 秒。每 15 秒检查 `/models`，连续两次网络失败会重建隧道。监听网络恢复和系统唤醒；正常退出或强制退出时，看护进程会清理 SSH 子进程。断线中的请求仍可能需要客户端重试。

## 配置

需要 macOS 15 或更新版本，以及已经可以非交互登录的 SSH 密钥或 ssh-agent。先用终端连接自己的跳板机，确认主机指纹并完成首次登录。应用启用严格主机密钥检查和 `BatchMode`，不弹出密码输入框。

```bash
mkdir -p "$HOME/Library/Application Support/FreeAPI"
cp config.example.json "$HOME/Library/Application Support/FreeAPI/config.json"
chmod 600 "$HOME/Library/Application Support/FreeAPI/config.json"
```

编辑这个本机文件，把示例值替换为自己的地址：

```json
{
  "sshDestination": "user@bastion.example.com",
  "remoteHost": "api.internal.example.com",
  "remotePort": 8189,
  "localPort": 18189,
  "apiPath": "/v1"
}
```

- `sshDestination`：SSH 的 `user@host` 或 `~/.ssh/config` 中的 Host 别名。端口、密钥和 ProxyJump 可放在 SSH 配置里。
- `remoteHost` / `remotePort`：**跳板机能够访问**的 API 主机和端口，不填写 `http://` 或路径。
- `localPort`：本机监听端口，只绑定 `127.0.0.1`，范围 1024–65535。
- `apiPath`：API 路径，例如 `/v1`；不带结尾斜杠，也可为空字符串。

配置在启动时读取，修改后重新打开应用。未找到有效配置时会提示打开配置目录。

API Key 填在客户端中，FreeAPI 不保存它。绿色状态包含 HTTP 200、401 和 403：表示 HTTP 接口可达，不代表模型鉴权或生成请求已经成功。示例面向 HTTP 上游；SSH 加密覆盖本机到跳板机这一段。

## 构建与安装

安装 Apple Command Line Tools 后执行：

```bash
xcode-select --install    # 已安装则跳过
./scripts/test.sh
./scripts/package.sh
```

默认构建包含 Intel 和 Apple Silicon 的 Universal 应用。也可以指定架构：

```bash
./scripts/package.sh x86_64
./scripts/package.sh arm64
```

产物为 `build/FreeAPI.app` 和 `dist/FreeAPI-macOS.zip`。退出旧版本后，把应用复制到 `/Applications` 再打开。构建使用 ad-hoc 签名，未进行 Apple 公证。运行验证以作者的 Intel / macOS 15 环境为主；Apple Silicon 版本需要自行验证。

GitHub Actions 运行配置和进程清理测试，并构建 Universal 应用。CI 不连接任何真实跳板机，也不需要密钥。

## 客户端

使用示例配置时，OpenAI 兼容客户端的 Base URL 是：

```text
http://127.0.0.1:18189/v1
```

在 CC Switch 中添加自定义供应商，填写这个地址、自己的 Key 和上游实际提供的模型 ID。模型上下文长度、图片输入和思考能力应以具体部署和实际测试为准。

Claude Code / Claude Desktop 使用 Anthropic 协议；如果上游只有 OpenAI Chat Completions，需要启用 CC Switch 的协议转换路由，并让 FreeAPI 和 CC Switch 同时保持运行。FreeAPI 本身只负责 TCP 转发。Claude Desktop 的 Cowork 还受系统虚拟化能力限制。

## 可选 Hermes 兼容补丁

[`integrations/hermes/`](integrations/hermes/) 保存了作者使用 FreeAPI + DeepSeek 时遇到的重复思考字段问题的临时补丁。它单独安装，不随应用自动启用；作用范围和卸载方式见该目录说明。

## 卸载

从菜单选择“退出并关闭隧道”，然后删除 `/Applications/FreeAPI.app`。本机配置目录 `~/Library/Application Support/FreeAPI` 和下载的压缩包可按需删除。没有系统后台服务需要卸载。Hermes 插件需按其独立说明移除。

## 仓库边界

本仓库包含应用源码、生成的应用图标、构建脚本、脱敏配置示例及可选兼容补丁。真实地址、SSH 密钥、API Key、运行日志和会话数据保留在本机。不要将自己的配置或客户端数据库提交到仓库。
