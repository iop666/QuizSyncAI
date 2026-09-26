using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace QuizSync.App;

/// <summary>
/// 悬浮球设置（`<app>/ball.json`）。
///
/// **单独一个文件**，不塞进 `ai.json`：AI 配置与界面配置是两件事，
/// 混在一起以后每加一项界面设置都要动 AI 的结构。
///
/// 1.1.0 的历史（`AGENTS.md` 记着）：用户反馈过「悬浮球的大小/透明度/描边/开关**四项全都调不动**」——
/// 当年的根因是 Riverpod 直接 `listen` `ChangeNotifierProvider` 时 `prev == next`。
/// 这里是 C#，不存在那个坑；但**「改设置要真的生效」这条要求一模一样**，
/// 所以每一项改完都必须**量出来**，不能只看代码对不对。
/// </summary>
internal sealed class BallSettings
{
    private const string FileName = "ball.json";

    /// <summary>默认与 1.1.0 对齐：开、直径 40、不透明度 100%（`AGENTS.md` M17：默认 40 / 70% 描边）。</summary>
    internal bool Enabled { get; set; } = true;

    internal int Diameter { get; set; } = 40;

    internal int Opacity { get; set; } = 100;

    /// <summary>
    /// 上次拖动到的位置（**可空**：null = 还没拖过，用默认位置「右侧垂直居中」）。
    /// 记下来是为了「下次启动还在我放的地方」—— 1.1.0 里球每次启动都回默认位置，用户会重复拖。
    /// </summary>
    internal int? X { get; set; }

    internal int? Y { get; set; }

    /// <summary>描边开关。1.1.0 的默认是「开」（`AGENTS.md` M17）。</summary>
    internal bool Stroke { get; set; } = true;

    /// <summary>描边宽度（像素）。**画在球的外面**，所以窗口尺寸 = 球 + 2 × 这个值。</summary>
    internal int StrokeWidth { get; set; } = 4;

    private static string FilePath => Path.Combine(AppDataDirectory.Ensure(), FileName);

    /// <summary>读设置。文件不存在或坏了都退回默认值（不因为一个坏配置让球消失）。</summary>
    internal static BallSettings Load()
    {
        var settings = new BallSettings();
        if (!File.Exists(FilePath))
        {
            return settings;
        }

        try
        {
            if (JsonNode.Parse(File.ReadAllText(FilePath)) is JsonObject json)
            {
                settings.Enabled = json["enabled"]?.GetValue<bool>() ?? settings.Enabled;
                // 夹到合理范围：配置是给用户改的，不能因为写了 0 或 9999 就画出个怪东西。
                settings.Diameter = Math.Clamp(json["diameter"]?.GetValue<int>() ?? settings.Diameter, 24, 160);
                settings.Opacity = Math.Clamp(json["opacity"]?.GetValue<int>() ?? settings.Opacity, 20, 100);
                settings.X = json["x"]?.GetValue<int>();
                settings.Y = json["y"]?.GetValue<int>();
                settings.Stroke = json["stroke"]?.GetValue<bool>() ?? settings.Stroke;
                settings.StrokeWidth = Math.Clamp(json["stroke_width"]?.GetValue<int>() ?? settings.StrokeWidth, 0, 12);
            }
        }
        catch (Exception error) when (error is JsonException or FormatException or InvalidOperationException)
        {
            return new BallSettings();
        }

        return settings;
    }

    internal void Save()
    {
        var json = new JsonObject
        {
            ["enabled"] = Enabled,
            ["diameter"] = Diameter,
            ["opacity"] = Opacity,
            ["x"] = X,
            ["y"] = Y,
            ["stroke"] = Stroke,
            ["stroke_width"] = StrokeWidth,
        };

        File.WriteAllText(FilePath, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }
}
