# SNI（伪装目标站点）怎么选

REALITY 会把客户端的 TLS 握手「借用」一个真实网站的证书来伪装，所以 `dest` / `serverNames` 要选一个合适的真实站点。默认 `www.nvidia.com`。

## 选择标准

- **大型真实网站**，支持 **TLS 1.3** 和 **HTTP/2**（REALITY 要求 TLS 1.3）。
- **不要选被用烂的**：例如 `www.lovelive-anime.jp` 是教程里的常见示例，大量节点都在用，特征明显。
- **不要选在国内被墙的**：例如 `dl.google.com`，国内访问不了的站点作为伪装目标本身就可疑。
- 最好是在 VPS 所在地区访问快、有 CDN 节点的站点；不要选会跳转到其他域名的站点。

## 测试命令（🌐 服务器上）

```bash
# 方法 1：Xray 自带（会显示 TLS 版本、证书域名、握手耗时）
xray tls ping www.nvidia.com

# 方法 2：curl 检查 TLS1.3 + HTTP/2，预期输出 2
curl -sS -o /dev/null --tlsv1.3 --http2 -w '%{http_version}\n' https://www.nvidia.com/
```

更换 SNI：`bash install.sh --sni <新站点>`（会复用原 UUID/密钥，只是 SNI 变了，客户端需重新导入链接）。
