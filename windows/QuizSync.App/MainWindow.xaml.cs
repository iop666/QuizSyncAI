using Microsoft.UI.Xaml;

namespace QuizSync.App;

/// <summary>
/// 外壳主窗口：**只做导航宿主**（Frame），页面各自在 <c>Pages/</c> 下。
///
/// 第五轮之前这里是一个「整窗铺白 + 居中堆一列文字」的 Grid —— 用户当场质问
/// 「你这真的是 winui 3 吗，怎么不像」。技术上是 WinUI 3，但没有任何 Fluent 结构。
/// 改成 Frame + Page 之后，欢迎页与配对页是真正的 WinUI 页面，导航也走 WinUI 的方式。
/// </summary>
public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        // 标题只认唯一的那个常量（XAML 里那份只是设计器预览用的写法，这里覆盖掉）。
        Title = QuizSync.Provider.AppWindowScope.Title;
        RootFrame.Navigate(typeof(Pages.WelcomePage));
    }
}
