# iOS Universal Links（echo-loop.top）

本仓库已经补齐了 iOS Universal Links 的工程侧配置，目标域名为 `echo-loop.top`。

当前 iOS `Bundle ID` 为 `top.echo-loop`，当前签名 `Team ID` 为 `S8S968QAV3`，因此 AASA 文件中的 `appIDs` 也已经同步更新为 `S8S968QAV3.top.echo-loop`。

## 已完成的仓库配置

- `ios/Runner/Runner.entitlements`
  - 已添加 `Associated Domains`
  - 当前包含 `applinks:echo-loop.top`
  - 当前包含 `applinks:www.echo-loop.top`
- `web/apple-app-site-association`
  - 提供可直接部署的 AASA 文件模板
  - 已覆盖当前 App 内支持的主要深链路径

## 你还需要完成的服务器配置

1. 将 [web/apple-app-site-association](/Volumes/SamsungT7/workspace/fluency/fluency/web/apple-app-site-association) 发布到以下地址之一：
   - `https://echo-loop.top/apple-app-site-association`
   - `https://echo-loop.top/.well-known/apple-app-site-association`
2. 如果 `www.echo-loop.top` 也会对外提供链接，同样要在 `www` 子域提供同一份文件：
   - `https://www.echo-loop.top/apple-app-site-association`
   - 或 `https://www.echo-loop.top/.well-known/apple-app-site-association`
3. 确保返回条件满足 Apple 要求：
   - 必须是 HTTPS
   - 不能重定向
   - 文件名不能带 `.json`
   - `Content-Type` 建议为 `application/json`

## 真机验证步骤

1. 重新编译并安装 iOS App 到真机
2. 在备忘录、短信或 Safari 中打开以下任一链接：
   - `https://echo-loop.top/study`
   - `https://echo-loop.top/favorites`
3. 如果系统直接拉起 App，说明 Universal Links 已生效
4. 如果仍然停留在 Safari，优先检查：
   - 域名上的 AASA 文件是否可直接访问
   - 返回头是否为 `200 OK` 且无跳转
   - App 是否为重新安装后的新包

## 建议的命令行检查

```bash
curl -I https://echo-loop.top/apple-app-site-association
curl https://echo-loop.top/apple-app-site-association
```

## 当前 AASA 覆盖的路由

- `/`
- `/study`
- `/favorites`
- `/settings`
- `/collections`
- `/collections/*`
- `/audio/*`
- `/bookmark-review`

`/api/*` 已明确排除，避免站点 API 链接被 App 截获。
