using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace QuizSync.Core;

/// <summary>解析结果：规范化后的题目列表 + 被丢弃的空题干条数。</summary>
public sealed record ParsedQuestions(IReadOnlyList<Question> Questions, int DroppedEmpty);

/// <summary>
/// `ai-contract.md` 第 3 节的 5 步容错解析里的**前 3 步**（纯文本 → JSON）：
/// 直接解码 → 剥离 markdown 代码围栏 → 截取首尾大括号。全失败返回 null
/// （第 4、5 步——严格提醒重试与标记失败——在调用层）。
///
/// 与 Dart 侧 `ResponseParser` 逐条对齐（同一个 fixture 必须得到同样的结果）。
/// </summary>
public static partial class ResponseParser
{
    public static JsonObject? TryParseJson(string text)
    {
        // 1. 直接解整个响应文本。
        var direct = Decode(text);
        if (direct is not null)
        {
            return direct;
        }

        // 2. 剥离 markdown 代码围栏（```json ... ``` 或 ``` ... ```）。
        var stripped = StripCodeFence(text);
        if (stripped is not null)
        {
            var decoded = Decode(stripped);
            if (decoded is not null)
            {
                return decoded;
            }
        }

        // 3. 取第一个 `{` 到最后一个 `}` 的子串再解。
        var start = text.IndexOf('{', StringComparison.Ordinal);
        var end = text.LastIndexOf('}');
        if (start >= 0 && end > start)
        {
            var decoded = Decode(text[start..(end + 1)]);
            if (decoded is not null)
            {
                return decoded;
            }
        }

        return null;
    }

    /// <summary>把 JSON 转成规范化题目列表；空题干（schema: stem minLength 1）丢弃并计数。</summary>
    public static ParsedQuestions ToQuestions(
        JsonObject json, string sessionId, string deviceId, long now)
    {
        var questions = new List<Question>();
        var dropped = 0;
        if (json["questions"] is JsonArray rawQuestions)
        {
            var ordinal = 0;
            foreach (var item in rawQuestions)
            {
                if (item is not JsonObject itemObject)
                {
                    dropped++;
                    continue;
                }

                var question = Question.FromAiJson(
                    itemObject,
                    questionId: Guid.NewGuid().ToString(),
                    sessionId: sessionId,
                    ordinal: ordinal,
                    deviceId: deviceId,
                    now: now);

                if (string.IsNullOrWhiteSpace(question.Stem))
                {
                    dropped++;
                    continue;
                }

                questions.Add(question);
                ordinal++;
            }
        }

        return new ParsedQuestions(questions, dropped);
    }

    private static JsonObject? Decode(string raw)
    {
        try
        {
            return JsonNode.Parse(raw) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? StripCodeFence(string text)
    {
        var match = FencePattern().Match(text);
        return match.Success ? match.Groups[1].Value : null;
    }

    [GeneratedRegex(@"```(?:json)?\s*\n([\s\S]*?)\n\s*```", RegexOptions.IgnoreCase)]
    private static partial Regex FencePattern();
}

/// <summary>标绿结论（`ai-contract.md` 第 5 节 + `SPEC.md` 4.3）：端侧显示的唯一依据。</summary>
public sealed record HighlightResult(
    IReadOnlySet<string> OptionLabels,
    bool HighlightAnswerText,
    bool NoAnswer,
    bool NeedsReview,
    bool IsJudge)
{
    public bool HasAnyHighlight => OptionLabels.Count > 0 || HighlightAnswerText;
}

public static class Highlight
{
    /// <summary>
    /// `ai-contract.md` 第 5 节伪码的逐字实现。
    /// 用户手改答案后，用用户的值走同一套逻辑（传入手改后的 Question 即可）。
    /// </summary>
    public static HighlightResult Compute(Question question)
    {
        var answer = question.Answer;
        var needsReview = question.Confidence < 0.6 || question.NeedReview;
        var isJudge = question.Type == QuestionType.Judge;

        if (!answer.IsChoiceEmpty && question.Options.Count > 0)
        {
            var hits = answer.MatchedOptionLabels(question.Options);
            return hits.Count > 0
                ? new HighlightResult(hits, false, false, needsReview, isJudge)
                : new HighlightResult(new HashSet<string>(StringComparer.Ordinal), false, true, true, isJudge);
        }

        if (!answer.IsTextEmpty)
        {
            return new HighlightResult(new HashSet<string>(StringComparer.Ordinal), true, false, needsReview, isJudge);
        }

        return new HighlightResult(new HashSet<string>(StringComparer.Ordinal), false, true, true, isJudge);
    }
}
