# 樱花主题 Prompt 索引

## 一、职责

本目录只定义女气功职业 Prompt 在樱花主题下“具体改成什么样”。真实资源范围仍由 `../../manifest.json` 决定。

## 二、加载顺序

1. 读取 manifest、`../../prompts/README.md` 和显示名映射状态。
2. 只有显示名映射已核验时，才读取同名职业 Prompt 与本目录同名主题 Prompt。
3. 映射未核验时只使用源帧语义、几何和 manifest 独立授权的樱花共同规则；不得按名称套用逐技能增量。

## 三、稳定结构

每个文件固定包含：`职业基础`、`主题增量 Prompt`、`具体变化`、`主题验收`、`主题排除`。

主题基线：`sakura petals, cherry blossom particles, rose-pink energy, pink-white highlights, pale gold rim light, translucent floral mist, graceful wind flow, layered luminous edges`。

参考色板：`#000000 -> #3A0D25 -> #C43F73 -> #FFB7C5 -> #FFF5F8`。

## 四、当前文件

- `念气波.md`
- `雷霆踏.md`
- `螺旋念气场.md`
- `念气罩.md`
- `狮子吼.md`
- `幻影爆碎.md`
- `千莲怒放.md`
- `乱舞·千叶花.md`
- `念兽·龙虎啸.md`
- `三觉·百花奥义.md`
- `念气环绕.md`
- `光之兵刃.md`

## 五、覆盖状态

这些文件是主题设计条目，不是全技能覆盖证明。透明、人物、背景、Cut-in 和画布尺寸均按源帧与 manifest 决定。
