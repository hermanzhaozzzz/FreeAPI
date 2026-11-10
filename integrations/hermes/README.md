# Hermes：FreeAPI 思考字段兼容补丁

**自用临时补丁，仅供参考。** 对应 Hermes 上游问题 [#136486](https://github.com/NousResearch/hermes-agent/issues/136486)。

部分 Hermes 版本会把一段思考历史同时写入 assistant 消息的 `reasoning` 和 `reasoning_content`。部分上游将两者解析为同一个字段，从第二轮开始返回 HTTP 400 `duplicate field reasoning`。

这个插件通过 Hermes 的用户插件机制加载，在进程内包装思考历史的字段选择逻辑，保留 `reasoning_content`，去掉重复的 `reasoning`。仓库源码和已保存的会话历史均不修改；已经运行的 agent 的旧缓存也在返回时处理。

默认仅匹配：

- 模型 `DeepSeek-V4.1-Flash`（忽略大小写）。
- 地址 `http://127.0.0.1:18189/v1`，或对应的 `localhost` / `::1` 地址。
- 使用需要回传思考内容的 Chat Completions 请求。

其他端口、模型和供应商地址不受影响。若修改了 FreeAPI 端口，需要同步修改插件里的匹配条件。

## 安装

在仓库根目录执行；若目标已存在，先检查自己的旧版本再手动更新：

```bash
test ! -e "$HOME/.hermes/plugins/freeapi-reasoning-compat" && \
  mkdir -p "$HOME/.hermes/plugins" && \
  cp -R integrations/hermes/freeapi-reasoning-compat "$HOME/.hermes/plugins/"
hermes plugins enable freeapi-reasoning-compat
```

使用非默认 Hermes profile 时，把路径中的 `~/.hermes` 改为相应的 `HERMES_HOME`。

已在作者的环境验证：多轮思考历史回传、流式回复、工具调用后的继续回答。插件依赖 Hermes 的内部 Python 接口，升级 Hermes 后需要重新验证；上游修复后优先移除这个临时补丁。

## 停用和移除

```bash
hermes plugins disable freeapi-reasoning-compat
```

随后完全重启 Hermes 以及使用它的网关进程，清除内存中的包装函数。只热卸载插件无法撤回已经包装的 Python 函数。确认停用后，可以删除 `~/.hermes/plugins/freeapi-reasoning-compat` 目录。它不创建服务、不保存 Key，也不发起网络请求。
