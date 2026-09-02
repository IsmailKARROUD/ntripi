"""
constants/help/zh.py — the Chinese help centre.

English (en.py) is authoritative and is the route table. Everything
structural — slug, category, schema, block anchors and kinds, related, the
updated date — is identical to en.py by construction: the anchor is both the
in-page fragment and the HowToStep url, and `kind` is what FAQPage.mainEntity
and HowTo.step are built from, so a translation that moved one would empty the
structured data while the page still looked right.

`keywords` are the exception that is deliberately NOT a translation: they are
search synonyms, so they carry the words someone actually types in this
language rather than the English list rendered word for word.
"""

from __future__ import annotations

from app.constants.help.models import (
    KIND_DIAGRAM,
    KIND_FAQ,
    KIND_STEP,
    SCHEMA_CONTACT,
    SCHEMA_FAQ,
    SCHEMA_HOWTO,
    SCHEMA_RELEASES,
    Article,
    Block,
    Category,
    Release,
)

CATEGORIES: tuple[Category, ...] = (
    Category(
        id="getting-started",
        title="入门",
        blurb="创建账号，规划你的第一趟行程。",
        icon="rocket",
    ),
    Category(
        id="building",
        title="构建行程",
        blurb="停靠点、地点、交通，以及配套的提示。",
        icon="article",
    ),
    Category(
        id="sharing",
        title="分享与可见性",
        blurb="决定谁能看到行程，以及如何发给他们。",
        icon="lock",
    ),
    Category(
        id="community",
        title="社区",
        blurb="关注、评分、已保存的行程和动态。",
        icon="group",
    ),
    Category(
        id="account",
        title="账号与设置",
        blurb="登录、通知、权限和你的数据。",
        icon="person",
    ),
    Category(
        id="safety",
        title="安全与审核",
        blurb="举报、屏蔽、被隐藏的内容和申诉。",
        icon="flag",
    ),
    Category(
        id="troubleshooting",
        title="疑难解答",
        blurb="当某些功能不像你预期的那样工作时。",
        icon="warning",
    ),
    Category(
        id="about",
        title="关于 Ntripi",
        blurb="联系我们，以及最新版本有哪些变化。",
        icon="info",
    ),
)

RELEASES: tuple[Release, ...] = (
    Release(
        version="0.3.0",
        date="2026-09-01",
        headline="协作编辑、推送通知和帮助中心",
        entries=(
            "**邀请他人编辑行程。**行程所有者现在可以把编辑权限授予其他账号，同一时间只有一人编辑，谁的成果都不会被覆盖。",
            "**推送通知**已在 iOS 和 Android 上线，涵盖关注、评分、保存和审核通知。",
            "**这个帮助中心**，上述内容都写在了这里。",
        ),
    ),
)

ARTICLES: tuple[Article, ...] = (
    Article(
        slug="getting-started",
        title="如何在 Ntripi 中开始规划一趟行程",
        summary="创建账号，认识五个标签页，几分钟内搭好你的第一份行程计划。",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="‏Ntripi 是一款旅行应用，用真实的停靠点搭建行程计划——每个停靠点的花费、需要多久、以及彼此之间怎么走——并分享给你选定的人。创建账号，打开**行程**标签页，添加你的第一趟行程。",
        blocks=(
            Block(
                anchor="create-an-account",
                heading="创建账号",
                kind=KIND_STEP,
                body="""注册有三种方式：使用电子邮箱和密码、**使用 Google 登录**，或**使用 Apple 登录**。三种方式最终都到同一个地方。

系统会要求你填写显示名称、用户名和出生日期。Ntripi 的最低年龄要求是 16 岁。你的出生日期永远不会出现在个人资料中，其他用户也无法看到。

显示名称可以是任何内容、任何语言，最多 50 个字符。用户名是别人用来找到你的 `@名称`，如果你一直没设置显示名称，展示的就是它。""",
            ),
            Block(
                anchor="verify-your-email",
                heading="验证你的邮箱地址",
                kind=KIND_STEP,
                body="""在邮箱验证之前，有些操作会被暂缓：创建行程、给行程评分，以及关注他人。这能把一次性账号挡在评分之外。

请在收件箱里找验证链接。如果你用同一个邮箱通过 Google 注册，那么用 Google 登录就会替你完成验证——个人资料上的提示条会提供这个选项。""",
            ),
            Block(
                anchor="the-five-tabs",
                heading="熟悉界面：五个标签页",
                kind=KIND_STEP,
                body="""底部栏有五个标签页，自左至右：

- **搜索** — 找的是*人*，不是行程。按用户名搜索。
- **个人资料** — 你自己的资料页，以及打开全部设置的齿轮图标。
- **行程** — 你拥有的行程，以及别人邀请你编辑的行程。
- **已保存** — 你收藏的行程。
- **动态** — 所有人的公开行程，可按**热门**和**最新**排序。

个人资料页上齿轮旁边的铃铛会打开你的通知。""",
            ),
            Block(
                anchor="build-your-first-trip",
                heading="搭建第一趟行程",
                kind=KIND_STEP,
                body="""打开**行程**并点按 **+**。给行程起个标题，选好记录花费用的货币，然后开始添加停靠点。

新行程在你更改设置之前**仅自己可见**，所以放心试。完整流程见[如何规划一份行程](/help/plan-a-trip-itinerary)。""",
            ),
            Block(
                anchor="where-to-get-help",
                heading="在应用内获取帮助",
                body="""大多数表单字段的标签旁都有一个小小的 **?** 图标。点一下就会说明该字段的用途，无需离开当前页面——这是理解陌生字段最快的方式。

**设置 ▸ 帮助中心**汇集了常见问题和联系我们的方式。如果有功能出了问题，见[如何报告故障](/help/contact)。""",
            ),
        ),
        keywords=(
            "注册",
            "新账号",
            "创建账号",
            "第一次",
            "新手",
            "入门",
            "基础",
            "开始",
            "怎么用",
            "上手",
        ),
        related=("plan-a-trip-itinerary", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="想规划点什么？开始你的第一趟行程。",
    ),
    Article(
        slug="plan-a-trip-itinerary",
        title="如何一步步规划一份旅行行程",
        summary="用真实的停靠点、花费、时间和交通搭建一份行程——从空白行程到可以分享出去。",
        category="getting-started",
        schema=SCHEMA_HOWTO,
        intro="‏Ntripi 里的一趟行程就是一串有序的停靠点。每个停靠点是一个真实地点，带有位置、大致花费，以及你预计停留的时长。停靠点之间记录你怎么移动。分四轮搭建：创建行程、添加停靠点、把它们连起来，然后决定谁能看到。",
        blocks=(
            Block(
                anchor="create-the-trip",
                heading="创建行程",
                kind=KIND_STEP,
                body="""在**行程**标签页点按 **+**。开始只需要一个标题；其余都可以稍后再说。

- **标题** — 这趟行程是什么。「马拉喀什四日游」胜过「摩洛哥」。
- **货币** — 你记录的每一笔花费都用它，总额才有意义。选你实际会花的那种。
- **封面图** — 可选，之后也能补。它是别人在动态和分享链接里看到的东西。
- **最佳时节** — 这趟行程适合的月份。对有季节性的安排很有用。""",
            ),
            Block(
                anchor="add-stops",
                heading="添加停靠点",
                kind=KIND_STEP,
                body="""在行程内点按 **+** 添加停靠点。一个停靠点包含：

- **名称和地址** — 这个地方叫什么。
- **位置** — 在地图上选点，或粘贴一个 Google 地图链接，让 Ntripi 从中读出坐标。
- **地点类型** — 餐饮、住宿、景点、自然、购物等等。它决定地图和列表里画出哪个图标。
- **花费** — 人均大致多少钱。可以留空，或标记为免费。
- **停留时长** — 要预留多久。它让计划变得现实，而不是一厢情愿。
- **备注** — 任何你想记住的事。

按你实际游览的顺序添加。之后随时可以拖动调整。""",
            ),
            Block(
                anchor="connect-the-stops",
                heading="记录你怎么在停靠点之间移动",
                kind=KIND_STEP,
                body="""两个停靠点之间可以添加一段**交通**：怎么走、要多久、多少钱。

一段交通可以包含多个路段——先坐公交到车站，再换火车——每个路段还能记下线路号和方向，而这恰恰是当天最想不起来的细节。""",
            ),
            Block(
                anchor="add-warnings-and-tips",
                heading="添加提醒和建议",
                kind=KIND_STEP,
                body="""任何停靠点以及整趟行程，都可以带上四类简短提示：**建议**、**注意**、**避免**和**信息**。它们以彩色标签呈现，很难被忽略。

「出发前先买票」和「北门关闭」就该写在这里——这些是一份光秃秃的行程永远不会告诉你的事。""",
            ),
            Block(
                anchor="choose-who-sees-it",
                heading="决定谁能看到",
                kind=KIND_STEP,
                body="""新行程从**仅自己**开始。准备好之后，打开行程设置，从四个级别里选一个——公开、粉丝、指定的人，或只有你自己。

每个级别在实际使用中意味着什么，见[如何不公开地分享行程](/help/share-an-itinerary-privately)。""",
            ),
        ),
        keywords=(
            "行程规划",
            "旅行行程",
            "行程",
            "逐日",
            "度假规划",
            "安排旅行",
            "路线",
            "日程",
            "停靠点",
            "预算",
            "花费",
            "计划",
        ),
        related=("plan-alternative-options", "share-an-itinerary-privately", "getting-started"),
        updated="2026-09-01",
        cta="规划属于你自己的行程——大约十分钟。",
    ),
    Article(
        slug="app-map",
        title="‏Ntripi 的界面和图标详解",
        summary="带你走一遍五个标签页、行程页面，以及沿途会遇到的各个图标。",
        category="getting-started",
        intro="‏Ntripi 底部有五个标签页，上方几乎没有多余的装饰。几乎所有可改的东西，要么藏在个人资料页的齿轮后面，要么藏在对元素本身的长按里。这一页把它们逐一点名。",
        blocks=(
            Block(
                anchor="bottom-nav",
                heading="五个标签页",
                kind=KIND_DIAGRAM,
                body="""1. **搜索** — 找的是**人**，不是行程。按用户名搜索。公开行程要通过动态来发现。
2. **个人资料** — 你自己的资料页。齿轮打开全部设置；旁边的铃铛打开通知。
3. **行程** — 你拥有的行程，以及另一个视图，放别人邀请你编辑的行程。
4. **已保存** — 你收藏的行程，带一个筛选框。
5. **动态** — 所有人的公开行程，可按**热门**和**最新**排序。

点按你当前所在的标签页会回到它的顶部，这是从深层页面退出来最快的方式。""",
            ),
            Block(
                anchor="itinerary-screen",
                heading="读懂一份行程",
                kind=KIND_DIAGRAM,
                body="""1. 标题下方的**可见性标签** — 谁能打开这趟行程。作为所有者，点它即可更改。
2. **出现第二列**意味着这两个停靠点互为备选方案，而非先后顺序。见[如何为同一天规划两个方案](/help/plan-alternative-options)。
3. 两个停靠点之间的**交通行** — 怎么从一个到另一个，以及要多久。
4. 停靠点上的**彩色标签**是一条提示：建议、注意、避免或信息。
5. **评分行** — 平均分以及有多少人评过。满三人之后才会显示平均分。""",
            ),
            Block(
                anchor="icons",
                heading="你会遇到的图标",
                body="""| 图标 | 作用 |
|---|---|
| **?** | 说明旁边的字段，无需离开页面 |
| 书签 | 把行程存进「已保存」标签页 |
| 铅笔 | 编辑——只有你有权限时才显示 |
| 旗帜 | 向我们举报 |
| 齿轮 | 设置，位于你自己的资料页 |
| 铃铛 | 通知，有新内容时带一个圆点 |

**?** 值得记住：几乎每个表单的每个字段都有一个，比跑到这里来更快。""",
            ),
            Block(
                anchor="long-press",
                heading="长按快捷操作",
                body="""在自己行程的某个部分上按住手指，会直接跳到编辑那一部分——标题、封面、某个停靠点、某条提示。省去了绕回编辑页面的麻烦。

在别人的行程上，同样的手势提供的是举报或屏蔽。两者永远不会重叠，所以你既不会误报自己的行程，也不会去改别人的。""",
            ),
        ),
        keywords=(
            "图标",
            "按钮",
            "菜单",
            "导航",
            "标签页",
            "在哪里",
            "这个按钮",
            "界面",
            "布局",
            "页面",
        ),
        related=("getting-started", "app-settings"),
        updated="2026-09-01",
        cta="亲自看看——打开 Ntripi。",
    ),
    Article(
        slug="plan-alternative-options",
        title="如何为同一天规划两个方案",
        summary="把备选地点并排放进同一趟行程，下雨天或另一种预算都不需要再做一份计划。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="大多数行程工具强制每个时段只能放一个地点。Ntripi 允许你把**备选方案并排堆放**：两三个地点占据行程中的同一个位置，由出行的人当天再定。这些纵列在内部称为**列**。",
        blocks=(
            Block(
                anchor="what-a-track-is",
                heading="什么是一列",
                body="""**一列**是一组纵向排列、互为备选的停靠点。只有一列的行程就是普通的单线行程。在同一个位置加上第二列，你就有了度过那段行程的两种方式。

只要答案是「看情况」，列就派得上用场：

- **天气** — 一个户外方案和一个室内方案。
- **预算** — 贵的餐厅和便宜又好的那家。
- **体力** — 长途徒步和短程散步。
- **口味** — 一半人去博物馆，另一半去市集。""",
            ),
            Block(
                anchor="add-an-alternative",
                heading="添加一个备选方案",
                kind=KIND_STEP,
                body="""打开行程，找到你想为其添加备选的停靠点。用它旁边的添加控件，选择把新停靠点放进**新的一列**，而不是接在现有停靠点后面。

两个停靠点现在并排。哪个都不是「真正的那个」——它们地位相同，读到这趟行程的人两个都会看到。""",
            ),
            Block(
                anchor="move-a-stop",
                heading="在列之间移动停靠点",
                kind=KIND_STEP,
                body="""停靠点事后可以移到另一列，所以你不会被添加时碰巧的顺序绑住。打开停靠点，用移动操作选择它所属的列。

一列只有在至少含一个停靠点时才存在。移走或删掉最后一个停靠点，空列会自行消失——没有什么需要收拾。""",
            ),
            Block(
                anchor="reorder",
                heading="重新排列列和停靠点",
                kind=KIND_STEP,
                body="拖动即可调整一列内停靠点的顺序，也可以调整列本身的顺序。行程中的第一列被视为起点，最后一列被视为终点，地图连的就是这两者之间。",
            ),
            Block(
                anchor="transport-warning",
                heading="为什么插入一列有时会弹出提示",
                body="""交通是记录在两个*相邻*列之间的。如果你在两个已经有交通相连的列之间插入新的一列，那段连接就无处安放了——两列不再相邻。

‏Ntripi 会先询问，而不是悄悄丢掉你填过的交通。确认则删除受影响的连接；取消则什么都不变。""",
            ),
        ),
        keywords=(
            "并行",
            "并列",
            "列",
            "备选",
            "备选方案",
            "选项",
            "可选",
            "备用",
            "分支",
            "二选一",
            "雨天",
            "天气",
            "选择",
        ),
        related=("plan-a-trip-itinerary", "getting-started"),
        updated="2026-09-01",
        cta="规划一趟有真正备选方案的行程，而不是一条脆弱的单线。",
    ),
    Article(
        slug="add-places-to-an-itinerary",
        title="如何为行程计划添加地点、花费和时间",
        summary="一个停靠点能装下的全部内容——它是什么、在哪里、多少钱，以及要预留多久。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="停靠点是你真的会去的一个地方。除了名字之外，让计划真正可用的是两个字段：**花费**和**停留时长**——正是它们把一串地点变成可以做预算、能塞进一天的东西。",
        blocks=(
            Block(
                anchor="add-a-stop",
                heading="添加停靠点",
                kind=KIND_STEP,
                body="""打开行程并点按 **+**。给这个地方起个名字——你会脱口而出的那个，而不是它的官方名称——有地址的话也填上。

停靠点按游览顺序添加。之后随时可以拖成别的顺序。""",
            ),
            Block(
                anchor="place-type",
                heading="选择地点类型",
                kind=KIND_STEP,
                body="""地点类型决定地图和列表里画出哪个图标，让一天的安排一眼可读。共有十一种：

- **餐饮** · **住宿** · **购物**
- **学习与参观** · **景点** · **娱乐**
- **运动与观赛** · **自然** · **理疗与沐浴**
- **宗教场所** · **交通**

这一项可选。没有类型的停靠点照样能用；只是看起来和其他没类型的一样。""",
            ),
            Block(
                anchor="cost",
                heading="记录花费",
                kind=KIND_STEP,
                body="""填入**人均**的大致花费，用行程的货币。估个数就行——重点是最后的总额，不是一张发票。

如果某个地方免费，请标记为免费，而不是把字段留空。留空意味着「我还没查」，这个区别对读你计划的人很重要。""",
            ),
            Block(
                anchor="time-to-spend",
                heading="记录要预留多久",
                kind=KIND_STEP,
                body="""这个字段能让计划不至于沦为空想。一个下午安排四个景点，写成列表看着合理，等每个都标上九十分钟就变得不可能了。

按你真正想在那里待多久来预留，而不是按最快能逛完的时间。""",
            ),
            Block(
                anchor="notes",
                heading="写下自己的备注",
                body="""备注字段是自由文本——预订号、点什么菜、走哪个入口、为什么选这里而不是隔壁那家。

如果某条提醒应该显眼到难以忽略，而不是被顺带读过，请改用[建议或注意提示](/help/travel-notes-and-warnings)：那些会显示为彩色标签。""",
            ),
        ),
        keywords=(
            "停靠点",
            "地点",
            "景点",
            "添加",
            "预算",
            "价格",
            "时长",
            "要多久",
            "分类",
            "餐厅",
            "酒店",
            "博物馆",
        ),
        related=("plan-a-trip-itinerary", "add-locations-from-google-maps", "travel-notes-and-warnings"),
        updated="2026-09-01",
        cta="开一趟行程，添加你的第一个停靠点。",
    ),
    Article(
        slug="add-locations-from-google-maps",
        title="如何通过 Google 地图链接添加地点",
        summary="粘贴一个地图链接，Ntripi 会从中读出坐标；也可以自己在地图上放置图钉。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="停靠点获取位置有两种方式：在 Ntripi 自己的地图上选点，或者粘贴一个 Google 地图链接，让 Ntripi 从中读出坐标。后者通常更快，因为你多半已经在那里找到过这个地方了。",
        blocks=(
            Block(
                anchor="paste-a-link",
                heading="粘贴 Google 地图链接",
                kind=KIND_STEP,
                body="""在停靠点的位置字段中切换到链接选项，粘贴网址。Ntripi 会提取坐标并保留该链接，于是停靠点会显示一小块地图预览，之后你也能在地图应用中打开这个地方。

桌面端的长网址和分享用的短链接都可以。只接受 Google 地图的地址——指向其他站点的链接会被拒绝，而不是存下来又被悄悄忽略。""",
            ),
            Block(
                anchor="pick-on-the-map",
                heading="或者自己放置图钉",
                kind=KIND_STEP,
                body="""切换到坐标并打开地图选点器。平移和缩放到目标位置，中心的图钉就是会被保存的点。

对于地图上没有条目的地方，这个方式更合适——一处观景点、一个步道入口、一片无名海滩。""",
            ),
            Block(
                anchor="locate-me",
                heading="把地图定位到你所在的位置",
                kind=KIND_STEP,
                body="""定位按钮会把地图移到你当前的位置，省得你横跨一个大洲去找自己正站着的这座城市。

首次使用时会请求位置权限。**拒绝不会影响任何功能**——地图只是从别处打开，你自己平移过去即可。见 [Ntripi 会请求哪些权限](/help/permissions)。""",
            ),
            Block(
                anchor="opening-in-maps",
                heading="在你的地图应用中打开停靠点",
                body="""带位置的停靠点会提供在你已安装的地图应用中打开的选项，这样当天不用重新输入就能获得导航。

‏Ntripi 的地图用来读计划；你的地图应用用来照着走。""",
            ),
        ),
        keywords=(
            "谷歌地图",
            "链接",
            "粘贴",
            "坐标",
            "定位",
            "图钉",
            "位置",
            "地图选点",
            "经纬度",
            "在哪",
        ),
        related=("add-places-to-an-itinerary", "permissions"),
        updated="2026-09-01",
        cta="把你的第一个停靠点标在地图上。",
    ),
    Article(
        slug="plan-transport-between-stops",
        title="如何规划停靠点之间的交通",
        summary="记录你怎么从一个地方到下一个——方式、时间、花费，以及你一定记不住的线路号。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="任意两个停靠点之间，你都可以记录一段**交通**：怎么走、要多久、多少钱。一段交通可以有多个路段，于是「先公交再火车」仍然是一次连接，而不是两段无从解释的空白。",
        blocks=(
            Block(
                anchor="add-a-segment",
                heading="添加一段连接",
                kind=KIND_STEP,
                body="""在两个停靠点之间使用添加交通的控件。选择方式——步行、骑行、公交、火车、地铁、出租车、自驾、渡轮、航班——并填上时长。

花费按人计，使用行程的货币，会和停靠点一起计入行程总额。""",
            ),
            Block(
                anchor="multiple-legs",
                heading="添加多个路段",
                kind=KIND_STEP,
                body="""一段路程很少只用一种交通工具。为每一部分各加一个路段——走到站点、公交、换乘、火车——每段各自保留方式和时长。

这样这次连接显示的就是真实的门到门时间，而这个数字决定了这个下午的安排成不成立。""",
            ),
            Block(
                anchor="line-and-direction",
                heading="记下线路和方向",
                kind=KIND_STEP,
                body="""每个路段都可以记下线路——`M4`、`12路`、`RER B`——以及方向，也就是车头显示的终点站。

方向才是当天真正要紧的细节。在一个双向发车的站台上，知道自己要坐 M4 一点忙也帮不上。""",
            ),
            Block(
                anchor="orphaned-connections",
                heading="为什么插入停靠点可能会弹出提示",
                body="""一次连接存在于*两个相邻者之间*。如果你在两个已有连接的列之间插入新的一列，那段连接就没有位置了。

‏Ntripi 会先询问，而不是悄悄丢掉你填过的内容。确认则删除受影响的连接；取消则什么都不变。""",
            ),
        ),
        keywords=(
            "交通",
            "公交",
            "地铁",
            "火车",
            "出租车",
            "打车",
            "步行",
            "开车",
            "航班",
            "换乘",
            "路段",
            "怎么去",
        ),
        related=("add-places-to-an-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="把一段行程连同换乘一起画出来。",
    ),
    Article(
        slug="travel-notes-and-warnings",
        title="如何为行程添加旅行提醒和建议",
        summary="四类提示——建议、注意、避免和信息——以彩色标签呈现，没人会一划而过。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="旅途中出岔子的地方，往往不在旅行指南里。Ntripi 有四类提示——**建议**、**注意**、**避免**和**信息**——可以挂在某个停靠点上，也可以挂在整趟行程上，并绘制成彩色标签，让读者是撞见它们，而不是去翻找。",
        blocks=(
            Block(
                anchor="the-four-types",
                heading="每一类的用途",
                body="""- **建议** — 这样做会更顺利。「网上买票，现场排队要一小时。」
- **注意** — 没问题，但要留神。「晚上人多；包背在身前。」
- **避免** — 别这么做。「门口的出租车站要价虚高；走两条街再拦车。」
- **信息** — 值得知道，无需行动。「周二闭馆。」

类型只改变颜色和标签，所以请挑一个让陌生人读出你本意的那种。""",
            ),
            Block(
                anchor="add-to-a-stop",
                heading="给某个停靠点加提示",
                kind=KIND_STEP,
                body="""打开停靠点，在那里添加提示。它属于那个地点，你重排行程时它也会跟着走。

凡是关于某个特定入口、排队、开放时间或当地风险的内容，都该写在这里。""",
            ),
            Block(
                anchor="add-to-the-trip",
                heading="给整趟行程加提示",
                kind=KIND_STEP,
                body="""从行程本身出发添加的提示适用于整趟行程——签证要求、季节、哪张 SIM 卡能用、要带什么。

行程级的提示显示在靠上的位置、停靠点之前，因为通常得先读了它们才谈得上规划某一天。""",
            ),
            Block(
                anchor="notes-vs-notes",
                heading="彩色提示与备注字段的区别",
                body="""每个停靠点还有一个普通的**备注**字段。那个留给你自己的备忘——预订号、点什么菜。

凡是读者需要*据此行动*的内容，请用彩色提示。区别就在于：它是不是应该容易被跳过。""",
            ),
        ),
        keywords=(
            "提示",
            "备注",
            "提醒",
            "警告",
            "建议",
            "注意",
            "避免",
            "信息",
            "注解",
            "安全",
            "骗局",
        ),
        related=("add-places-to-an-itinerary", "plan-a-trip-itinerary"),
        updated="2026-09-01",
        cta="把你当初希望有人告诉你的事写下来。",
    ),
    Article(
        slug="trip-cover-photos",
        title="如何为行程添加封面照片",
        summary="挑一张封面图、裁剪好，并在上传前弄清什么会被拒绝。",
        category="building",
        intro="封面是别人在动态和分享链接里看到的东西，因此它比任何单个字段都更卖力。只有行程的**所有者**能设置它——被邀请来编辑的人可以改内容，但改不了行程对外的那张脸。",
        blocks=(
            Block(
                anchor="add-a-cover",
                heading="添加或更换封面",
                body="""打开行程的编辑页面，点按封面区域。相册会打开；选一张图并裁剪到框内。

裁剪比例偏宽，因为链接预览用的就是这个形状。竖幅照片会被切掉上下两端，所以请挑主体位于中间的那张。""",
            ),
            Block(
                anchor="what-gets-refused",
                heading="什么会被拒绝，以及为什么",
                body="""图片可能因三种原因被拒：

- **太小。**最短边低于 600 像素的图，在现代屏幕上会发虚。
- **格式不支持。**JPEG、PNG 以及常见的照片格式都没问题。
- **内容。**上传的文件在存储前会依据[社区准则](/guidelines)自动检查。

如果你认为某次拒绝有误，[请告诉我们](/help/contact)。""",
            ),
            Block(
                anchor="what-we-strip",
                heading="‏Ntripi 会从你的照片中移除什么",
                body="""每张上传的图片在存储前都会被**清除 EXIF 元数据**。那是相机附加的一段隐藏数据——最重要的是**拍摄地点的 GPS 坐标**，以及设备型号和时间戳。

无论行程是否公开都会这么做，而且无法关闭。一张你家街道的照片，不该把你家街道公之于众。""",
            ),
            Block(
                anchor="no-cover",
                heading="如果你不添加封面",
                body="""没有封面的行程会得到一张根据其路线生成的占位图，所以看起来不会像坏掉了。

不过在公开分享之前，还是值得换一张真实的：在一片照片构成的动态里，占位图正是人们一划而过的那种。""",
            ),
        ),
        keywords=(
            "封面",
            "照片",
            "图片",
            "上传",
            "裁剪",
            "横幅",
            "缩略图",
            "被拒绝",
            "太小",
        ),
        related=("plan-a-trip-itinerary", "share-a-trip-link"),
        updated="2026-09-01",
        cta="给你的行程一张脸。",
    ),
    Article(
        slug="plan-a-trip-with-friends",
        title="如何和其他人一起规划一趟行程",
        summary="邀请他人编辑行程，并理解为什么同一时间只能有一个人在输入。",
        category="building",
        schema=SCHEMA_HOWTO,
        intro="一趟行程有一个所有者和任意数量的**编辑者**。编辑者可以修改内容——停靠点、交通、提示、标题——但不能改谁可以看到它、封面，以及编辑者名单。同一时间只有一人编辑，谁的成果都不会被覆盖。",
        blocks=(
            Block(
                anchor="invite-an-editor",
                heading="邀请他人来编辑",
                kind=KIND_STEP,
                body="""打开行程的编辑页面，找到编辑者名单。按用户名把人加进来。对方会收到一条点名这趟行程的通知，而这正是他们能找到它的原因——私密行程不在任何动态里，也不在任何搜索里。

只有**所有者**能添加或移除编辑者。编辑者不能再拉人进来：邀请是你的信任决定，并不附带把它转交出去的权力。""",
            ),
            Block(
                anchor="cannot-see-it",
                heading="如果他们还看不到这趟行程",
                kind=KIND_STEP,
                body="""编辑的前提是先能看到。如果你邀请了看不到它的人，Ntripi 会询问要不要一并给对方访问权限，而不是直接失败。

选择「是」只会把对方加入该行程的允许名单，仅此而已。它永远不会放宽行程的可见性——把「粉丝」变成「指定的人」会悄悄把其他所有人挡在外面，所以那始终是一个需要你刻意做出的决定。""",
            ),
            Block(
                anchor="one-at-a-time",
                heading="为什么同一时间只能一人编辑",
                body="""当你打开一趟行程进行编辑时，你就持有了它。其他任何人看到的是**「有人正在编辑」**，可以读但不能保存。

否则就是两个人往同一个停靠点里打字，其中一个人的内容全丢了却毫不知情。持有时间很短：你离开时就会释放，如果你分了心，它也会自行过期。""",
            ),
            Block(
                anchor="taking-over",
                heading="从别人手里接管",
                kind=KIND_STEP,
                body="""如果这趟行程闲置了一段时间，任何有编辑权限的人都可以接管。作为所有者，你随时都能拿回来——包括从你自己的另一台设备上，而那通常正是它卡住的原因。

接管始终是刻意的第二步，绝不会自动发生。""",
            ),
            Block(
                anchor="losing-the-lock",
                heading="如果有人在你输入时接管了",
                body="""会出现一条提示条，保存随之失效。**你输入的内容不会丢失**——每个字段都保持你离开时的样子，你仍然可以从中选中并复制。

把行程拿回来再保存，或者把文字复制出去，等对方结束后再粘贴回来。Ntripi 不会替你关掉页面或清空字段，因为在那一刻，你未保存的文字就是它唯一的副本。""",
            ),
            Block(
                anchor="finding-shared-trips",
                heading="找回别人分享给你的行程",
                body="**行程**标签页里有第二个视图，放的是别人邀请你编辑的行程。那是回到它的长久途径——宣布它的那条通知终会被清理掉，而私密行程不会出现在任何动态或搜索中。",
            ),
        ),
        keywords=(
            "协作",
            "一起",
            "共同",
            "共享",
            "编辑者",
            "邀请",
            "团队",
            "朋友",
            "家人",
            "共编",
            "有人正在编辑",
            "锁定",
        ),
        related=("share-an-itinerary-privately", "plan-alternative-options", "troubleshooting"),
        updated="2026-09-01",
        cta="和真正要同行的人一起规划下一趟旅程。",
    ),
    Article(
        slug="share-an-itinerary-privately",
        title="如何不公开地分享一份旅行行程",
        summary="四个可见性级别决定谁能打开一趟行程——从整个互联网，到少数几位点名的人。",
        category="sharing",
        schema=SCHEMA_FAQ,
        intro="每趟行程都有四个可见性级别之一，你随时可以更改。新行程从**仅自己**开始。若想分享给特定一群人而不对外发布，请使用**指定的人**并按用户名添加他们。",
        blocks=(
            Block(
                anchor="the-four-levels",
                heading="四个可见性级别是什么？",
                kind=KIND_FAQ,
                body="""- **公开** — 任何人都能打开，包括未登录的人。它可以出现在动态里，也能通过分享链接被搜索引擎找到。
- **粉丝** — 所有关注你的人。如果你的账号是私密的，那就只包括你已通过的粉丝。
- **指定的人** — 只有你添加的那些用户名。除此之外谁都不行，不管他怎么拿到链接的。
- **仅自己** — 除了你和你设为编辑者的人，没有别人。""",
            ),
            Block(
                anchor="share-with-a-few-people",
                heading="怎样只分享给少数几个人？",
                kind=KIND_FAQ,
                body="""把行程设为**指定的人**，按用户名把他们加进来。然后把行程的分享链接发给他们。

链接不是什么秘密口令——它是行程的地址。每次有人打开时都会对照你的名单检查权限，所以把链接转发给名单外的人，对方什么也得不到。""",
            ),
            Block(
                anchor="what-others-see",
                heading="没有权限的人会看到什么？",
                kind=KIND_FAQ,
                body="""一个写着该行程不可用的页面。它不会透露这趟行程存在、属于谁，或者叫什么名字——一趟你看不到的行程，和一趟从未创建过的行程，是无法区分的。

对于屏蔽了你的个人资料，情况也一样。""",
            ),
            Block(
                anchor="change-later",
                heading="之后还能改可见性吗？",
                kind=KIND_FAQ,
                body="""可以，随时改，两个方向都行。改成更窄的级别会立即生效——不再符合条件的人马上就打不开了。

只有行程的所有者能更改可见性。你邀请来编辑的人可以改内容，但改不了谁能看到。""",
            ),
            Block(
                anchor="link-previews",
                heading="把链接贴到别处时会显示什么？",
                kind=KIND_FAQ,
                body="""公开的行程会生成一张预览卡片，包含封面图、标题、时长、花费和评分。

非公开的行程不会生成预览——因为预览会把标题泄露给聊天里的所有人，包括那些根本打不开它的人。""",
            ),
        ),
        keywords=(
            "私密",
            "隐私",
            "可见性",
            "谁能看到",
            "公开",
            "粉丝",
            "受限",
            "仅自己",
            "隐藏",
            "保密",
            "分享链接",
            "权限",
            "仅好友",
            "邀请",
        ),
        related=("plan-a-trip-itinerary", "plan-alternative-options"),
        updated="2026-09-01",
        cta="规划一趟行程，只分享给你真正想分享的人。",
    ),
    Article(
        slug="share-a-trip-link",
        title="如何把你的行程作为链接分享",
        summary="用一个链接把行程发给任何人，并在粘贴之前知道预览卡片会显示什么。",
        category="sharing",
        intro="每趟行程都有一个网址。分享无非就是把它发出去——链接是行程的位置，不是口令，每次有人打开时都会重新对照你的[可见性设置](/help/share-an-itinerary-privately)检查权限。",
        blocks=(
            Block(
                anchor="get-the-link",
                heading="获取链接",
                body="""打开行程并使用分享操作。设备自带的分享面板会弹出，链接因此可以发往任何应用——消息、邮件、备忘录。

页面在浏览器中打开，所以你发给的人不需要装应用就能阅读。""",
            ),
            Block(
                anchor="what-the-preview-shows",
                heading="预览卡片会显示什么",
                body="""**公开**的行程会在大多数聊天应用中生成一张预览卡片：封面图、标题、总时长和总花费、停靠点数量，以及评分（如果有的话）。

**非**公开的行程不会生成预览。这是刻意为之——预览会把标题展示给群聊里的所有人，包括那些打不开它的人。""",
            ),
            Block(
                anchor="what-they-see",
                heading="读者会看到什么",
                body="""整趟行程：按顺序排列的停靠点、并行的备选方案、它们之间的交通、花费、你的提示和提醒，以及评分。

这些他们不用账号就能全部读到。但保存、评分或从中复制停靠点则需要账号。""",
            ),
            Block(
                anchor="unsharing",
                heading="收回分享",
                body="""改掉行程的可见性，链接对不再符合条件的人就会立刻失效。你不必再去追那条已经发出去的消息。

你无法撤销的是截图，所以请把「发布」当成真正的发布来对待。""",
            ),
        ),
        keywords=(
            "分享",
            "链接",
            "网址",
            "发送",
            "微信",
            "预览",
            "复制",
            "发布",
            "公开",
        ),
        related=("share-an-itinerary-privately", "trip-cover-photos"),
        updated="2026-09-01",
        cta="做出值得发出去的东西。",
    ),
    Article(
        slug="follow-and-private-accounts",
        title="粉丝、关注请求和私密账号",
        summary="关注是怎么运作的、私密账号会隐藏什么，以及如何通过或拒绝一条请求。",
        category="community",
        schema=SCHEMA_FAQ,
        intro="关注某人会把他的公开行程送到你眼前，也让他可以把行程分享给粉丝。如果你的账号是**私密**的，关注就变成一条由你通过或拒绝的**请求**。",
        blocks=(
            Block(
                anchor="how-to-follow",
                heading="怎么关注一个人？",
                kind=KIND_FAQ,
                body="""在**搜索**标签页里找到对方——它搜的是用户名——然后在他的资料页上点关注。

如果对方账号是公开的，你立刻就关注上了。如果是私密的，按钮会变成**已请求**，直到对方做出决定。""",
            ),
            Block(
                anchor="what-private-hides",
                heading="私密账号会隐藏什么？",
                kind=KIND_FAQ,
                body="""设为**粉丝**的行程，只对你真正通过了的粉丝可见，而不是对所有点过关注的人可见。

你设为**公开**的行程仍然公开——私密管的是谁算粉丝，它不是一把总锁。如果你想把一切都藏起来，请把行程本身设为[仅自己或指定的人](/help/share-an-itinerary-privately)。""",
            ),
            Block(
                anchor="handling-requests",
                heading="在哪里通过请求？",
                kind=KIND_FAQ,
                body="""资料页上的提示条会显示数量，**设置 ▸ 关注请求**则会列出它们。逐条接受或拒绝。

拒绝不会通知对方。请求只是不再处于待处理状态，对方还可以再次申请。""",
            ),
            Block(
                anchor="going-public",
                heading="如果我从私密改成公开会怎样？",
                kind=KIND_FAQ,
                body="""所有待处理的请求都会被自动通过。把人留在一道你刚刚拆掉的门后排队，那会是一条再也不会有人去看的队伍。

反过来，从公开改成私密，并不会移除你已有的粉丝。""",
            ),
            Block(
                anchor="unfollow-vs-block",
                heading="取消关注和屏蔽有什么区别？",
                kind=KIND_FAQ,
                body="""**取消关注**只是让对方的行程不再出现在你的动态里。他依然能看到此前能看到的一切。

**屏蔽**会双向切断可见性，而且被屏蔽的人不会被告知。见[举报与屏蔽](/help/report-and-block)。""",
            ),
        ),
        keywords=(
            "关注",
            "粉丝",
            "已关注",
            "请求",
            "私密",
            "公开账号",
            "通过",
            "接受",
            "取消关注",
            "屏蔽",
        ),
        related=("share-an-itinerary-privately", "report-and-block"),
        updated="2026-09-01",
        cta="找到那些行程值得你借鉴的人。",
    ),
    Article(
        slug="rate-a-trip",
        title="行程评分是怎么运作的：安全、无障碍、拥挤程度等",
        summary="一个总体评分加五个可选维度，以及为什么要满三人评过才显示平均分。",
        category="community",
        schema=SCHEMA_FAQ,
        intro="一次评分包含一个必填的**总体**分（满分五分），以及最多五个可选维度：安全、体验、无障碍、适合家庭程度和拥挤程度。你还可以在旁边留下文字评价。",
        blocks=(
            Block(
                anchor="the-dimensions",
                heading="这五个维度是什么意思？",
                kind=KIND_FAQ,
                body="""- **安全** — 待着有多安心。
- **体验** — 实际有多好。
- **无障碍** — 对行动不便者、婴儿车或大件行李有多友好。
- **适合家庭** — 带孩子去有多合适。
- **拥挤程度** — 人少得有多舒服。

所有维度都是**分越高越好**，拥挤程度也不例外：五分表示清静宜人，一分表示人满为患。它们全是可选的——只评你说得上来的那些。""",
            ),
            Block(
                anchor="three-ratings",
                heading="为什么我看不到平均分？",
                kind=KIND_FAQ,
                body="""某个维度要等**三个**人评过之后，才会显示它的平均分。

把一个人的看法当作平均分呈现，读起来像是关于这个地方的事实，而不是一种观点，两个人也好不到哪里去。不满三人时，你看到的是一条条单独的评分。""",
            ),
            Block(
                anchor="who-can-rate",
                heading="谁可以给行程评分？",
                kind=KIND_FAQ,
                body="""任何能看到它、并且邮箱已验证的人，行程所有者除外。你随时可以更新自己的评分——再评一次是替换，而不是新增一条。

邮箱验证的要求，正是把一次性账号挡在分数之外的东西。""",
            ),
            Block(
                anchor="written-notes",
                heading="我能写点评，而不只是打分吗？",
                kind=KIND_FAQ,
                body="""可以——评分对话框里有一个评价字段，而那才是其他旅行者真正会读的部分。分数说的是过程如何；评价说的是为什么。

评价和其他所有发布的内容一样，受[社区准则](/guidelines)约束。""",
            ),
            Block(
                anchor="disagreeing",
                heading="有人给我的行程打了不公平的分",
                kind=KIND_FAQ,
                body="""你无法删除自己行程上的评分，而这正是关键所在——一个作者可以随手删掉的分数，对下一位读者毫无价值。

如果某条评分是违反准则，而不只是与你意见不合，请[举报它](/help/report-and-block)，会有人来看。""",
            ),
        ),
        keywords=(
            "评分",
            "打分",
            "评价",
            "点评",
            "星级",
            "分数",
            "安全",
            "无障碍",
            "适合家庭",
            "拥挤",
            "人多",
        ),
        related=("save-trips-and-find-new-ones", "report-and-block"),
        updated="2026-09-01",
        cta="给一趟你真正走过的行程打分。",
    ),
    Article(
        slug="save-trips-and-find-new-ones",
        title="如何保存行程并发现新的行程",
        summary="把值得留着的都收藏起来，并弄清「热门」和「最新」两种动态的区别。",
        category="community",
        schema=SCHEMA_FAQ,
        intro="**动态**标签页展示所有人的公开行程。任何值得留着的，都可以收藏进**已保存**标签页，那里只属于你——没人会被告知你保存了他的行程。",
        blocks=(
            Block(
                anchor="saving",
                heading="怎么保存一趟行程？",
                kind=KIND_FAQ,
                body="""在任何你能看到的行程上点书签图标。它会出现在你的**已保存**标签页里，列表变长后那里还有自己的筛选框。

你自己的行程上不显示书签——保存自己写的东西没有任何意义。""",
            ),
            Block(
                anchor="saved-changes",
                heading="如果保存的行程变了或消失了怎么办？",
                kind=KIND_FAQ,
                body="""你看到的始终是当前版本，而不是你保存时的那一版。

如果作者收窄了它的可见性或把它删了，它就会离开你的「已保存」标签页。书签是一个指向，不是一份副本——作者始终掌控自己的作品。""",
            ),
            Block(
                anchor="top-vs-recent",
                heading="「热门」和「最新」有什么区别？",
                kind=KIND_FAQ,
                body="""**最新**是全部公开内容，越新越靠前。**热门**按评分排序，而且一趟行程需要攒够几条评分才可能出现在那里。

在「最新」里你找到的是新作品；在「热门」里你找到的是别人已经背书过的作品。""",
            ),
            Block(
                anchor="not-in-top",
                heading="为什么我的行程不在「热门」里？",
                kind=KIND_FAQ,
                body="""它必须是公开的，而且需要足够多的评分。只有一条好评的行程说明不了什么，所以「热门」会等上几条。

把它通过[链接](/help/share-a-trip-link)分享给去过那里的人——最早的那几条评分就是这么来的。""",
            ),
            Block(
                anchor="finding-people",
                heading="怎么找到某个特定的人？",
                kind=KIND_FAQ,
                body="""**搜索**标签页搜的是用户名，不是行程。行程要通过动态、别人发给你的链接，或者在找到某人之后通过他的资料页来发现。

私密行程按设计不出现在任何动态或搜索里；通往它的唯一途径，是一份邀请，或者一个来自能看到它的人的链接。""",
            ),
        ),
        keywords=(
            "保存",
            "已保存",
            "收藏",
            "书签",
            "动态",
            "发现",
            "探索",
            "热门",
            "最新",
            "浏览",
        ),
        related=("rate-a-trip", "share-an-itinerary-privately"),
        updated="2026-09-01",
        cta="找一趟值得借鉴的行程。",
    ),
    Article(
        slug="notifications",
        title="如何控制 Ntripi 发送哪些通知",
        summary="‏Ntripi 会告诉你的八件事、其中哪三项可以关掉，以及为什么其余的会一直开着。",
        category="account",
        schema=SCHEMA_FAQ,
        intro="个人资料页上齿轮旁边的铃铛，就是全部清单。有三类通知可以在**设置 ▸ 通知**里关掉；其余的会一直开着，因为看不见的事情就无法及时处理。",
        blocks=(
            Block(
                anchor="what-you-get",
                heading="‏Ntripi 会就哪些事通知我？",
                kind=KIND_FAQ,
                body="""- 有人申请关注你，或者开始关注你
- 有人通过了你的关注请求 *（可选）*
- 有人给你的行程评了分 *（可选）*
- 有人保存了你的行程 *（可选）*
- 你被邀请编辑某趟行程
- 你获得了某趟行程的访问权限
- 某项审核决定影响了你的内容或账号

此外没有别的。没有营销，没有拉你回来的推送，也没有周期性摘要。""",
            ),
            Block(
                anchor="switching-off",
                heading="怎么关掉其中一些？",
                kind=KIND_FAQ,
                body="""**设置 ▸ 通知**里有三个开关：评分、保存，以及关注请求被通过。关掉其中一个，通知根本就不会被创建，而不只是被藏起来。

若要全部静音，请在手机自己的设置里关掉 Ntripi 的通知——见[权限](/help/permissions)。""",
            ),
            Block(
                anchor="always-on",
                heading="为什么其余的关不掉？",
                kind=KIND_FAQ,
                body="""关注请求、访问授权和审核决定，都需要你在一个有用的时间窗口内做出回应。

没人看到的关注请求永远得不到答复。别人分享给你的行程不在任何动态或搜索里，所以一条你没收到的通知，就是一份你从不知道自己拥有的访问权限。而审核决定有申诉期限——在那里保持沉默，代价就是失去申诉机会。""",
            ),
            Block(
                anchor="arrival",
                heading="为什么有些来得比较晚？",
                kind=KIND_FAQ,
                body="""推送投递在任何平台上都只是尽力而为：省电管理会杀掉后台进程，手机会限制频率，连接会中断。

因此 Ntripi 在打开期间也会大约每分钟自查一次，即便推送从未送达，铃铛上的数字也是准的。如果推送被关闭或被拒绝，这项自查就是唯一的渠道——而它照样有效。""",
            ),
            Block(
                anchor="clearing",
                heading="我可以删除通知吗？",
                kind=KIND_FAQ,
                body="""可以，逐条删或一次全删，在最终生效前有几秒钟可以撤销。

删掉一条审核通知并不会删掉那项决定——它仍留在**设置 ▸ 账号状态**里，连同申诉按钮。已读通知会在九十天后清除；未读的会留得更久，因为它们是你唯一能证明发生过某件事的记录。""",
            ),
        ),
        keywords=(
            "通知",
            "推送",
            "提醒",
            "铃铛",
            "红点",
            "静音",
            "关闭",
            "邮件",
            "免打扰",
        ),
        related=("permissions", "follow-and-private-accounts"),
        updated="2026-09-01",
        cta="跟进你的行程，又不必忍受噪音。",
    ),
    Article(
        slug="app-settings",
        title="语言、深色模式、声音与震动",
        summary="个人资料页齿轮后面的每一个开关，以及它们各自会改变什么。",
        category="account",
        intro="你自己资料页上的齿轮打开的是全部设置。这些设置保存在你的设备上，因此是按安装区分的：在手机上换了主题，平板上不会跟着变。",
        blocks=(
            Block(
                anchor="language",
                heading="语言",
                body="""‏Ntripi 提供英语、法语、阿拉伯语、德语、西班牙语和中文。当你设备的语言是这六种之一时，应用会跟随它，你也可以在这里手动指定。

阿拉伯语会把整个界面切换为从右到左。当你从应用中打开法律文件和这个帮助中心时，这个选择也会一并带过去。""",
            ),
            Block(
                anchor="theme",
                heading="主题",
                body="""跟随系统、浅色或深色。**跟随系统**会跟着你的手机走，包括它的日夜自动切换，这也是默认设置。

深色模式是真正的纯黑，不是灰色——如果你习惯在床上读行程，这一点值得知道。""",
            ),
            Block(
                anchor="sounds-and-haptics",
                heading="音效与震动",
                body="""两个互相独立的开关。**音效**是那些细小的提示音——通知到达、评分落定。**震动**是你能感觉到的轻触，包括打分时每颗星一下短促的震动。

每个开关都会用你刚选定的设置回应你一次，好让你听到或感觉到自己开启的是什么。""",
            ),
            Block(
                anchor="shake-to-report",
                heading="摇一摇报告",
                body="""在手机上默认开启：摇动会截取屏幕并打开一份故障报告。如果你读东西时手上动作比较多，可以在这里关掉——**设置 ▸ 支持 ▸ 摇一摇报告**。

它被刻意设计成不容易误触：需要两次明确的摇动，应用不在前台时会被忽略，并且要等上几秒才能再次触发。""",
            ),
            Block(
                anchor="account-rows",
                heading="菜单里的其余项",
                body="""- **账号状态** — 审核决定与申诉
- **已屏蔽账号** — 你屏蔽过的所有人，一点即可解除
- **关注请求** — 仅在你的账号为私密时显示
- **帮助中心**和**关于** — 包括本网站

修改密码或删除账号在你个人资料的编辑页面里，位于「安全」之下。""",
            ),
        ),
        keywords=(
            "设置",
            "语言",
            "翻译",
            "深色模式",
            "浅色模式",
            "主题",
            "声音",
            "音效",
            "震动",
            "触感",
            "偏好",
        ),
        related=("app-map", "notifications", "permissions"),
        updated="2026-09-01",
        cta="把这个应用调成你自己的样子。",
    ),
    Article(
        slug="permissions",
        title="‏Ntripi 会请求哪些权限，以及为什么",
        summary="位置、通知、照片和运动——各自的用途、何时会请求，以及如何改变主意。",
        category="account",
        schema=SCHEMA_FAQ,
        intro="‏Ntripi 会请求四样东西，每一样都在它第一次真正有用时才请求，而不是在启动时。**它从不请求你的相机、通讯录、麦克风，也不请求后台位置。**拒绝其中任何一项，应用照样能用。",
        blocks=(
            Block(
                anchor="location",
                heading="位置——用来做什么？",
                kind=KIND_FAQ,
                body="""用于在你添加停靠点时把地图定位到你所在的位置，免得你横跨一个大洲去找自己正站着的这座城市。

它在你第一次使用地图的定位按钮时请求，而且**仅在你使用应用期间**——没有后台位置，也没有追踪。拒绝不会影响任何功能：地图只是从别处打开，你自己平移过去即可。""",
            ),
            Block(
                anchor="notifications",
                heading="通知——为什么要，又为什么只问一次？",
                kind=KIND_FAQ,
                body="""用于告诉你关注请求、评分、保存和审核决定。

它在你第一次打开**通知页面**时请求——也就是你刚刚表明自己想要它们的那一刻。iOS 每次安装只允许应用弹出一次询问，所以在启动时、在你还没见过这个应用之前就问，等于把这唯一的机会浪费在一个陌生人身上。""",
            ),
            Block(
                anchor="photos",
                heading="照片——Ntripi 能看到什么？",
                kind=KIND_FAQ,
                body="""只有你选中的那张图。Ntripi 打开的是系统自带的照片选择器，它只交回一个文件，别的什么都不给——应用无从查看你的相册。

每次上传都会被**清除 EXIF 元数据**，包括拍摄地点的 GPS 坐标。见[封面照片](/help/trip-cover-photos)。""",
            ),
            Block(
                anchor="motion",
                heading="运动与震动——做什么用？",
                kind=KIND_FAQ,
                body="""摇动手机会提交一份故障报告，而手机的短暂震动用于确认诸如完成评分之类的操作。

两者都可以在**设置**中关闭：**摇一摇报告**和**震动**。关于你动作的任何信息都不会离开设备。""",
            ),
            Block(
                anchor="never-asked",
                heading="‏Ntripi 从不请求什么",
                kind=KIND_FAQ,
                body="""**相机**、你的**通讯录**、你的**麦克风**，以及**后台位置**。它们既没有出现在应用里，也没有在我们发布的安装包中声明。

如果哪天有什么东西声称 Ntripi 在请求其中之一，那不是我们——[请告诉我们](/help/contact)。""",
            ),
            Block(
                anchor="changing-your-mind",
                heading="之后怎么修改某项权限？",
                kind=KIND_FAQ,
                body="""权限属于你的操作系统，而不属于 Ntripi，所以要在那里修改：

- **iPhone 或 iPad** — 设置 ▸ 下滑找到 Ntripi ▸ 开关「定位」或「通知」。
- **Android** — 设置 ▸ 应用 ▸ Ntripi ▸ 权限。

这一点对通知尤其重要，因为 iOS 不会再次询问：一旦拒绝，只有系统设置这一条回头路。""",
            ),
        ),
        keywords=(
            "权限",
            "隐私",
            "位置",
            "定位",
            "相机",
            "摄像头",
            "照片",
            "通知",
            "麦克风",
            "通讯录",
            "追踪",
            "允许",
            "拒绝",
        ),
        related=("your-data-and-privacy", "notifications", "add-locations-from-google-maps"),
        updated="2026-09-01",
        cta="看清这个应用到底请求了什么——以及没请求什么。",
    ),
    Article(
        slug="your-data-and-privacy",
        title="‏Ntripi 存储哪些数据，以及如何删除",
        summary="用通俗的话说明保存了什么、谁能看到，以及如何永久删除你的账号。",
        category="account",
        schema=SCHEMA_FAQ,
        intro="‏Ntripi 存储你写下的和上传的内容，外加让你保持登录所需的信息。没有广告，没有第三方广告追踪，也不会出售任何东西。[隐私政策](/privacy)是具有约束力的正式文本；这里是简版。",
        blocks=(
            Block(
                anchor="what-is-stored",
                heading="‏Ntripi 存了我的哪些信息？",
                kind=KIND_FAQ,
                body="""- **你的账号** — 显示名称、用户名、邮箱地址和出生日期（从不向任何人展示）。
- **你创建的内容** — 行程、停靠点、提示、评分，以及你上传的所有图片。
- **你的关系** — 你关注了谁、谁关注了你、你屏蔽了谁。
- **会话数据** — 足以让你保持登录，以及一个设备令牌（如果你开启了推送通知）。

上传的图片会被清除 EXIF 元数据，包括照片拍摄地点的 GPS 坐标。""",
            ),
            Block(
                anchor="who-sees-it",
                heading="谁能看到我写的东西？",
                kind=KIND_FAQ,
                body="""你的[可见性设置](/help/share-an-itinerary-privately)指定的那些人，除此之外没有别人。设为**仅自己**的行程，只有你和你邀请来编辑的人能看到。

无论哪种设置，你的出生日期都不会被其他用户看到。你的邮箱地址不会显示在个人资料上。""",
            ),
            Block(
                anchor="moderation",
                heading="‏Ntripi 会有人读我的行程吗？",
                kind=KIND_FAQ,
                body="""不会例行阅读。文字和图片在发布时会被自动检查，只有当内容被举报，或被这些检查标记出来时，才会有人去看。

自动检查只发送内容本身，别的什么都不发——没有用户 ID，没有邮箱，也没有姓名。""",
            ),
            Block(
                anchor="deleting",
                heading="怎么删除我的账号？",
                kind=KIND_FAQ,
                body="""在个人资料的编辑页面，安全 ▸ **删除账号**。用密码确认，如果你是用 Google 登录的，就用 Google 确认。

删除是永久性的，你的行程也会一并消失。别人保存过的那些行程会随之失效，因为书签是一个指向，而不是一份副本。""",
            ),
            Block(
                anchor="requests",
                heading="怎么申请一份我的数据副本？",
                kind=KIND_FAQ,
                body="""请写信到 **[privacy@ntripi.app](mailto:privacy@ntripi.app)**。这个地址是[隐私政策](/privacy)中载明的数据保护联系方式，它能直达真正有权处理请求的人。

同一个地址也受理更正、限制处理和反对处理的请求。""",
            ),
        ),
        keywords=(
            "隐私",
            "数据",
            "删除账号",
            "移除",
            "导出",
            "个人数据",
            "追踪",
            "广告",
            "谁能看到",
        ),
        related=("permissions", "sign-in-and-account-security", "share-an-itinerary-privately"),
        updated="2026-09-01",
    ),
    Article(
        slug="sign-in-and-account-security",
        title="登录、密码和删除账号",
        summary="用邮箱、Google 或 Apple 登录，重置密码，为什么有些操作需要已验证的邮箱，以及如何离开。",
        category="account",
        schema=SCHEMA_FAQ,
        intro="你可以用邮箱和密码登录，也可以用 Google 或 Apple 登录。三者到达的是同一个账号，而且用 Google 创建的账号之后也可以再加一个密码。",
        blocks=(
            Block(
                anchor="forgot-password",
                heading="我忘记密码了",
                kind=KIND_FAQ,
                body="""在登录页面点**忘记密码**。重置链接会通过邮件送达，并在短时间内有效。

如果一直没收到，请检查垃圾邮件文件夹，并确认你用的是注册时的那个地址。如果你是用 Google 注册的，可能压根就没有密码——请改用 Google 登录。""",
            ),
            Block(
                anchor="verify-email",
                heading="为什么我不能创建行程、评分或关注别人？",
                kind=KIND_FAQ,
                body="""这三件事都需要已验证的邮箱地址。请在收件箱里找验证链接，或者用个人资料上的提示条再发一封。

用同一个邮箱通过 Google 登录也能完成验证。这项要求正是把一次性账号挡在评分和别人粉丝列表之外的东西。""",
            ),
            Block(
                anchor="changing-password",
                heading="怎么修改密码？",
                kind=KIND_FAQ,
                body="""个人资料 ▸ 编辑 ▸ **安全 ▸ 修改密码**。用当前密码确认。

修改会登出所有**其他**会话，只保留你正在使用的这一个——所以如果你是因为怀疑有人进了你的账号才改密码，仅此一步就把对方踢出去了。""",
            ),
            Block(
                anchor="age",
                heading="‏Ntripi 为什么要问我的出生日期？",
                kind=KIND_FAQ,
                body="""‏Ntripi 的最低年龄要求是 **16 岁**，[服务条款](/terms)里也这么写，这意味着必须去问，而不能想当然。

它从不出现在你的个人资料上，其他用户也永远看不到。只会问一次，之后不再问。""",
            ),
            Block(
                anchor="suspended",
                heading="我的账号被停用了",
                kind=KIND_FAQ,
                body="""你应该收到过一封说明原因的邮件，里面带有申诉链接。申诉会由人来阅读。

如果那封邮件已经不在了，申诉表单可以给你补发一个新链接。见[被隐藏的内容与申诉](/help/hidden-content-and-appeals)。""",
            ),
            Block(
                anchor="deleting",
                heading="怎么删除我的账号？",
                kind=KIND_FAQ,
                body="""个人资料 ▸ 编辑 ▸ **安全 ▸ 删除账号**，用密码或 Google 确认。

这是永久性的，你的行程也会一并消失。如果你只是想从别人视野里消失，把行程设为[仅自己](/help/share-an-itinerary-privately)并把账号改为私密是可以撤销的，而删除不可以。""",
            ),
        ),
        keywords=(
            "登录",
            "账号",
            "密码",
            "忘记密码",
            "重置",
            "谷歌",
            "苹果",
            "验证",
            "邮箱",
            "进不去",
            "删除账号",
            "年龄",
            "16岁",
        ),
        related=("your-data-and-privacy", "troubleshooting"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-and-block",
        title="如何举报内容或屏蔽某人",
        summary="举报违反规则的行程、点评或个人资料，并与你不愿打交道的人彻底切断联系。",
        category="safety",
        schema=SCHEMA_HOWTO,
        intro="举报是把某样东西送去审核；屏蔽是把某个人从你的使用体验中移除。两者是不同的工具，你可以都用。它们都不会告诉对方你做了什么。",
        blocks=(
            Block(
                anchor="report",
                heading="举报行程、点评或个人资料",
                kind=KIND_STEP,
                body="""在对象本身上使用旗帜操作——一趟行程、一个停靠点、一条点评、一条提示或一份个人资料。选一个理由，再补充任何有帮助的信息。

从对象本身发起举报会把上下文一并带上，这正是它优于给我们发一段描述邮件的原因。从公开的分享页面举报不需要账号。""",
            ),
            Block(
                anchor="reasons",
                heading="选择理由",
                body="""可选理由有：儿童性虐待内容、色情内容、暴力或威胁、仇恨言论、骚扰、垃圾信息，以及其他。

请选最接近的那个——它决定这条举报被处理的紧急程度。**任何涉及儿童的内容都按最高优先级处理**，并进入单独的队列。""",
            ),
            Block(
                anchor="what-happens",
                heading="我举报之后会发生什么？",
                body="""它会进入审核队列。被多位不同的人举报，或被自动检查佐证的内容，可以在有人复核期间先行隐藏。

作者永远不会被告知是谁举报了他。你通常不会收到回复——结果就是内容留下或被移除。""",
            ),
            Block(
                anchor="block",
                heading="屏蔽某人",
                kind=KIND_STEP,
                body="""从对方的个人资料，或者按住他发布的某样东西。

屏蔽会**双向**切断可见性：你看不到他，他也看不到你。你们之间的任何关注关系都会被移除。对方不会被告知，而且在他看来，你的资料页与一个从未存在过的账号毫无区别。""",
            ),
            Block(
                anchor="unblock",
                heading="解除对某人的屏蔽",
                kind=KIND_STEP,
                body="""**设置 ▸ 已屏蔽账号**列出你屏蔽过的所有人，一点即可撤销。

解除屏蔽不会恢复屏蔽时移除的关注关系——你们任何一方想重新关注都可以。""",
            ),
            Block(
                anchor="urgent",
                heading="如果有人处于危险之中",
                body="""请先联系当地的紧急服务。Ntripi 无法足够快地联系到任何人，不适合作为第一通电话。

之后再写信到 **[abuse@ntripi.app](mailto:abuse@ntripi.app)**，这个邮箱正是为此而设有人值守的。""",
            ),
        ),
        keywords=(
            "举报",
            "投诉",
            "屏蔽",
            "拉黑",
            "滥用",
            "骚扰",
            "垃圾信息",
            "不安全",
            "不当内容",
            "解除屏蔽",
            "安全",
        ),
        related=("hidden-content-and-appeals", "follow-and-private-accounts", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="hidden-content-and-appeals",
        title="你的内容为什么被隐藏，以及如何申诉",
        summary="行程或点评被隐藏意味着什么、在哪里查看原因，以及如何请人再看一遍。",
        category="safety",
        schema=SCHEMA_FAQ,
        intro="如果你发布的内容被隐藏了，你会收到一条通知和一个原因，**设置 ▸ 账号状态**里会保留记录。大多数决定都可以申诉，而申诉会由人来阅读。",
        blocks=(
            Block(
                anchor="what-hidden-means",
                heading="「被隐藏」是什么意思？",
                kind=KIND_FAQ,
                body="""别人打不开它。**你还能打开**——它仍在你的列表里，带着一条说明原因的提示条，而且只要申诉尚有可能，就不会删除任何东西。

隐藏是可以撤销的，删除则不然，这正是它成为第一步而非最后一步的原因。""",
            ),
            Block(
                anchor="why",
                heading="我的内容为什么被隐藏了？",
                kind=KIND_FAQ,
                body="""要么是足够多的不同用户举报了它，要么是自动检查标记了它，要么是审核人员认定它违反了[社区准则](/guidelines)。

原因写在提示条上，也写在**设置 ▸ 账号状态**里。有些隐藏是临时性的——在有人处理之前自动执行——而这恰恰是它们可以申诉的原因。""",
            ),
            Block(
                anchor="appealing",
                heading="怎么申诉？",
                kind=KIND_FAQ,
                body="""**设置 ▸ 账号状态**会逐条列出决定，每条都带一个申诉按钮。用你自己的话说明为什么你认为它判错了。

每项决定同时只能有一份申诉，且一个月内每项决定只能申诉一次——设这个限制是为了让队列足够短，申诉才真的会被读到。""",
            ),
            Block(
                anchor="warnings",
                heading="我收到了警告，但没有内容被隐藏",
                kind=KIND_FAQ,
                body="""警告是记在你账号上的一条记录，不伴随任何内容下架。它是一个信号，同时也是一份记录——第二次警告会被记为第二次，不会并入第一次。

警告和其他事项一样可以申诉。""",
            ),
            Block(
                anchor="suspended",
                heading="我的整个账号被停用了",
                kind=KIND_FAQ,
                body="""你无法登录，所以申诉不可能放在应用内。停用邮件里带有一个网页表单的链接；如果邮件已经不在了，表单可以往你的邮箱补发一个新链接。

停用是可以撤销的，申诉成功会恢复原账号，而不是重建一个。""",
            ),
            Block(
                anchor="after",
                heading="我申诉之后会怎样？",
                kind=KIND_FAQ,
                body="""会有人阅读它，然后要么恢复内容，要么维持原决定，并把结果告诉你。

如果决定被推翻，内容会原样回来——这期间什么都没有被删除。""",
            ),
        ),
        keywords=(
            "隐藏",
            "被删",
            "下架",
            "审核",
            "申诉",
            "上诉",
            "封禁",
            "停用",
            "警告",
            "内容被屏蔽",
            "恢复",
        ),
        related=("report-and-block", "sign-in-and-account-security", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="troubleshooting",
        title="‏Ntripi 用不了：常见问题与解决办法",
        summary="大家最常撞见的那些提示，每一条到底是什么意思，以及接下来该怎么做。",
        category="troubleshooting",
        schema=SCHEMA_FAQ,
        intro="‏Ntripi 里的大多数问题都出自三件事之一：两个人在编辑同一趟行程、连接断了，或者账号的某一步还没完成。在下面找到你看见的那条提示。",
        blocks=(
            Block(
                anchor="modified-please-reload",
                heading="「该行程已被修改，请重新加载」",
                kind=KIND_FAQ,
                body="""在你的页面加载之后，这趟行程发生了变化——通常是因为你在另一台设备上也开着它，或者你邀请来编辑的人先保存了。

重新加载行程，再改一遍。Ntripi 宁可拒绝这次保存，也不会悄悄覆盖掉你打字期间进来的内容。""",
            ),
            Block(
                anchor="someone-else-is-editing",
                heading="「有人正在编辑这趟行程」",
                kind=KIND_FAQ,
                body="""同一时间只有一个人能编辑一趟行程。此刻它在别人手里——也可能是你自己在另一台设备上。

等对方结束，或者在对方闲置一段时间后接管。如果你是所有者，随时都能拿回来。接管会结束对方的会话，所以对方会收到告知，而不是无声无息地丢掉成果。""",
            ),
            Block(
                anchor="lost-the-edit",
                heading="我正在编辑，突然保存不了了",
                kind=KIND_FAQ,
                body="""在你开着页面的时候，有人接管了这趟行程。**你打的字没有丢**——页面保持原样，每个字段都还填着内容。

有两条出路，而且都保住你的成果：把行程拿回来再保存，或者把文字复制出去，等对方结束后再粘贴回来。在你自己离开这个页面之前，什么都不会被丢弃。""",
            ),
            Block(
                anchor="image-rejected",
                heading="我上传的照片被拒绝了",
                kind=KIND_FAQ,
                body="""上传的文件在存储前会被自动检查。图片可能因为太小、格式不受支持，或内容不符合[社区准则](/guidelines)而被拒绝。

换一张更大的图试试，最短边至少 600 像素。如果你认为这次拒绝有误，[请联系我们](/help/contact)。""",
            ),
            Block(
                anchor="text-rejected",
                heading="我保存文字时被拒绝了",
                kind=KIND_FAQ,
                body="""你写下的文字在存储前会依据[社区准则](/guidelines)进行检查。

你打字时还可能在字段下方看到一条不显眼的提醒。那只是一条警告——它从不阻止你，也绝不会改动你写的内容。地名尤其可能触发警告，却完全不是问题。""",
            ),
            Block(
                anchor="cannot-create",
                heading="我不能创建行程、评分或关注任何人",
                kind=KIND_FAQ,
                body="""这些操作需要已验证的邮箱地址。请在收件箱里找验证链接，或者用个人资料上的提示条再发一封。

用同一个邮箱通过 Google 登录也能完成验证。""",
            ),
            Block(
                anchor="offline",
                heading="有一条横幅说我处于离线状态",
                kind=KIND_FAQ,
                body="""‏Ntripi 察觉到连接断了。已经加载出来的内容你都还能继续读；需要服务器的控件会变灰，直到你重新连上。

连接恢复后横幅会自行消失——不需要你点任何东西。""",
            ),
            Block(
                anchor="still-stuck",
                heading="这些都对不上我遇到的情况",
                kind=KIND_FAQ,
                body="请在应用内报告：**摇一摇手机**，Ntripi 会截取屏幕，让你在发送前把问题圈出来。见[如何联系我们](/help/contact)。",
            ),
        ),
        keywords=(
            "错误",
            "问题",
            "故障",
            "用不了",
            "失败",
            "卡住",
            "保存不了",
            "重新加载",
            "离线",
            "闪退",
            "崩溃",
            "修复",
            "帮助",
        ),
        related=("contact", "getting-started"),
        updated="2026-09-01",
    ),
    Article(
        slug="report-a-bug",
        title="如何报告 Ntripi 中的故障",
        summary="摇一摇手机截取屏幕，把问题圈出来发送——在网页版则用按钮。",
        category="troubleshooting",
        schema=SCHEMA_HOWTO,
        intro="**摇一摇你的手机。**Ntripi 会截下你正在看的这个页面，递给你一支笔把问题圈出来，然后连同你的说明一起发出。这比用文字描述一个界面快得多，而且它会替你附上设备和版本信息。",
        blocks=(
            Block(
                anchor="shake",
                heading="摇一摇手机",
                kind=KIND_STEP,
                body="""在应用的任何位置，在你觉得某处不对劲的那一刻。系统会截下正是那个页面的画面。

它需要两次明确的摇动，所以走路或坐公交不会触发。应用在后台时也会被忽略，并且要等上几秒才能再次触发。""",
            ),
            Block(
                anchor="draw",
                heading="把问题圈出来",
                kind=KIND_STEP,
                body="""直接在截图上画。在出错的地方画一个圈，能省掉整整一段解释。

如果需要截取另一个页面，报告工具开着的时候你也可以继续浏览。""",
            ),
            Block(
                anchor="describe",
                heading="选择分类并加以描述",
                kind=KIND_STEP,
                body="""从以下几项中选一个：闪退、显示、数据、卡顿，或其他。然后说明你做了什么、期待什么、实际发生了什么。

在你点击发送之前，什么都不会被发出。""",
            ),
            Block(
                anchor="what-is-sent",
                heading="随报告一起发出的内容",
                body="""你的说明、你选的分类、那张截图，以及关于设备和应用版本的技术信息——这些都是输入起来很烦、却总是被第一个问到的东西。

截图和其他上传一样会被清除元数据。它永远不会展示给其他用户，而且故障报告在关闭并搁置一段时间后会被删除，因为一张截图可能包含他人的信息。""",
            ),
            Block(
                anchor="web-and-off",
                heading="在网页版，或关掉手势之后",
                body="""浏览器没有摇动这一说，所以在网页版请使用**设置 ▸ 支持 ▸ 报告故障**，它打开的是同一个报告工具。

如果你在手机上关掉了这个手势，同一个菜单项依然可用。想重新开启：**设置 ▸ 支持 ▸ 摇一摇报告**。""",
            ),
        ),
        keywords=(
            "故障",
            "错误",
            "报告",
            "反馈",
            "闪退",
            "崩溃",
            "摇一摇",
            "截图",
            "问题",
            "异常",
        ),
        related=("troubleshooting", "contact"),
        updated="2026-09-01",
    ),
    Article(
        slug="contact",
        title="如何联系 Ntripi 支持团队",
        summary="故障、安全隐患、隐私请求或一般问题该发到哪里，以及信里该写些什么。",
        category="about",
        schema=SCHEMA_CONTACT,
        intro="报告应用问题最快的方式是**摇一摇手机**——Ntripi 会截取屏幕，让你在发送前直接在上面标注。其余情况，请在下面挑选与你的需求相符的地址。",
        blocks=(
            Block(
                anchor="report-a-bug",
                heading="在应用内报告故障",
                body="""**摇一摇你的手机。**Ntripi 会截图，递给你一支笔把出错的地方圈出来，并让你在发送前补充说明和分类。

截图会随报告一起发出，省得你用文字描述界面。在你点击发送之前，什么都不会被发出。

你可以在**设置 ▸ 支持 ▸ 摇一摇报告**中关掉这个手势。网页版没有摇动，请改用**设置 ▸ 支持 ▸ 报告故障**。""",
            ),
            Block(
                anchor="email-us",
                heading="给我们发邮件",
                body="""- **[support@ntripi.app](mailto:support@ntripi.app)** — 应用出了问题，或者你卡住了。
- **[abuse@ntripi.app](mailto:abuse@ntripi.app)** — 违反[社区准则](/guidelines)的内容或行为，以及任何与他人安全相关的紧急情况。
- **[privacy@ntripi.app](mailto:privacy@ntripi.app)** — 数据保护请求，以及[隐私政策](/privacy)涵盖的一切。
- **[contact@ntripi.app](mailto:contact@ntripi.app)** — 其余所有事项。""",
            ),
            Block(
                anchor="what-to-include",
                heading="信里该写什么",
                body="""一份报告如果包含以下内容，处理起来会快得多：

- **你做了什么**，按你操作的先后顺序。
- **你期待什么**，以及实际发生了什么。
- **一张截图**，如果问题是看得见的。
- **你的设备和应用版本** — 应用内的报告工具会自动附上这些，这也是能用它就用它的又一个理由。""",
            ),
            Block(
                anchor="reporting-content",
                heading="举报内容而非报告故障",
                body="""要举报别人发布的东西，请在那趟行程、那条点评或那份个人资料本身上使用旗帜操作，而不要发邮件。它会直达审核队列，并把上下文一并带上。

举报不会展示给被举报的人。""",
            ),
        ),
        keywords=(
            "支持",
            "客服",
            "邮箱",
            "联系",
            "帮助",
            "反馈",
            "故障",
            "报告",
            "滥用",
            "隐私",
            "投诉",
        ),
        related=("troubleshooting",),
        updated="2026-09-01",
    ),
    Article(
        slug="whats-new",
        title="‏Ntripi 有什么新变化",
        summary="近期版本：新增了什么、改动了什么，以及修复了什么。",
        category="about",
        schema=SCHEMA_RELEASES,
        intro="‏Ntripi 正在公开发布前的活跃开发阶段。下面每个版本都写明了改动了什么，以及为什么可能与你有关。",
        releases=RELEASES,
        keywords=(
            "更新日志",
            "版本说明",
            "更新",
            "新功能",
            "版本",
            "变更",
            "有什么变化",
            "历史",
        ),
        related=("getting-started", "contact"),
        updated="2026-09-01",
    ),
)
