using QuizSync.Core;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 标绿规则（`ai-contract.md` 第 5 节 + `SPEC.md` 4.3）：**端侧显示的唯一依据**。
/// 与 Dart 侧 `test/ai/highlight_test.dart` 同一套判据。
/// </summary>
public sealed class HighlightTests
{
    private static Question Question(
        QuestionType type,
        IReadOnlyList<Option> options,
        IReadOnlyList<string>? choice = null,
        string? answerText = null,
        double confidence = 0.95,
        bool needReview = false) => new()
    {
        QuestionId = "q-1",
        SessionId = "s-1",
        Ordinal = 0,
        Type = type,
        Options = options,
        Choice = choice ?? [],
        AnswerText = answerText,
        Confidence = confidence,
        NeedReview = needReview,
        UpdatedBy = "test",
    };

    private static readonly Option[] SingleOptions = [new("A", "甲"), new("B", "乙"), new("C", "丙")];

    [Fact]
    public void Single_choice_answer_marks_exactly_that_option()
    {
        var result = Highlight.Compute(Question(QuestionType.SingleChoice, SingleOptions, choice: ["B"]));
        Assert.Equal(["B"], result.OptionLabels);
        Assert.True(result.HasAnyHighlight);
        Assert.False(result.NoAnswer);
        Assert.False(result.NeedsReview);
        Assert.False(result.IsJudge);
    }

    [Fact]
    public void Multi_choice_answer_marks_every_hit()
    {
        var result = Highlight.Compute(Question(QuestionType.MultiChoice, SingleOptions, choice: ["A", "C"]));
        Assert.Equal(["A", "C"], result.OptionLabels.OrderBy(x => x, StringComparer.Ordinal));
        Assert.False(result.NoAnswer);
    }

    [Fact]
    public void Judge_question_sets_the_judge_flag()
    {
        var options = new Option[] { new("对", "对"), new("错", "错") };
        var result = Highlight.Compute(Question(QuestionType.Judge, options, choice: ["错"]));
        Assert.True(result.IsJudge);
        Assert.Equal(["错"], result.OptionLabels);
    }

    [Fact]
    public void Choice_that_matches_no_option_means_no_answer_and_needs_review()
    {
        var result = Highlight.Compute(Question(QuestionType.SingleChoice, SingleOptions, choice: ["Z"]));
        Assert.Empty(result.OptionLabels);
        Assert.True(result.NoAnswer);
        Assert.True(result.NeedsReview);
        Assert.False(result.HasAnyHighlight);
    }

    [Fact]
    public void Fill_in_answer_highlights_the_text()
    {
        var result = Highlight.Compute(Question(QuestionType.Blank, [], answerText: "H2O"));
        Assert.True(result.HighlightAnswerText);
        Assert.True(result.HasAnyHighlight);
        Assert.False(result.NoAnswer);
    }

    [Fact]
    public void No_answer_at_all_means_no_highlight_and_needs_review()
    {
        var result = Highlight.Compute(Question(QuestionType.SingleChoice, SingleOptions));
        Assert.False(result.HasAnyHighlight);
        Assert.True(result.NoAnswer);
        Assert.True(result.NeedsReview);
    }

    [Fact]
    public void Low_confidence_or_need_review_shows_the_yellow_badge()
    {
        var lowConfidence = Highlight.Compute(
            Question(QuestionType.SingleChoice, SingleOptions, choice: ["A"], confidence: 0.5));
        Assert.True(lowConfidence.NeedsReview);
        Assert.Equal(["A"], lowConfidence.OptionLabels);

        var flagged = Highlight.Compute(
            Question(QuestionType.SingleChoice, SingleOptions, choice: ["A"], needReview: true));
        Assert.True(flagged.NeedsReview);

        // 0.6 是阈值本身：不低于就不标黄。
        var boundary = Highlight.Compute(
            Question(QuestionType.SingleChoice, SingleOptions, choice: ["A"], confidence: 0.6));
        Assert.False(boundary.NeedsReview);
    }

    [Fact]
    public void Choice_but_no_options_falls_back_to_no_answer()
    {
        // 没有选项就没有可标绿的行（数据异常时不许瞎标）。
        var result = Highlight.Compute(Question(QuestionType.SingleChoice, [], choice: ["A"]));
        Assert.Empty(result.OptionLabels);
        Assert.True(result.NoAnswer);
        Assert.True(result.NeedsReview);
    }
}
