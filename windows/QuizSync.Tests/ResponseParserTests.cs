using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using QuizSync.Core;
using Xunit;

namespace QuizSync.Tests;

/// <summary>找到产品仓里的 Dart 侧文件（fixtures 与 prompt 源码）。</summary>
internal static class DartRepo
{
    /// <summary>从测试二进制往上找仓库根（含 `packages/quizsync_core`）。</summary>
    public static string Root()
    {
        var probe = new DirectoryInfo(AppContext.BaseDirectory);
        while (probe is not null)
        {
            if (Directory.Exists(Path.Combine(probe.FullName, "packages", "quizsync_core")))
            {
                return probe.FullName;
            }

            probe = probe.Parent;
        }

        throw new DirectoryNotFoundException("找不到产品仓根（需要 packages/quizsync_core）");
    }

    public static string Fixture(string name) =>
        File.ReadAllText(Path.Combine(Root(), "packages", "quizsync_core", "test", "fixtures", name));

    public static string PromptSource() =>
        File.ReadAllText(Path.Combine(Root(), "packages", "quizsync_core", "lib", "ai", "prompt.dart"));
}

/// <summary>
/// `ResponseParser` 的 5 步容错（`ai-contract.md` 第 3 节）——**用 Dart 侧同一批 fixture**，
/// 逐条对齐 `packages/quizsync_core/test/ai/response_parser_test.dart` 的期望。
/// </summary>
public sealed class ResponseParserTests
{
    [Fact]
    public void Step1_plain_json_decodes_directly()
    {
        var json = ResponseParser.TryParseJson(DartRepo.Fixture("single_choice.json"));
        Assert.NotNull(json);
        var parsed = ResponseParser.ToQuestions(json!, "s", "d", 1);
        Assert.Single(parsed.Questions);
        Assert.Equal(["B"], parsed.Questions[0].Choice);
        Assert.Equal(0, parsed.DroppedEmpty);
    }

    [Fact]
    public void Step2_markdown_fence_is_stripped()
    {
        var json = ResponseParser.TryParseJson(DartRepo.Fixture("markdown_fenced.md"));
        Assert.NotNull(json);
        var parsed = ResponseParser.ToQuestions(json!, "s", "d", 1);
        Assert.Equal("水的化学式是", parsed.Questions[0].Stem);
    }

    [Fact]
    public void Step3_surrounding_prose_is_trimmed_to_braces()
    {
        var json = ResponseParser.TryParseJson(DartRepo.Fixture("wrapped_json.txt"));
        Assert.NotNull(json);
        var parsed = ResponseParser.ToQuestions(json!, "s", "d", 1);
        Assert.Equal(["A"], parsed.Questions[0].Choice);
    }

    [Fact]
    public void Multi_and_judge_fixture_keeps_order_and_ordinals()
    {
        var json = ResponseParser.TryParseJson(DartRepo.Fixture("multi_and_judge.json"));
        Assert.NotNull(json);
        var parsed = ResponseParser.ToQuestions(json!, "s", "d", 1);
        Assert.Equal(2, parsed.Questions.Count);
        Assert.Equal(QuestionType.MultiChoice, parsed.Questions[0].Type);
        Assert.Equal(QuestionType.Judge, parsed.Questions[1].Type);
        Assert.Equal(0, parsed.Questions[0].Ordinal);
        Assert.Equal(1, parsed.Questions[1].Ordinal);
    }

    [Fact]
    public void Invalid_text_and_empty_string_yield_null()
    {
        Assert.Null(ResponseParser.TryParseJson(DartRepo.Fixture("invalid.txt")));
        Assert.Null(ResponseParser.TryParseJson(string.Empty));
    }

    [Fact]
    public void Legal_json_with_empty_questions_is_accepted()
    {
        var json = ResponseParser.TryParseJson(DartRepo.Fixture("no_questions.json"));
        Assert.NotNull(json);
        Assert.Empty(ResponseParser.ToQuestions(json!, "s", "d", 1).Questions);
    }

    [Fact]
    public void Empty_stem_entries_are_dropped_and_counted()
    {
        const string text =
            """{"questions":[{"stem":"","type":"single","answer":{"choice":["A"]},"analysis":"","confidence":0.9},{"stem":"有效题","type":"single","answer":{"choice":["B"]},"analysis":"","confidence":0.9}]}""";
        var json = ResponseParser.TryParseJson(text);
        Assert.NotNull(json);
        var parsed = ResponseParser.ToQuestions(json!, "s", "d", 1);
        Assert.Single(parsed.Questions);
        Assert.Equal(1, parsed.DroppedEmpty);
        Assert.Equal("有效题", parsed.Questions[0].Stem);
    }

    [Fact]
    public void Judge_without_options_gets_auto_paired_options()
    {
        const string text =
            """{"questions":[{"stem":"这说法对吗","type":"judge","answer":{"choice":["对"]},"analysis":"","confidence":0.9}]}""";
        var parsed = ResponseParser.ToQuestions(ResponseParser.TryParseJson(text)!, "s", "d", 1);
        var question = parsed.Questions[0];
        Assert.Equal(["对", "错"], question.Options.Select(o => o.Label));
        Assert.Equal(["对"], question.Choice);
        Assert.False(question.Incomplete, "judge 自动补选项后不算不完整");
    }

    [Fact]
    public void Choice_labels_outside_options_are_dropped_and_warned()
    {
        const string text =
            """{"questions":[{"stem":"题","type":"single","options":[{"label":"A","text":"甲"}],"answer":{"choice":["C"]},"analysis":"","confidence":0.9}]}""";
        var parsed = ResponseParser.ToQuestions(ResponseParser.TryParseJson(text)!, "s", "d", 1);
        var question = parsed.Questions[0];
        Assert.Empty(question.Choice);
        Assert.Contains("答案与选项不匹配", question.Warnings);
        // 选项少于 2 项 → 不完整 + 标黄。
        Assert.True(question.Incomplete);
        Assert.True(question.NeedReview);
    }
}

/// <summary>
/// prompt 是**逐字契约**：C# 侧的常量必须与 Dart 侧源码算出的哈希一致 ——
/// 两边不等就说明有人只改了一边（这正是不许手抄的原因）。
/// </summary>
public sealed class PromptVersionTests
{
    [Fact]
    public void Prompt_hash_matches_the_dart_source()
    {
        var dartSource = DartRepo.PromptSource();
        var match = Regex.Match(dartSource, @"const String kAiPrompt = '''(.*?)''';", RegexOptions.Singleline);
        Assert.True(match.Success, "没能从 Dart 源码里提取 kAiPrompt");
        // Dart 的 `\$` 是转义的美元号（运行时就是 `$`）；其余反斜杠原样保留。
        var dartPrompt = match.Groups[1].Value.Replace("\\$", "$", StringComparison.Ordinal);

        var dartHash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(dartPrompt)))[..8];
        Assert.Equal($"v1-{dartHash}", Prompt.ComputePromptVersion());
        // 逐字一致：C# 的常量就是 Dart 运行时那个字符串。
        Assert.Equal(Prompt.AiPrompt, dartPrompt);
    }

    [Fact]
    public void Prompt_keeps_the_contractual_paragraphs()
    {
        Assert.Contains("你是一个专业的解题助手", Prompt.AiPrompt, StringComparison.Ordinal);
        Assert.Contains("【输出格式】", Prompt.AiPrompt, StringComparison.Ordinal);
        Assert.Contains("has_answer_in_image", Prompt.AiPrompt, StringComparison.Ordinal);
        Assert.Contains("解析要在保证正确的前提下尽量简短", Prompt.AiPrompt, StringComparison.Ordinal);
    }

    [Fact]
    public void Prompt_version_is_stable_and_well_formed()
    {
        var version = Prompt.ComputePromptVersion();
        Assert.Matches("^v1-[0-9a-f]{8}$", version);
        Assert.Equal(version, Prompt.ComputePromptVersion());
    }
}
