using QuizSync.Core;
using QuizSync.Data;
using QuizSync.Provider;
using Xunit;

namespace QuizSync.Tests;

/// <summary>
/// 识别编排（缓存 → 配额 → 重试 → 解析 → 严格提醒重试 → 记录用量）。
/// 与 Dart 侧 `AnalysisEngine` 同一套语义，全部用假 provider（**不出网**）。
/// </summary>
public sealed class AnalysisEngineTests
{
    private const string SingleQuestion =
        """{"questions":[{"stem":"题目","type":"single","options":[{"label":"A","text":"甲"},{"label":"B","text":"乙"}],"answer":{"choice":["B"]},"analysis":"解析","confidence":0.9}]}""";

    private static QuizDatabase NewDatabase() => QuizDatabase.CreateFromProtocolSchema(":memory:");

    private static AiConfig Config(int maxRetries = 0) => new()
    {
        ProviderId = "fake",
        Model = "m",
        ApiKey = "k",
        MaxRetries = maxRetries,
    };

    private static AnalysisEngine Engine(
        QuizDatabase database, IAiProvider provider, int dailyLimit = 200, int maxRetries = 0) =>
        new(provider,
            new AnalysisCache(database),
            new QuotaGuard(database, dailyLimit),
            deviceId: "dev-1",
            retry: new RetryPolicy(maxRetries, _ => Task.CompletedTask));

    private static byte[] Page(byte value = 0xD8) => [0xFF, value, 0x01];

    [Fact]
    public async Task Happy_path_returns_questions_and_records_usage()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider(SingleQuestion);

        var outcome = await Engine(database, provider).AnalyzeImageAsync(Page(), "hash-1", Config());

        Assert.True(outcome.Ok);
        Assert.Single(outcome.Questions);
        Assert.Equal(["B"], outcome.Questions[0].Choice);
        Assert.Equal(1, outcome.ProviderCalls);
        Assert.False(outcome.FromCache);

        var quota = new QuotaGuard(database);
        Assert.Equal(1, quota.UsedToday()); // 成功也记用量（统计用）
    }

    [Fact]
    public async Task Cache_hit_skips_the_api_and_does_not_consume_quota()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider(SingleQuestion);
        var engine = Engine(database, provider);
        var config = Config();

        var first = await engine.AnalyzeImageAsync(Page(), "hash-1", config);
        Assert.False(first.FromCache);

        // 把首次结果写成一条 done 会话（缓存就是这么存的）。
        var promptVersion = Prompt.ComputePromptVersion();
        using (var command = database.Connection.CreateCommand())
        {
            command.CommandText = """
                INSERT INTO sessions (session_id, image_hash, source_device, status, ai_model, prompt_version,
                                      created_at, updated_at, updated_by, question_count)
                VALUES ('s-1', 'hash-1', 'dev-1', 'done', 'm', $prompt, $at, $at, 'dev-1', 1)
                """;
            command.Parameters.AddWithValue("$prompt", promptVersion);
            command.Parameters.AddWithValue("$at", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            command.ExecuteNonQuery();
            command.CommandText = """
                INSERT INTO questions (question_id, session_id, ordinal, stem, type, answer_text, analysis, confidence,
                                       options_json, choice_json, warnings_json, created_at, updated_at, updated_by)
                VALUES ('q-1', 's-1', 0, '缓存题', 'single', 'B', '', 0.9, '[]', '[]', '[]', 1, 1, 'dev-1')
                """;
            command.ExecuteNonQuery();
        }

        var callsBefore = provider.CallCount;
        var second = await engine.AnalyzeImageAsync(Page(), "hash-1", config);

        Assert.True(second.FromCache);
        Assert.Equal("s-1", second.CacheSessionId);
        Assert.Equal("缓存题", second.Questions[0].Stem);
        Assert.Equal(callsBefore, provider.CallCount); // 没再调 API
        Assert.Equal(1, new QuotaGuard(database).UsedToday()); // 也没有多记一次用量
    }

    [Fact]
    public async Task Multi_page_never_uses_the_cache()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider(SingleQuestion);
        var engine = Engine(database, provider);

        var first = await engine.AnalyzeImagesAsync([Page(0xD8), Page(0xD9)], "hash-1", Config());
        Assert.False(first.FromCache);
        Assert.Equal(1, first.ProviderCalls); // 直接真调用，没有先查缓存

        // 同一「首页哈希」再跑一次多页：仍然不命中缓存。
        var second = await engine.AnalyzeImagesAsync([Page(0xD8), Page(0xD9)], "hash-1", Config());
        Assert.False(second.FromCache);
    }

    [Fact]
    public async Task Quota_exhausted_returns_a_clear_error_without_calling_ai()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider(SingleQuestion);
        var engine = Engine(database, provider, dailyLimit: 1);
        var config = Config();

        await engine.AnalyzeImageAsync(Page(), "hash-1", config);   // 用掉唯一一次
        var blocked = await engine.AnalyzeImageAsync(Page(0xD9), "hash-2", config);

        Assert.Equal("ai_quota_exceeded", blocked.ErrorCode);
        Assert.Empty(blocked.Questions);
        Assert.Equal(1, provider.CallCount); // 明确提示，不是静默失败
    }

    [Fact]
    public async Task Unparseable_response_triggers_the_strict_reminder_retry()
    {
        using var database = NewDatabase();
        // 第一次给解释文字，第二次给合法 JSON，并检查提示词里带了严格提醒。
        var provider = new RecordingProvider(["这是一段解释，不是 JSON", SingleQuestion]);
        var engine = new AnalysisEngine(
            provider, new AnalysisCache(database), new QuotaGuard(database), "dev-1",
            new RetryPolicy(0, _ => Task.CompletedTask));

        var outcome = await engine.AnalyzeImageAsync(Page(), "hash-1", Config());

        Assert.True(outcome.Ok);
        Assert.Equal(2, outcome.ProviderCalls);
        Assert.Equal(2, provider.Prompts.Count);
        Assert.Contains(Prompt.StrictJsonReminder, provider.Prompts[1], StringComparison.Ordinal);
        // 第 4 步不占网络重试预算：网络重试次数为 0 也能走这一步。
    }

    [Fact]
    public async Task Still_unparseable_keeps_the_raw_text_and_marks_failure()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider("完全不是 JSON", "还是不是 JSON");
        var engine = Engine(database, provider);

        var outcome = await engine.AnalyzeImageAsync(Page(), "hash-1", Config());

        Assert.True(outcome.ParseFailed);
        Assert.Equal("ai_bad_response", outcome.ErrorCode);
        Assert.Equal("还是不是 JSON", outcome.RawText); // 保留原文供人工查看
        Assert.Equal(2, outcome.ProviderCalls);

        // 失败也记用量，并带上错误码。
        using var command = database.Connection.CreateCommand();
        command.CommandText = "SELECT ok, error_code FROM ai_usage ORDER BY rowid DESC LIMIT 1";
        using var reader = command.ExecuteReader();
        Assert.True(reader.Read());
        Assert.Equal(0, reader.GetInt32(0));
        Assert.Equal("ai_bad_response", reader.GetString(1));
    }

    [Fact]
    public async Task Valid_json_without_questions_reports_no_question_found()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider("""{"questions":[]}""");

        var outcome = await Engine(database, provider).AnalyzeImageAsync(Page(), "hash-1", Config());

        Assert.Equal("no_question_found", outcome.ErrorCode);
        Assert.Empty(outcome.Questions);
        Assert.Equal(1, outcome.ProviderCalls);
    }

    [Fact]
    public async Task Retryable_provider_errors_are_retried_then_mapped_to_local_codes()
    {
        using var database = NewDatabase();
        // 超时：可重试 → 用完 1 次重试预算后仍失败。
        var provider = FakeAiProvider.Failing(new AiException(AiErrorKind.Timeout, "慢"), times: 5);
        var outcome = await Engine(database, provider, maxRetries: 1).AnalyzeImageAsync(Page(), "hash-1", Config(1));

        Assert.Equal("ai_timeout", outcome.ErrorCode);
        Assert.Equal(2, outcome.ProviderCalls); // 1 次 + 1 次重试
        Assert.Empty(outcome.Questions);
    }

    [Theory]
    [InlineData(AiErrorKind.Timeout, "ai_timeout")]
    [InlineData(AiErrorKind.Auth, "ai_auth")]
    [InlineData(AiErrorKind.RateLimited, "ai_rate_limited")]
    [InlineData(AiErrorKind.BadRequest, "ai_bad_response")]
    [InlineData(AiErrorKind.Network, "internal")]
    [InlineData(AiErrorKind.ServerError, "internal")]
    [InlineData(AiErrorKind.Unknown, "internal")]
    public void Error_kinds_map_to_the_contract_codes(AiErrorKind kind, string expected)
    {
        Assert.Equal(expected, AnalysisEngine.ErrorCodeFor(new AiException(kind, "m")));
    }

    [Fact]
    public async Task Empty_page_list_is_rejected_before_any_call()
    {
        using var database = NewDatabase();
        var provider = new FakeAiProvider(SingleQuestion);

        var outcome = await Engine(database, provider).AnalyzeImagesAsync([], "hash-1", Config());

        Assert.Equal("internal", outcome.ErrorCode);
        Assert.Equal(0, provider.CallCount);
    }

    /// <summary>记录每次调用的提示词，用来验证「严格提醒」确实附上去了。</summary>
    private sealed class RecordingProvider(IReadOnlyList<string> responses) : IAiProvider
    {
        private int _calls;

        public string Id => "recording";

        public List<string> Prompts { get; } = [];

        public Task<AiRawResponse> AnalyzeAsync(
            IReadOnlyList<byte[]> jpegBytesList, string prompt, AiConfig config, CancellationToken cancellationToken = default)
        {
            Prompts.Add(prompt);
            var index = Math.Min(_calls, responses.Count - 1);
            _calls++;
            return Task.FromResult(new AiRawResponse(responses[index], 1));
        }
    }
}
