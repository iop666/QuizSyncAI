# AI 契约

本文件定义 `packages/quizsync_core` 里 AI 客户端的全部行为。**实现必须与本文件的 JSON 字段逐字对齐**，端侧 UI 依赖这些字段（尤其标绿）。

---

## 1. Provider 抽象

```dart
abstract class QuizAiProvider {
  String get id;                     // 'openai-compatible' | 'anthropic' | 'gemini'
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,   // 多页（用户需求 4）：1..6 张，顺序即页序
    required String prompt,
    required AiConfig config,
  });
}

class AiConfig {
  String providerId;
  String baseUrl;        // 可空，空则用 provider 默认
  String apiKey;
  String model;          // 例如 gpt-4o-mini / qwen-vl-max / glm-4v-plus / claude-sonnet / gemini-2.x
  int timeoutSeconds;    // 默认 90
  int maxRetries;        // 默认 2
}
```

需要实现的 provider：

| id | 覆盖 | 说明 |
|---|---|---|
| `openai-compatible` | OpenAI、阿里 DashScope 兼容模式（Qwen-VL）、智谱 GLM-4V、DeepSeek 等一切 OpenAI 兼容端点 | **默认**。请求 `POST {baseUrl}/chat/completions`，图片以 `image_url` data URI 传入；多页时同一条 user 消息里按页序放多个 `image_url` 块 |
| `anthropic` | Claude | `POST {baseUrl}/v1/messages`，图片走 `image` + base64 块（多页 = 多个 image 块） |
| `gemini` | Gemini | `POST {baseUrl}/v1beta/models/{model}:generateContent`，图片走 `inline_data`（多页 = 多个 inline_data part） |

**Provider 必须可被替换为假实现**，供单测与回环集成测试使用（返回固定 fixture，不发网络请求）。

---

## 2. Prompt（全文，逐字使用）

`prompt_version` 字段随本文件内容哈希变化。首版记为 `v1`。

```
你是一个专业的解题助手。用户会给你一张或多张屏幕截图，图中可能包含一道或多道题目。

【任务】
1. 在整张图中找出所有题目。截图可能包含与题目无关的界面元素（浏览器地址栏、标签页、
   聊天窗口、广告、状态栏、视频进度条等），请忽略这些内容，只提取题目本身。
2. 按从上到下、从左到右的阅读顺序输出每一道题。
3. 对每一道题：给出题干、选项（如有）、正确答案、以及简洁清晰的解析。
4. 如果图中没有任何题目，返回 {"questions": []}，不要编造题目。
5. 如果某道题的图片/图形信息不足以作答，仍然输出该题，把 confidence 设为 0.3 以下，
   并把原因写入 warnings。

【多张图片（多页）规则】
- 多张图片是**同一次截屏里的连续页面**，可能包含同一道题或同一组题。
- **图片顺序可能错乱**（用户翻页方向、截屏先后都可能与题目顺序不一致）：你必须先通读
  全部图片，根据内容自己判断正确顺序（题号大小与先后、题干与选项的衔接、材料与问题的
  关系、段落的承上启下），再按**正确的题目顺序**输出；不要盲目沿用给出的图片次序。
- 有些页**只有阅读材料 / 文章 / 图表，没有题目**：不要把这类页丢掉，也不要为它编造
  题目；把该页内容作为它所属题目的 material 输出（见下面的阅读类规则）。
- 一道题可能在某一页开始、在下一页继续（题干在一页、选项在下一页）。这种情况请把两页
  的内容**合并成同一道题**输出，不要拆成两道题，也不要因为第一页缺选项就丢掉它。
- 只有确认两页属于**不同**的题目时，才分别输出。

【阅读类题目规则（材料要单独给，不要混进题干）】
- 阅读理解、完形填空、材料题、资料分析这类题目：把文章 / 段落 / 图表文字等**材料原文**
  完整写进 material 字段，stem 只写**问题本身**（例如「下列说法正确的是」），
  不要把自己抄进 stem 的材料重复一遍。
- 同一份材料下面有多道小题时，每道小题的 material 都要把这份材料重复填满。
- 不是阅读类的题目，material 一律给 null。

【主观题规则（必须结构化、条理化）】
- subjective（主观题 / 简答 / 问答 / 论述）的 answer.text 必须**分点分层、条理清晰**，
  不要写成一大段话：用换行分隔，每一点以 ①②③ 或 1. 2. 3. 开头；先给结论，再列依据。
- 每一点写成一句短句，一句一个要点；关键术语、数值、公式要完整准确。
- blank（填空）的 answer.text 按空格先后给出答案，多个空用「；」分隔。

【不完整题目规则（必须严格遵守）】
- 如果某段内容**只有答案、没有题干**（例如只截到了答案页、解析页的一角），
  **不要输出这道题**，也不要为它编造题干。
- 如果**有题干但选项不全**（选项被截断、只截到 A、B，或明显缺少后续选项），
  仍然输出这道题：把 incomplete 设为 true，并按题意推断最可能的答案，
  同时把 answer_is_guess 设为 true，在 analysis 里说明这是推断。
- 如果题干本身被截断（例如结尾是省略号、句子不完整），把 incomplete 设为 true。
- 只要 incomplete 为 true，就把 need_review 设为 true。

【题号规则】
- 尽量识别图中原本印着的题号（例如 "12"、"(3)"、"3(2)"、"例 5"），原样写入 question_no。
- 图中没有题号时给 null，不要自己编号。

【输出格式】
只输出一个 JSON 对象，不要输出任何解释文字，不要用 markdown 代码围栏包裹。

{
  "questions": [
    {
      "question_no": "图中的题号，如 '12' 或 '(3)'，没有则给 null",
      "material": "阅读类题目的材料原文；没有材料则给 null",
      "stem": "题干全文（问句本身），不含选项，也不含 material 里的材料原文",
      "type": "single | multi | judge | blank | subjective",
      "options": [
        { "label": "A", "text": "选项内容" }
      ],
      "answer": {
        "choice": ["B"],
        "text": null
      },
      "analysis": "解析过程。数学公式用 LaTeX，行内用 \$...\$，独立公式用 \$\$...\$\$",
      "confidence": 0.95,
      "need_review": false,
      "has_answer_in_image": false,
      "incomplete": false,
      "answer_is_guess": false,
      "warnings": []
    }
  ]
}

【字段规则】
- type：单选 single；多选 multi；判断 judge；填空 blank；主观题/问答 subjective。
- material：阅读类题目的材料原文（完整照抄，保留段落换行）；没有材料时给 null。
- options：单选、多选、判断必须给出；填空与主观题为空数组 []。
- 判断题的选项固定为 [{"label":"对","text":"对"},{"label":"错","text":"错"}]，answer.choice 填 "对" 或 "错"。
- answer.choice：选项类题目的答案，元素必须与 options 里的 label 完全一致。
  单选恰好 1 个元素；多选 1 个或多个元素。
- answer.text：填空与主观题的答案文本（主观题必须分点、用换行分隔）；选项类题目填 null。
- confidence：0 到 1 之间，表示你对这道题答案的把握。
- need_review：当你认为答案可能不可靠时为 true。
- has_answer_in_image：图中是否本来就印着答案（例如答案页、教辅解析）。
  如果图中已有答案，以图中的答案为准，并把该项设为 true。
- incomplete：题目是否不完整（题干被截断、或选项缺失/不全）。
- answer_is_guess：答案是否为你按题意推断出来的（而不是题目或计算直接给出的）。
- warnings：字符串数组，没有则为 []。

【重要】
- 选项类题目必须给出答案，不要留空。
- 不要输出 analysis 之外的任何额外字段（上面的字段都要给全）。
- 解析要在保证正确的前提下尽量简短。

```

---

## 3. 输出 JSON Schema（解析与校验的唯一依据）

```json
{
  "type": "object",
  "required": ["questions"],
  "properties": {
    "questions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["stem", "type", "options", "answer", "analysis", "confidence"],
        "properties": {
          "question_no":     { "type": ["string", "null"] },
          "material":        { "type": ["string", "null"] },
          "stem":            { "type": "string", "minLength": 1 },
          "type":            { "enum": ["single", "multi", "judge", "blank", "subjective"] },
          "options": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["label", "text"],
              "properties": { "label": {"type":"string"}, "text": {"type":"string"} }
            }
          },
          "answer": {
            "type": "object",
            "properties": {
              "choice": { "type": ["array","null"], "items": { "type": "string" } },
              "text":   { "type": ["string","null"] }
            }
          },
          "analysis":            { "type": "string" },
          "confidence":          { "type": "number", "minimum": 0, "maximum": 1 },
          "need_review":         { "type": "boolean" },
          "has_answer_in_image": { "type": "boolean" },
          "incomplete":          { "type": "boolean" },
          "answer_is_guess":     { "type": "boolean" },
          "warnings":            { "type": "array", "items": { "type": "string" } }
        }
      }
    }
  }
}
```

### 解析容错（必须按此顺序尝试，全部失败才算失败）

1. 直接 `jsonDecode` 整个响应文本。
2. 若失败，剥离 markdown 代码围栏（```json ... ``` 或 ``` ... ```）后再次 `jsonDecode`。
3. 若失败，取文本中**第一个 `{` 到最后一个 `}`** 的子串再解。
4. 若仍失败：附加一条用户消息「上一次的返回不是合法 JSON。请只输出 JSON 对象本身，不要任何其他文字或代码围栏。」重试 1 次。
5. 仍失败：把会话标记为 `failed`，保留原始返回文本（存入 `sessions.raw_response`）供人工查看，并置 `need_review = true`。

### 字段级规范化（缺字段不报错，补默认值）

| 情况 | 处理 |
|---|---|
| 缺 `question_no` | 置 null |
| 缺 `material` / 为 null / 纯空白 | 置 `''`（`Question.material`，DB 列默认空串），端侧不渲染材料面板 |
| 缺 `options` | 置 `[]`；若 `type` 是 single/multi/judge 且 `options` 为空 → 记 warning「未识别到选项」，不标绿 |
| 缺 `answer` 或 `answer` 全空 | 记 warning「未识别出答案」，不标绿，`need_review = true` |
| `answer.choice` 元素不在 `options[].label` 中 | 剔除非法元素；若剔除后为空 → 记 warning「答案与选项不匹配」，不标绿 |
| 缺 `confidence` | 按 0.5 处理（会触发需复核徽标） |
| 缺 `warnings` | 置 `[]` |
| `type` 不认识 | 按 `subjective` 处理并记 warning |
| `judge` 且选项缺失 | 自动补 `[{"label":"对","text":"对"},{"label":"错","text":"错"}]` |
| 缺 `incomplete` | 置 false；但 single/multi 的 `options` 少于 2 项时**强制置 true**（题目被截断），并记 warning「选项不全（仅 N 项）」 |
| 缺 `answer_is_guess` | 置 false；但 `incomplete == true` 且答案非空时**强制置 true**（该答案只能是推断），并记 warning「答案为 AI 按题意推断，仅供参考」，同时 `need_review = true` |
| `incomplete == true` | 追加 warning「题目不全，已在卡片上标黄」；端侧给整张卡片加黄框 |
| 只有答案没有题干（`stem` 为空） | **丢弃该题**（不计入 `questions`，计入 `dropped_empty`），不要为它编造题干 |

---

## 4. 重试、超时、缓存与配额

| 项 | 规则 |
|---|---|
| 超时 | 默认 90 秒（整体请求），可配置。**注意：原计划的 30 秒已按 `DECISIONS.md` 3.5 放宽** |
| 可重试错误 | 超时、连接失败、HTTP 5xx、HTTP 429 |
| 重试策略 | 指数退避：第 1 次等待 1s，第 2 次等待 3s；默认最多 2 次 |
| 不可重试错误 | HTTP 400（请求格式错）、401 / 403（Key 无效或无权限）。直接失败并给出对应提示，不要浪费重试 |
| JSON 解析失败 | 走上面的容错第 4 步，额外重试 1 次（不占用上面的 2 次网络重试预算） |
| 缓存 | key = `image_hash` + `prompt_version` + `model`。命中且距今 < 30 天 → 直接回放结果，**不调用 API**，会话标注 `cached: true` |
| 缓存与多页 | **缓存与同图去重只对单页生效**。会话级缓存按 `sessions.image_hash`（多页时=第一页）查找，无法区分「首页相同但后续页不同」的两次识别，命中错缓存比不命中更糟；多页任务必须真实调用 AI。同图去重也必须**页序完全一致**才算命中 |
| 同图去重 | 同一 `image_hash` 已有 `done` 会话时，默认直接复用，不重新分析；UI 提示「这道题之前搜过，跳到上次结果」 |
| 每日配额 | 默认 200 次（不含缓存命中），达到上限时明确提示「今日调用已达上限」，不静默失败 |
| 用量记录 | 每次真实调用记录：时间、模型、prompt_version、耗时、是否成功、错误码 |

---

### 4.1 多页识别（用户需求 4）

- 一次识别可以带 **1..6 页**图片（上限可配 `AppSettings.multiPageLimit`，服务端硬上限 `kHardMaxPagesPerTask` **就是 6** —— 用户反馈 9 明确「硬上限就是 6 张，不是 12」）。
- 页序由 `session_images.ordinal`（0 起）决定，`sessions.image_hash` 始终是**第一页**（兼容既有缓存与协议字段）。
- 多页请求把全部页放进**同一条** user 消息（OpenAI 兼容 = 多个 `image_url`；Anthropic = 多个 image 块；Gemini = 多个 inline_data part）。
- **页序错乱由模型自己纠正**（用户反馈 14：多页顺序可能乱，让 AI 自己识别完进行正确排序）：prompt 明确要求先通读全部图片、按内容判断正确顺序后再输出，不得盲目沿用给出的图片次序。（`session_images.ordinal` 仍如实记录**用户实际截取的顺序**，用于展示与重试，不因模型排序而改写。）
- **只有材料、没有题目的页不能丢**（用户反馈 14）：这类页的内容进入所属题目的 `material` 字段，而不是被忽略或伪造题干。
- 任务执行时若任何一页的图片文件缺失 → 任务失败（`internal`），**不得**用残缺的页序出结果。

### 4.2 不完整题目与 AI 猜测的端侧表现（用户需求 2/3）

| 数据 | 端侧表现 |
|---|---|
| `incomplete == true` | 整张题目卡片加**黄色外框**，顶部黄底横幅「题目不全（题干或选项被截断）」 |
| `answerGuessed == true` | 顶部黄色徽标「AI 猜测答案」，答案区标题追加「（AI 猜测）」，横幅文案改为「下面的答案是 AI 按题意推断的」 |
| `question_no` 有值 | 卡片标题 = `displayTitle`，即 `排序序号. 第 <question_no> 题`（例：`3. 第 12 题`）；没有题号时只有 `3.` |
| 导出文件 | 标题同样用 `displayTitle`，并在题型后追加「· 题目不全 / · AI 猜测」 |

### 4.3 阅读材料与结构化主观题（用户反馈 15）

| 数据 | 端侧表现 |
|---|---|
| `material` 非空 | 卡片题干**上方**渲染「阅读材料（N 行，点击展开）」面板，**默认折叠**，点击展开/收起（`QuestionCard`，两端共用） |
| `material` 为空 | 完全不渲染材料面板（绝大多数题目） |
| 主观题 `answer.text` 含多行 | 按行渲染为条目（保留 AI 给的 ①②③ / 1. 等序号），没有序号的行走项目符号，见 `Question.hasStructuredAnswer` |
| 导出 Markdown | `material` 以引用块（`>`）放在题干之前 |

---

## 5. 标绿映射（端侧唯一依据）
端侧**只读**下面这些字段，不得从 `analysis` 文本里搜索答案：

```
对每道题：
  if (answer.choice 非空 && options 非空):
      命中集合 = answer.choice ∩ options.map(label)
      if (命中集合 非空):
          type == judge  → 在「对 / 错」中把命中的那个标绿
          其他           → 把所有命中选项行标绿        // 单选 1 个，多选多个
      else:
          不标绿 + 显示「未识别出答案」
  else if (answer.text 非空):
      在「答案」区块用绿色文字 + 浅绿底显示 answer.text   // 填空 / 主观
  else:
      不标绿 + 显示「未识别出答案」
```

配色与图标见 `SPEC.md` 4.3。用户手改答案后，用用户的值走同一套逻辑标绿。

**用户反馈 13：AI 自己没把握时不用绿色。** 当 `need_review == true` 或 `confidence < 0.6`
（即 `HighlightResult.needsReview`）时，命中的选项行与「答案」区块改用**黄色**配色
（`HighlightColors.lightUncertainText` / `darkUncertainText` 与对应底色），
绿色专留给「可信的答案」。逻辑与配色分离：`computeHighlight` 只给出 `needsReview`，
颜色由端侧 `HighlightColors.text(bright, uncertain: true)` 决定。

---

## 6. 置信度语义

| confidence | 端侧表现 |
|---|---|
| ≥ 0.85 | 不显示徽标 |
| 0.6 – 0.85 | 不显示徽标 |
| < 0.6 | 卡片顶部黄色徽标「AI 不确定，建议复核」 |
| `need_review == true` | 同上，无论 confidence 多少 |

全应用范围必须有一处常驻的免责声明：「答案由 AI 生成，仅供参考」。

---

## 7. 测试要求（M2 起）

1. **解析容错单测**：针对容错 5 个步骤各写一个用例，包括纯文本包裹、代码围栏、前后有解释文字、完全非法 JSON。
2. **字段规范化单测**：覆盖第 3 节表格里的每一行。
3. **标绿映射单测**：覆盖单选、多选、判断、填空、主观、答案与选项不匹配、answer 为空共 7 个用例。
4. **重试行为单测**：用假 provider 依次返回「超时 → 超时 → 成功」，断言总共调用 3 次且退避时长正确；返回 401 时断言只调用 1 次。
5. **缓存单测**：同一 hash 连续两次请求，断言第二次没有触发 provider。
6. 所有 fixture 放在 `packages/quizsync_core/test/fixtures/`，**不要**在单测里发真实网络请求。
