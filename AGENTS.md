# AGENTS.md

FreeAPI 是 macOS 菜单栏代理工具，本文件记录仓库的工作约定，重点是版本发布和 GitHub Release 维护。

## 日常改动

- 直接在 `main` 上提交，不建功能分支，不建 PR。
- 提交信息用英文祈使句，一行说清做了什么，例如 `Add an opt-in launch-at-login setting`。
- 提交前跑 `./scripts/check.sh` 和 `./scripts/test.sh`；prek 钩子会再跑一遍。
- 涉及配置结构时同步 `AppConfiguration.currentVersion` 并提供迁移，不能只改 `Backends` 字段。

## 版本号

三处必须一起改：

| 位置 | 说明 |
| --- | --- |
| `Resources/Info.plist` → `CFBundleShortVersionString` | 语义化版本，例如 `3.1.0` |
| `Resources/Info.plist` → `CFBundleVersion` | 单调递增的构建号，每次发版 +1 |
| `README.md`「构建与安装」 | `dist/FreeAPI-X.Y.Z.dmg` 的文件名 |

版本策略：新功能升 minor，修复升 patch，配置文件结构破坏性变更才升 major。

## 发布流程

```bash
# 1. 确认工作区干净、检查和测试通过
git status
./scripts/check.sh
./scripts/test.sh

# 2. 提交版本号改动
git add Resources/Info.plist README.md
git commit -m "Bump the version to 3.1.0"

# 3. 打附注 tag，标题固定为 FreeAPI X.Y.Z
git tag -a v3.1.0 -m "FreeAPI 3.1.0"

# 4. 推送 main 和 tag，两者都要推
git push origin main
git push origin v3.1.0

# 5. 本地构建 Universal DMG，产物在 dist/
./scripts/package.sh universal
# dist/FreeAPI-3.1.0.dmg 与 dist/SHA256SUMS
```

推送后 CI 会在 macOS 15 上跑检查并构建 DMG 作为 Actions 产物（`FreeAPI-macOS`）。等它通过再发布，不要写轮询脚本盯着。

## 创建 GitHub Release

tag 已经在远端之后，用 `gh` 创建 Release 并上传 DMG 与校验文件：

```bash
gh release create v3.1.0 \
  dist/FreeAPI-3.1.0.dmg dist/SHA256SUMS \
  --title "FreeAPI 3.1.0" \
  --notes "$(cat <<'EOF'
## 更新内容

- 设置页新增「启动」分区，可用「登录时启动 FreeAPI」开关让应用在登录后自动驻留菜单栏

## 安装

需要 macOS 15 或更新版本。下载 `FreeAPI-3.1.0.dmg`，退出旧版本，把 FreeAPI 拖进 Applications。构建使用 ad-hoc 签名、未公证，第一次打开被 Gatekeeper 拦住时在 Finder 里右键「打开」。

校验：`shasum -a 256 -c SHA256SUMS`
EOF
)"
```

发布要点：

- Release 标题与 tag 一致，都是 `FreeAPI X.Y.Z`。
- 正文用中文，先列更新内容（按 `git log v<上一个>..HEAD --oneline` 归纳，面向用户而不是逐条抄提交），再写安装与校验说明。
- 附件只放 `FreeAPI-X.Y.Z.dmg` 和 `SHA256SUMS`，不要上传 `build/` 中间产物。
- 不把已发布的历史 Release 当作可随意改写的对象：正文可以修错别字，附件和 tag 不要悄悄替换。

## Release 页面维护

```bash
gh release list                              # 看现有版本
gh release view v3.1.0                       # 看正文和附件
gh release view v3.1.0 --json assets --jq '.assets[].name'
gh release edit v3.1.0 --notes-file notes.md # 改正文
gh release upload v3.1.0 dist/FreeAPI-3.1.0.dmg --clobber   # 替换附件
gh release delete v3.1.0                     # 删 Release，tag 仍在
```

- 附件损坏或漏传时用 `--clobber` 重传，并在正文里补一句修正说明。
- 删除 Release 前先确认：外部文章（如 `articles/freeapi-zhihu.md` 里的下载链接）是否引用该 tag，tag 本身是否还有人依赖。
- 已发表文章里指向旧版本（`v3.0.0`）的链接保持可用，不要为了新版本去改文章内容。

## 发版后的验证

- `gh release view <tag> --json assets` 确认 DMG 和 `SHA256SUMS` 都在。
- 下载 DMG 一验：挂载后 `FreeAPI.app` 能启动，版本号与 tag 一致。
- 新功能要在真实应用里点一次，菜单栏应用的界面状态（登录项、隧道连接）无法靠类型检查覆盖。
