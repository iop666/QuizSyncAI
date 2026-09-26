using System.Text.Json.Nodes;

namespace QuizSync.Core;

/// <summary>题型。取值与 `ai-contract.md` 第 3 节 enum 逐字一致（wire 字符串不许改）。</summary>
public enum QuestionType
{
    SingleChoice,
    MultiChoice,
    Judge,
    Blank,
    Subjective,
}

public static class QuestionTypes
{
    public static string Wire(this QuestionType type) => type switch
    {
        QuestionType.SingleChoice => "single",
        QuestionType.MultiChoice => "multi",
        QuestionType.Judge => "judge",
        QuestionType.Blank => "blank",
        _ => "subjective",
    };

    /// <summary>不认识的 type 按 subjective 处理（是否记 warning 由调用方决定）。</summary>
    public static QuestionType Parse(string? raw) => raw switch
    {
        "single" => QuestionType.SingleChoice,
        "multi" => QuestionType.MultiChoice,
        "judge" => QuestionType.Judge,
        "blank" => QuestionType.Blank,
        _ => QuestionType.Subjective,
    };

    public static bool IsKnown(string? raw) =>
        raw is "single" or "multi" or "judge" or "blank" or "subjective";

    /// <summary>该题型必须有选项（单选 / 多选 / 判断）。</summary>
    public static bool RequiresOptions(this QuestionType type) =>
        type is QuestionType.SingleChoice or QuestionType.MultiChoice or QuestionType.Judge;
}

/// <summary>选项（`options[]` 的一项）。</summary>
public sealed record Option(string Label, string Text)
{
    public static Option FromJson(JsonObject json) =>
        new(json["label"]?.ToString() ?? string.Empty, json["text"]?.ToString() ?? string.Empty);
}

/// <summary>
/// 结构化答案。**标绿的判定只依赖本类**（`ai-contract.md` 第 5 节）：
/// 严禁从解析文本里搜索答案。
/// </summary>
public sealed record AnswerValue(IReadOnlyList<string>? Choice = null, string? Text = null)
{
    public static readonly AnswerValue Empty = new();

    public bool IsChoiceEmpty => Choice is null || Choice.Count == 0;

    public bool IsTextEmpty => string.IsNullOrEmpty(Text);

    public bool IsEmpty => IsChoiceEmpty && IsTextEmpty;

    /// <summary>标绿判定核心：`answer.choice` ∩ `options[].label`，非法 label 自动剔除。</summary>
    public HashSet<string> MatchedOptionLabels(IReadOnlyList<Option> options)
    {
        var matched = new HashSet<string>(StringComparer.Ordinal);
        if (IsChoiceEmpty)
        {
            return matched;
        }

        var labels = options.Select(o => o.Label).ToHashSet(StringComparer.Ordinal);
        foreach (var label in Choice!)
        {
            if (labels.Contains(label))
            {
                matched.Add(label);
            }
        }

        return matched;
    }

    public static AnswerValue FromJson(JsonObject? json)
    {
        if (json is null)
        {
            return Empty;
        }

        List<string>? choice = null;
        if (json["choice"] is JsonArray array)
        {
            choice = [.. array.Select(item => item?.ToString() ?? string.Empty)];
        }

        return new AnswerValue(choice, json["text"]?.ToString());
    }
}

/// <summary>
/// 题目。字段与 `data-model.md` 的 `questions` 表对齐；`FromAiJson` 负责
/// **字段级规范化**（与 Dart 侧 `Question.fromAiJson` 逐条一致）。
/// </summary>
public sealed record Question
{
    public required string QuestionId { get; init; }

    public required string SessionId { get; init; }

    public required int Ordinal { get; init; }

    public string? QuestionNo { get; init; }

    public string Stem { get; init; } = string.Empty;

    public string Material { get; init; } = string.Empty;

    public QuestionType Type { get; init; } = QuestionType.Subjective;

    public IReadOnlyList<Option> Options { get; init; } = [];

    public IReadOnlyList<string> Choice { get; init; } = [];

    public string? AnswerText { get; init; }

    public string Analysis { get; init; } = string.Empty;

    public double Confidence { get; init; } = 0.5;

    public bool NeedReview { get; init; }

    public bool AnswerInImage { get; init; }

    public bool Incomplete { get; init; }

    public bool AnswerGuessed { get; init; }

    public IReadOnlyList<string> Warnings { get; init; } = [];

    public long CreatedAt { get; init; }

    public long UpdatedAt { get; init; }

    public required string UpdatedBy { get; init; }

    public AnswerValue Answer => new(Choice, AnswerText);

    public bool ShouldShowReviewBadge => NeedReview || Confidence < 0.6;

    /// <summary>
    /// 把 AI 返回的一条 JSON 规范化成题目。规则（与 Dart 侧逐条对齐，见 `ai-contract.md` 第 3 节）：
    /// 未知 type → subjective 并记 warning；judge 缺选项 → 自动补「对/错」；
    /// 选项类缺选项 → warning；`answer.choice` 里不在选项中的 label 剔除；
    /// 答案为空 → warning + `need_review`；选项少于 2 项 → incomplete（有答案则算猜测）；
    /// AI 显式声明的 `incomplete` / `answer_is_guess` 同样尊重。
    /// </summary>
    public static Question FromAiJson(
        JsonObject json,
        string questionId,
        string sessionId,
        int ordinal,
        string deviceId,
        long now)
    {
        var warnings = new List<string>();
        if (json["warnings"] is JsonArray rawWarnings)
        {
            warnings.AddRange(rawWarnings.Select(w => w?.ToString() ?? string.Empty));
        }

        var typeRaw = json["type"]?.ToString();
        if (!QuestionTypes.IsKnown(typeRaw))
        {
            warnings.Add($"未知题型 {typeRaw ?? "(null)"}，按 subjective 处理");
        }

        var type = QuestionTypes.Parse(typeRaw);

        var options = new List<Option>();
        if (json["options"] is JsonArray optionsRaw)
        {
            foreach (var item in optionsRaw)
            {
                if (item is JsonObject optionObject)
                {
                    var option = Option.FromJson(optionObject);
                    if (!string.IsNullOrEmpty(option.Label))
                    {
                        options.Add(option);
                    }
                }
            }
        }

        if (type == QuestionType.Judge && options.Count == 0)
        {
            // judge 且选项缺失：自动补「对 / 错」。
            options = [new Option("对", "对"), new Option("错", "错")];
        }

        if (type.RequiresOptions() && options.Count == 0)
        {
            warnings.Add("未识别到选项");
        }

        var answer = json["answer"] is JsonObject answerRaw ? AnswerValue.FromJson(answerRaw) : AnswerValue.Empty;

        var choice = answer.Choice?.ToList() ?? [];
        if (choice.Count > 0)
        {
            var labels = options.Select(o => o.Label).ToHashSet(StringComparer.Ordinal);
            var valid = choice.Where(labels.Contains).ToList();
            if (valid.Count != choice.Count)
            {
                if (valid.Count == 0)
                {
                    warnings.Add("答案与选项不匹配");
                }

                choice = valid;
            }
        }

        var answerText = answer.IsTextEmpty ? null : answer.Text;
        var needReview = json["need_review"]?.GetValue<bool>() == true;
        if (answer.IsEmpty)
        {
            warnings.Add("未识别出答案");
            needReview = true;
        }

        var lacksOptions = type.RequiresOptions() && options.Count < 2;
        var incomplete = json["incomplete"]?.GetValue<bool>() == true || lacksOptions;
        var guessed = json["answer_is_guess"]?.GetValue<bool>() == true || (incomplete && !answer.IsEmpty);
        if (lacksOptions && options.Count > 0)
        {
            warnings.Add($"选项不全（仅 {options.Count} 项）");
        }

        if (incomplete)
        {
            warnings.Add("题目不全，已在卡片上标黄");
        }

        if (guessed)
        {
            warnings.Add("答案为 AI 按题意推断，仅供参考");
            needReview = true;
        }

        var confidence = json["confidence"]?.GetValue<double>() ?? 0.5;
        var material = (json["material"]?.ToString() ?? string.Empty).Trim();

        return new Question
        {
            QuestionId = questionId,
            SessionId = sessionId,
            Ordinal = ordinal,
            QuestionNo = json["question_no"]?.ToString(),
            Stem = json["stem"]?.ToString() ?? string.Empty,
            Material = material,
            Type = type,
            Options = options,
            Choice = choice,
            AnswerText = answerText,
            Analysis = json["analysis"]?.ToString() ?? string.Empty,
            Confidence = confidence,
            NeedReview = needReview,
            AnswerInImage = json["has_answer_in_image"]?.GetValue<bool>() == true,
            Incomplete = incomplete,
            AnswerGuessed = guessed,
            Warnings = warnings,
            CreatedAt = now,
            UpdatedAt = now,
            UpdatedBy = deviceId,
        };
    }
}
