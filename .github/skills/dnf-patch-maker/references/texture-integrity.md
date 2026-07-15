# 纹理完整性中文契约

## 一、默认保留

保留源 Sprite、Texture、IMG 版本、压缩、图集、TextureVersion、texture index、裁剪矩形、旋转和共享关系。IMG Ver1/2/4/5/6 必须分别路由 handler。

## 二、声明与载荷一致

Sprite、Texture、压缩和载荷必须描述同一种格式。DXT Sprite 搭配 ARGB Texture 或裸 BGRA 载荷属于硬失败。

DXT1/3/5 必须验证：

- `DDS ` magic 与合法头；
- 匹配 FourCC；
- 宽高；
- 按 4x4 块计算的长度；
- BC1 每块 8 字节，BC2/BC3 每块 16 字节；
- 连续 alpha 使用合适格式。

Bitmap/PNG 替换接口不是 BC 编码器。需要 DXT 时使用成熟编码器并独立检查。

## 三、ARGB 转换边界

只有 Sprite、Texture、压缩和载荷共同一致，且目标客户端验证过时，才采用完整 ARGB 转换。单一职业或客户端的成功不能推广为全局规则。

第三方工具 round-trip 只证明工具自洽，不等于客户端兼容。
