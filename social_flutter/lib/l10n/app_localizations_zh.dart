// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get required => '必填';

  @override
  String get retry => '重试';

  @override
  String get dismiss => '忽略';

  @override
  String get seeAll => '查看全部';

  @override
  String get back => '返回';

  @override
  String get navSearch => '搜索';

  @override
  String get navProfile => '个人资料';

  @override
  String get navItineraries => '行程';

  @override
  String get navFeed => '动态';

  @override
  String get navSaved => '已保存';

  @override
  String get saveItineraryTooltip => '保存行程';

  @override
  String get unsaveItineraryTooltip => '从已保存中移除';

  @override
  String get savedItinerariesTitle => '已保存';

  @override
  String get noSavedItinerariesYet => '还没有已保存的行程。点按任意行程上的书签即可将其保存在这里。';

  @override
  String get searchSavedHint => '搜索已保存…';

  @override
  String get savedSearchNoResults => '没有已保存的行程与你的搜索匹配。';

  @override
  String get feedTitle => '发现';

  @override
  String get feedTabTop => '热门';

  @override
  String get feedTabRecent => '最新';

  @override
  String get feedEmpty => '还没有公开的行程。请稍后再来查看！';

  @override
  String get feedTopEmpty => '评分的行程还不够多——去看看最新吧。';

  @override
  String get offlineBanner => '你已离线！部分功能可能无法使用。';

  @override
  String get offlineActionTitle => '你已离线';

  @override
  String get offlineActionMessage => '没有网络连接时无法进行更改。请重新连接后再试。';

  @override
  String get downloadBanner => '为获得更好的体验，请下载 Ntripi 应用。';

  @override
  String get downloadBannerButton => '下载';

  @override
  String get loginTitle => '欢迎回来';

  @override
  String get loginSubtitle => '登录以继续你的旅程';

  @override
  String get loginEmailLabel => '邮箱或用户名';

  @override
  String get loginEmailHelp => '使用你注册时的邮箱或 @用户名登录。';

  @override
  String get loginEmailHint => 'you@example.com 或 @用户名';

  @override
  String get loginPasswordLabel => '密码';

  @override
  String get loginPasswordHelp => '你的账号密码。点按眼睛图标以显示或隐藏。';

  @override
  String get loginForgotPassword => '忘记密码？';

  @override
  String get loginSignIn => '登录';

  @override
  String get loginNoAccount => '还没有账号？ ';

  @override
  String get loginSignUp => '注册';

  @override
  String get loginOrWithEmail => '或使用邮箱登录';

  @override
  String loginContinueWithProvider(String provider) {
    return '使用 $provider 继续';
  }

  @override
  String get registerTitle => '创建账号';

  @override
  String get registerSubtitle => '加入成千上万分享路线的探索者';

  @override
  String get registerDisplayName => '显示名称';

  @override
  String get registerDisplayNameHelp =>
      '你的名称对他人显示的方式。最多 50 个字符，支持任意语言和表情符号。留空时使用 @用户名。';

  @override
  String get registerDisplayNameHint => '你的名称';

  @override
  String get registerUsername => '用户名 *';

  @override
  String get registerUsernameHelp => '你唯一的 @用户名。仅限小写字母、数字和下划线。之后无法更改。';

  @override
  String get registerUsernameHint => '你的用户名';

  @override
  String get registerDob => '出生日期 *';

  @override
  String get registerDobHelp =>
      'Ntripi 面向 16 周岁及以上的用户。我们只询问一次，它绝不会显示在你的个人资料中，其他用户也无法看到。';

  @override
  String get registerDobHint => '选择你的出生日期';

  @override
  String get registerDobRequired => '请填写你的出生日期。';

  @override
  String registerDobTooYoung(int age) {
    return '你必须年满 $age 周岁才能使用 Ntripi。';
  }

  @override
  String get dobPickerHelp => '选择你的出生日期';

  @override
  String get dobFromGoogle => '取自你的 Google 账户';

  @override
  String get googleConsentDobLabel => '出生日期';

  @override
  String get acceptTermsDobPrompt => '我们还需要你的出生日期。Ntripi 面向 16 周岁及以上的用户。';

  @override
  String get errorUnderage => '你必须年满 16 周岁才能使用 Ntripi。';

  @override
  String get errorDobRequired => '需要填写出生日期才能继续。';

  @override
  String get registerEmail => '邮箱 *';

  @override
  String get registerEmailHelp => '用于登录和找回账号。我们绝不会公开显示它。';

  @override
  String get registerEmailHint => 'you@example.com';

  @override
  String get registerEmailRequired => '邮箱为必填项。';

  @override
  String get registerEmailInvalid => '请输入有效的邮箱。';

  @override
  String get registerPassword => '密码 *';

  @override
  String get registerPasswordHelp => '至少 8 个字符，且至少包含一个数字。';

  @override
  String get registerPasswordHint => '至少 8 个字符';

  @override
  String get registerPasswordRequired => '密码为必填项。';

  @override
  String get registerPasswordTooShort => '至少需要 8 个字符。';

  @override
  String get registerPasswordNoDigit => '必须至少包含一个数字。';

  @override
  String get passwordTooLong => '密码过长——最多 72 个字符（含非拉丁字母时更少）。';

  @override
  String get registerConfirmPassword => '确认密码 *';

  @override
  String get registerConfirmPasswordHelp => '请再次输入密码以确保一致。';

  @override
  String get registerConfirmRequired => '请确认你的密码。';

  @override
  String get registerConfirmMismatch => '两次输入的密码不一致。';

  @override
  String get registerTosAgree => '我同意';

  @override
  String get registerTos => '服务条款';

  @override
  String get registerTosComma => '、';

  @override
  String get registerGuidelines => '社区准则';

  @override
  String get registerTosAnd => '和';

  @override
  String get registerPrivacyPolicy => '隐私政策';

  @override
  String get registerTosSuffix => '。';

  @override
  String get registerTosProhibited => '我了解，令人反感的内容和滥用行为一律严禁。';

  @override
  String get registerTosHelp => '你必须同意服务条款、社区准则和隐私政策才能创建账号。点按高亮的链接即可阅读。';

  @override
  String get registerTosRequired => '你必须接受服务条款和社区准则。';

  @override
  String get registerTosTitle => '服务条款';

  @override
  String get registerGuidelinesTitle => '社区准则';

  @override
  String get legalDocLoadFailed => '无法加载此文件。请检查网络连接后重试。';

  @override
  String get legalDocOpenInBrowser => '在浏览器中打开';

  @override
  String get googleTosTitle => '还差一步';

  @override
  String get googleTosSubtitle => '您正在创建新的 Ntripi 账户。请接受我们的条款以继续。';

  @override
  String get googleTosAccept => '接受并继续';

  @override
  String get acceptTermsTitle => '我们的条款已更新';

  @override
  String get acceptTermsBody => '我们更新了使用条款、社区准则和隐私政策。请阅读并接受后继续使用 Ntripi。';

  @override
  String get acceptTermsButton => '接受并继续';

  @override
  String get registerCreateAccount => '创建账号';

  @override
  String get registerAlreadyHaveAccount => '已有账号？ ';

  @override
  String get registerSignIn => '登录';

  @override
  String get followers => '粉丝';

  @override
  String get following => '关注';

  @override
  String get latestTrip => '最新行程';

  @override
  String get whereIveBeen => '我去过的地方';

  @override
  String get noStopsYet => '还没有停靠点';

  @override
  String get addFirstStop => '添加第一个停靠点';

  @override
  String get addStopHintTitle => '添加你的停靠点';

  @override
  String get addStopHintMessage => '要添加停靠点，请点按顶部的编辑 ✎。';

  @override
  String get addCoverHintMessage => '要添加封面图片，请点按顶部的此按钮。';

  @override
  String get longPressEditHintTitle => '长按即可编辑';

  @override
  String get longPressEditHintMessage => '长按行程中的任意部分——封面、注释或停靠点——即可直接编辑。';

  @override
  String get addProfilePhoto => '添加头像';

  @override
  String get addAvatarHintMessage => '要添加头像，请点按顶部的此按钮。';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个停靠点',
    );
    return '$_temp0';
  }

  @override
  String get expand => '展开';

  @override
  String get tapToSeeStops => '点按查看停靠点';

  @override
  String get coverImageSection => '封面图片';

  @override
  String get coverImageUrlLabel => '封面图片网址';

  @override
  String get uploadCoverImage => '上传封面图片';

  @override
  String followRequestsBannerTitle(int count) {
    return '关注请求（$count）';
  }

  @override
  String get tapToReview => '点按查看';

  @override
  String get editProfileTooltip => '编辑个人资料';

  @override
  String get settingsTooltip => '设置';

  @override
  String get shareProfileTooltip => '分享个人资料';

  @override
  String get couldNotLoadItineraries => '无法加载行程。';

  @override
  String get whereTheyveBeen => '他们去过的地方';

  @override
  String get itinerariesSectionHeader => '行程';

  @override
  String get noPublicItinerariesYet => '还没有公开的行程。';

  @override
  String get accountIsPrivateTitle => '该账号为私密账号';

  @override
  String get followRequestSentTitle => '请求已发送';

  @override
  String get followRequestPendingMessage => '对方接受你的请求后，你就能看到其行程、停靠点和旅行地图。';

  @override
  String followToSeeMessage(String handle) {
    return '关注 $handle 即可查看其行程、停靠点和旅行地图。';
  }

  @override
  String get editProfileTitle => '编辑个人资料';

  @override
  String get uploadPhoto => '上传照片';

  @override
  String get identitySection => '身份';

  @override
  String get displayNameLabel => '显示名称';

  @override
  String get usernameLabel => '用户名';

  @override
  String get bioLabel => '简介';

  @override
  String get bioHelpMessage => '简短的描述。支持 **加粗** markdown 和表情符号。';

  @override
  String get addBioLabel => '添加简介';

  @override
  String get avatarUrlLabel => '头像网址';

  @override
  String get travelIdentitySection => '旅行者身份';

  @override
  String get passportLabel => '护照';

  @override
  String get livesInLabel => '居住地';

  @override
  String get languagesLabel => '语言';

  @override
  String maxLanguagesReached(int count) {
    return '最多可添加 $count 种语言。';
  }

  @override
  String get privacySection => '隐私';

  @override
  String get securitySection => '安全';

  @override
  String get dangerZoneSection => '危险区域';

  @override
  String get privateAccountLabel => '私密账号';

  @override
  String get privateAccountSubtitle => '他人需先发送请求关注你，才能查看你的行程。';

  @override
  String get switchToPublicTitle => '切换为公开？';

  @override
  String switchToPublicMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '你有 $count 条待处理的关注请求。切换为公开后将自动全部接受。是否继续？',
    );
    return '$_temp0';
  }

  @override
  String get switchToPublicButton => '切换为公开';

  @override
  String get planFirstJourney => '规划你的第一次旅程';

  @override
  String get planFirstJourneyHint => '添加停靠点、交通路段和备注。与朋友分享，或保持私密。';

  @override
  String get createItinerary => '创建行程';

  @override
  String get needInspiration => '需要灵感？';

  @override
  String get browseForIdeas => '浏览社区动态获取灵感。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAccount => '账号';

  @override
  String get settingsNotifications => '通知';

  @override
  String get settingsNotificationsOn => '开启';

  @override
  String get settingsNotificationsOff => '关闭';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsSoundEffects => '音效';

  @override
  String get settingsSoundEffectsDetail => '在应用内执行操作时播放短提示音';

  @override
  String get settingsSupport => '支持';

  @override
  String get settingsHelpCenter => '帮助中心';

  @override
  String get settingsAbout => '关于 Ntripi';

  @override
  String get settingsTerms => '条款与隐私';

  @override
  String get settingsLogout => '退出登录';

  @override
  String get settingsDeleteAccount => '删除账号';

  @override
  String get logoutConfirmTitle => '退出登录';

  @override
  String get logoutConfirmMessage => '确定要退出登录吗？';

  @override
  String get logoutConfirmButton => '退出登录';

  @override
  String get languagePickerTitle => '语言';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageChinese => '简体中文';

  @override
  String get themePickerTitle => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get followRequestsTitle => '关注请求';

  @override
  String get noRequests => '没有待处理的请求';

  @override
  String requestsCountLabel(int count) {
    return '请求 · $count';
  }

  @override
  String get acceptButton => '接受';

  @override
  String get rejectButton => '拒绝';

  @override
  String followersTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 位粉丝',
      zero: '粉丝',
    );
    return '$_temp0';
  }

  @override
  String followingTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '关注 $count 人',
      zero: '关注',
    );
    return '$_temp0';
  }

  @override
  String followRequestsSectionLabel(int count) {
    return '关注请求 · $count';
  }

  @override
  String get allFollowersSection => '所有粉丝';

  @override
  String get noFollowersYet => '还没有粉丝。';

  @override
  String get notFollowingAnyone => '还没有关注任何人。';

  @override
  String get peopleYouFollow => '你关注的人';

  @override
  String get confirmButton => '确认';

  @override
  String get searchPeoplePlaceholder => '搜索用户…';

  @override
  String get searchForPeople => '搜索要关注的人';

  @override
  String get noUsersFound => '未找到用户。';

  @override
  String searchResultsCount(int count) {
    return '结果 · $count';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 位粉丝',
    );
    return '$_temp0';
  }

  @override
  String get searchUsersHelp => '通过 @用户名或显示名称查找用户。点按某个结果即可查看其个人资料。';

  @override
  String get myItineraries => '我的行程';

  @override
  String get noItinerariesYet => '还没有行程。';

  @override
  String get tapToCreateFirst => '点按 + 创建你的第一次旅行。';

  @override
  String get itinerariesScopeAll => '全部';

  @override
  String get itinerariesScopeMine => '我的';

  @override
  String get itinerariesScopeShared => '共享';

  @override
  String get sharedItinerariesEmpty => '没有与你共享的行程。';

  @override
  String get sharedItinerariesEmptyHint => '当有人把你添加为编辑者时，他们的行程会出现在这里。';

  @override
  String get editorBadgeLabel => '编辑者';

  @override
  String get deleteItineraryTitle => '删除此行程？';

  @override
  String get deleteItineraryMessage => '所有停靠点、注释、路段、评分和分享链接都将被永久销毁。此操作无法撤销。';

  @override
  String get deleteItineraryButton => '删除行程';

  @override
  String get newItinerary => '新建行程';

  @override
  String get editItinerary => '编辑行程';

  @override
  String get coverImageLabel => '封面图片';

  @override
  String get coverImageHelp => '一张 1200×630 的图片，显示在行程卡片和链接预览中。在裁剪框内拖动可重新定位。';

  @override
  String get itineraryTitleLabel => '标题 *';

  @override
  String get itineraryTitleHint => '例如：京都和大阪 10 日游';

  @override
  String get itineraryTitleHelp => '为此行程取一个简短清晰的名称。会显示在行程卡片和分享预览中。';

  @override
  String get itineraryTitleRequired => '标题为必填项';

  @override
  String get descriptionLabel => '描述';

  @override
  String get descriptionHelp =>
      '可选。行程摘要。使用工具栏可将文本加粗或倾斜、添加标题，以及创建项目符号或编号列表。切换到预览标签可查看读者看到的效果。';

  @override
  String get addDescriptionLabel => '添加描述';

  @override
  String get currencyLabel => '货币';

  @override
  String get currencyHelp => '此行程中所有停靠点费用和交通费用的默认货币。';

  @override
  String get visibilityLabel => '可见性';

  @override
  String get visibilityHelp =>
      '公开：任何人都可查看。粉丝：仅关注你的人。受限：仅你在下方添加到白名单的用户。仅自己：仅你可见。';

  @override
  String get visibilityPublic => '公开';

  @override
  String get visibilityFollowers => '粉丝';

  @override
  String get visibilityRestricted => '受限';

  @override
  String get visibilityOnlyMe => '仅自己';

  @override
  String get imageSaveButUploadFailed => '行程已保存，但图片上传失败。请从编辑界面重试。';

  @override
  String get formSectionBasics => '基本信息';

  @override
  String get formLabelCurrency => '货币';

  @override
  String get formLabelWhoCanSee => '谁可以查看？';

  @override
  String get formSectionDangerZone => '危险区域';

  @override
  String get formLabelDeleteItinerary => '删除行程';

  @override
  String get formDeleteItineraryHint => '输入标题以确认';

  @override
  String get currencySearchHint => '搜索货币…';

  @override
  String get bestTimeToVisit => '最佳出行时间';

  @override
  String get addBestTimeToVisit => '添加最佳出行时间';

  @override
  String get formLabelBestTime => '最佳出行时间';

  @override
  String get periodNotSet => '未设置';

  @override
  String get periodSectionMonths => '最佳月份';

  @override
  String get periodSectionWindows => '时间段';

  @override
  String get periodSectionWeekdays => '星期';

  @override
  String get periodSectionWhy => '为什么是这个时间？';

  @override
  String get periodMonthsHelp => '点选所有值得前往的月份。相邻的月份会合并为一个时间段。';

  @override
  String get periodNoMonthsSelected => '尚未选择月份';

  @override
  String get periodExactDays => '具体日期';

  @override
  String get periodStartsOn => '开始于';

  @override
  String get periodEndsOn => '结束于';

  @override
  String get periodWholeMonth => '整月';

  @override
  String get periodWeekdays => '工作日';

  @override
  String get periodWeekends => '周末';

  @override
  String get periodWhyHint => '例如：樱花盛开、气候宜人、人少';

  @override
  String get periodClear => '清除';

  @override
  String get periodClearConfirmTitle => '清除最佳出行时间？';

  @override
  String get periodClearConfirmMessage => '你选择的月份、具体日期、星期和备注都将被移除。';

  @override
  String currenciesLoadFailed(String error) {
    return '加载货币失败：$error';
  }

  @override
  String get deleteItineraryFormTitle => '删除行程';

  @override
  String deleteItineraryFormMessage(String title) {
    return '此操作将永久删除“$title”及其所有停靠点。请输入标题以确认。';
  }

  @override
  String get followButton => '关注';

  @override
  String get followingButton => '已关注';

  @override
  String get requestedButton => '已请求';

  @override
  String unfollowTitle(String username) {
    return '取消关注 @$username？';
  }

  @override
  String get unfollowMessage => '你将不再在动态中看到对方的行程。';

  @override
  String get unfollowConfirm => '取消关注';

  @override
  String get unfollowKeep => '继续关注';

  @override
  String unfollowedSnackbar(String username) {
    return '已取消关注 @$username';
  }

  @override
  String get cancelRequestTitle => '取消请求？';

  @override
  String cancelRequestMessage(String username) {
    return '取消向 @$username 发送的关注请求？';
  }

  @override
  String get cancelRequestConfirm => '取消请求';

  @override
  String get cancelRequestKeep => '保留';

  @override
  String get declineRequestTitle => '拒绝请求？';

  @override
  String declineRequestMessage(String username) {
    return '拒绝 @$username 的关注请求？对方之后可以再次发送请求。';
  }

  @override
  String get declineRequestConfirm => '拒绝';

  @override
  String get undoButton => '撤销';

  @override
  String couldNotUndo(String error) {
    return '无法撤销：$error';
  }

  @override
  String get errorNoInternet => '无网络连接。请检查你的网络后重试。';

  @override
  String get errorGenericRetry => '发生错误。请重试。';

  @override
  String get errorGeneric => '发生错误。';

  @override
  String get fieldHelpTooltip => '这是什么？';

  @override
  String typeToConfirmInstruction(String text) {
    return '请输入“$text”以确认：';
  }

  @override
  String get daysLabel => '天';

  @override
  String get noneOption => '无';

  @override
  String get discardButton => '放弃';

  @override
  String get discardChangesTitle => '放弃更改？';

  @override
  String get discardChangesMessage => '你的更改将不会被保存。';

  @override
  String get keepEditingButton => '继续编辑';

  @override
  String get orderSavedMessage => '顺序已保存';

  @override
  String get segmentSelectBothStops => '请同时选择出发和到达的停靠点。';

  @override
  String get segmentStopsMustDiffer => '出发和到达的停靠点必须不同。';

  @override
  String get segmentAddLegFirst => '保存前请至少添加一段行程。';

  @override
  String get segmentAlreadyExistsTitle => '路段已存在';

  @override
  String get segmentAlreadyExistsMessage => '已有一个路段连接这两个停靠点。你想怎么做？';

  @override
  String get segmentJoin => '合并';

  @override
  String get segmentReplace => '替换';

  @override
  String get segmentFromStopLabel => '出发停靠点';

  @override
  String get segmentToStopLabel => '到达停靠点';

  @override
  String get visibilityScreenTitle => '谁可以查看？';

  @override
  String get visibilityAddPerson => '添加用户';

  @override
  String get visibilitySearchByUsername => '按用户名搜索…';

  @override
  String get couldNotLoadRatings => '无法加载评分';

  @override
  String get stopNotFound => '未找到停靠点。';

  @override
  String get mapPickLocationTitle => '选择位置';

  @override
  String get mapConfirmLocation => '确认位置';

  @override
  String get stopCostHint => '例如：20';

  @override
  String get ratingsTitle => '评分';

  @override
  String get noRatingsYet => '还没有评分';

  @override
  String get ratingsOverallLabel => '总体';

  @override
  String get rateThisTrip => '评价此行程';

  @override
  String get editYourItinerary => '编辑你的行程';

  @override
  String get deletedUser => '已删除的用户';

  @override
  String get annotationContentHint => '旅行者应该知道些什么？';

  @override
  String get countryPickerTitle => '选择国家/地区';

  @override
  String get countrySearchHint => '搜索国家/地区…';

  @override
  String get countryNoneClear => '无 / 清除';

  @override
  String get languageSearchHint => '搜索语言…';

  @override
  String get coverChangeButton => '更改';

  @override
  String get coverEditCropButton => '编辑裁剪';

  @override
  String get coverAdjustTitle => '调整封面照片';

  @override
  String get mdBoldTooltip => '加粗';

  @override
  String get mdItalicTooltip => '倾斜';

  @override
  String get mdHeading1Tooltip => '标题 1';

  @override
  String get mdHeading2Tooltip => '标题 2';

  @override
  String get mdBulletListTooltip => '项目符号列表';

  @override
  String get mdNumberedListTooltip => '编号列表';

  @override
  String get mdEditTab => '编辑';

  @override
  String get mdPreviewTab => '预览';

  @override
  String get legCostHint => '例如：12.50';

  @override
  String get addLegButton => '添加行程段';

  @override
  String get totalLabel => '合计';

  @override
  String get reorderOrphanTitle => '保存重新排序？';

  @override
  String reorderOrphanMessage(int count, String segments) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个交通路段将被删除，因为其停靠点将不再位于相邻的列中：\n\n$segments',
    );
    return '$_temp0';
  }

  @override
  String get loadingLabel => '加载中…';

  @override
  String get usernameRequired => '用户名为必填项';

  @override
  String get usernameTooShort => '用户名至少需要 4 个字符';

  @override
  String get usernameTooLong => '用户名不能超过 30 个字符';

  @override
  String get usernameInvalidFormat => '仅限字母、数字、句点和下划线。必须以字母开头，以字母或数字结尾。';

  @override
  String get usernameConsecutiveSpecial => '不能有连续的句点或下划线';

  @override
  String get displayNameTooLong => '显示名称不能超过 50 个字符';

  @override
  String get comingSoon => '敬请期待';

  @override
  String get verifyEmailTitle => '验证你的邮箱';

  @override
  String get verifyEmailMessage => '验证你的邮箱即可解锁创建行程、评分和关注他人的功能。';

  @override
  String get verifyEmailButton => '使用 Google 验证';

  @override
  String get emailVerifiedSuccess => '邮箱已验证——一切就绪！';

  @override
  String get resendVerificationButton => '重新发送验证邮件';

  @override
  String get verificationEmailSent => '验证邮件已发送——请查看你的收件箱。';

  @override
  String get forgotPasswordTitle => '重置你的密码';

  @override
  String get forgotPasswordSubtitle => '输入你的账号邮箱，我们会向你发送一个用于设置新密码的链接。';

  @override
  String get forgotPasswordEmailLabel => '邮箱';

  @override
  String get forgotPasswordSubmit => '发送重置链接';

  @override
  String get forgotPasswordSentTitle => '请查看你的邮箱';

  @override
  String get forgotPasswordSentBody =>
      '如果该邮箱存在对应账号，我们已发送密码重置链接。请查看你的收件箱和垃圾邮件文件夹。';

  @override
  String get changePasswordTitle => '更改密码';

  @override
  String get changePasswordSubtitle => '输入你的当前密码，然后选择一个新密码。更改后会退出所有其他设备的登录。';

  @override
  String get changePasswordCurrentLabel => '当前密码';

  @override
  String get changePasswordNewLabel => '新密码';

  @override
  String get changePasswordConfirmLabel => '确认新密码';

  @override
  String get changePasswordMismatch => '两次输入的密码不一致。';

  @override
  String get changePasswordSameAsOld => '新密码必须与当前密码不同。';

  @override
  String get changePasswordSubmit => '更改密码';

  @override
  String get changePasswordConfirmMessage => '这会退出你所有其他设备的登录。是否继续？';

  @override
  String get changePasswordSuccess => '密码已更改。其他设备已退出登录。';

  @override
  String get backToSignIn => '返回登录';

  @override
  String get speaksLabel => '使用语言';

  @override
  String get removeButton => '移除';

  @override
  String get doneTooltip => '完成';

  @override
  String get addButton => '添加';

  @override
  String get deleteButton => '删除';

  @override
  String get deleteAccountTitle => '删除账号';

  @override
  String get deleteAccountConfirmTitle => '删除你的账号？';

  @override
  String get deleteAccountConfirmMessage =>
      '根据我们的隐私政策，你的账号、行程、关注关系和评分将被匿名化或删除。你将立即退出登录。此操作无法撤销。';

  @override
  String get deleteAccountRequiredText => '删除我的账号';

  @override
  String get deleteAccountConfirmLabel => '删除我的账号';

  @override
  String get deleteAccountPasswordError => '密码错误。请重试。';

  @override
  String get deleteAccountGenericError => '出了点问题。请重试。';

  @override
  String get deleteAccountCannotUndo => '此操作无法撤销';

  @override
  String get deleteAccountWillRemove => '删除你的账号将永久移除：';

  @override
  String get deleteAccountBullet1 => '你的个人资料和所有个人数据';

  @override
  String get deleteAccountBullet2 => '你的所有行程和停靠点';

  @override
  String get deleteAccountBullet3 => '你的关注关系';

  @override
  String get deleteAccountNote => '你对其他行程给出的评分将作为社区数据被匿名保留。';

  @override
  String get deleteAccountEnterPassword => '输入你的密码以确认';

  @override
  String get deleteAccountEnterPasswordError => '请输入你的密码以继续。';

  @override
  String get deleteAccountPasswordLabel => '密码';

  @override
  String get deleteAccountPasswordHelpTitle => '确认密码';

  @override
  String get deleteAccountPasswordHelpMessage =>
      '请重新输入你的密码以确认删除。账号删除是永久性的，无法撤销。';

  @override
  String get deleteAccountButton => '删除我的账号';

  @override
  String get deleteAccountGoogleExplain =>
      '此账号使用 Google 登录。请重新通过 Google 验证以确认删除。';

  @override
  String get deleteAccountGoogleButton => '使用 Google 继续';

  @override
  String get deleteAccountOrDivider => '或';

  @override
  String get deleteAccountGoogleAlternative => '更喜欢用 Google？可改用 Google 重新验证。';

  @override
  String get deleteAnnotationTitle => '删除注释？';

  @override
  String get deleteAnnotationMessage => '此操作将从行程中永久移除此注释。';

  @override
  String get deleteAnnotationStopMessage => '此注释将被永久移除。';

  @override
  String get removeTransitTitle => '移除停靠点之间的交通？';

  @override
  String get removeTransitMessage => '这两个停靠点之间的连接将被清除。你之后可以再添加一个。';

  @override
  String get reorderTracksTitle => '重新排列列';

  @override
  String get shareTooltip => '分享';

  @override
  String get editDetailsTooltip => '编辑详情和图片';

  @override
  String get descriptionSection => '描述';

  @override
  String get annotationsSection => '注释';

  @override
  String get addAnnotationButton => '添加注释';

  @override
  String get noAnnotationsYet => '还没有注释。';

  @override
  String get stopsList => '停靠点列表';

  @override
  String get editStopsButton => '编辑停靠点';

  @override
  String get addStopTooltip => '添加停靠点';

  @override
  String get reorderTracksTooltip => '重新排列列';

  @override
  String get mapSection => '地图';

  @override
  String get openInMaps => '在地图中打开';

  @override
  String get otherMapsApp => '其他地图应用';

  @override
  String get openRouteInMaps => '在 Google 地图中打开路线';

  @override
  String routeTruncated(int count) {
    return 'Google 地图只能显示前 $count 个停靠点';
  }

  @override
  String get openStreetMapContributors => 'OpenStreetMap 贡献者';

  @override
  String get poweredByOSM => '由 OpenStreetMap 提供支持';

  @override
  String get noStopsYetTapPlus => '还没有停靠点。点按 + 添加一个。';

  @override
  String get communityRating => '社区';

  @override
  String ratingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条评分',
    );
    return '$_temp0';
  }

  @override
  String get yourRating => '你的评分';

  @override
  String get rateIt => '评分';

  @override
  String deleteOrphanSegmentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除交通路段？',
    );
    return '$_temp0';
  }

  @override
  String deleteOrphanSegmentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 个交通路段连接这两个停靠点。在它们之间添加停靠点会将其隐藏，因为这两个停靠点将不再相邻。是否删除该路段并继续？',
    );
    return '$_temp0';
  }

  @override
  String get deleteAndContinue => '删除并继续';

  @override
  String get notSet => '未设置';

  @override
  String get stopDetailsView => '停靠点详情';

  @override
  String get editStopTitle => '编辑停靠点';

  @override
  String get addStopTitle => '添加停靠点';

  @override
  String get editStopTooltip => '编辑停靠点';

  @override
  String get duplicateStopTitle => '重复的停靠点';

  @override
  String duplicateStopMessage(String name) {
    return '$name 已在此行程中。仍要再次添加吗？';
  }

  @override
  String get addAnyway => '仍然添加';

  @override
  String get itineraryUpdatedTitle => '行程已在别处更新';

  @override
  String get itineraryUpdatedMessage => '此行程已从另一台设备编辑。请返回并重新加载以查看最新版本。';

  @override
  String get goBack => '返回';

  @override
  String get deleteStopTitle => '删除此停靠点？';

  @override
  String get deleteStopMessage => '此操作将移除该停靠点、其注释以及与之相连的所有交通路段。此操作无法撤销。';

  @override
  String get viewOnlyTitle => '仅查看';

  @override
  String get viewOnlyMessage => '点按编辑按钮以进行更改。';

  @override
  String get searchForPlaceLabel => '搜索地点';

  @override
  String get searchAPlaceHelpTitle => '搜索地点';

  @override
  String get searchAPlaceHelpMessage =>
      '输入地点、餐厅或地标的名称。选择一个结果即可自动填写下方的地点名称、地址和坐标。';

  @override
  String get searchPlaceHintText => '例如：巴黎埃菲尔铁塔';

  @override
  String get stopDetailsSectionLabel => '停靠点详情';

  @override
  String get placeNameLabel => '地点名称';

  @override
  String get placeNameHelp => '地点、餐厅、地标或停靠点的名称。';

  @override
  String get placeNameRequired => '地点名称为必填项';

  @override
  String get addressLabel => '地址';

  @override
  String get addressHelp => '街道地址或区域描述。可选。';

  @override
  String get mapLinkLabel => 'Google 地图链接';

  @override
  String get mapLinkHint => '粘贴一个 Google 地图链接';

  @override
  String get mapLinkInvalid => '请输入有效的 Google 地图链接';

  @override
  String get mapLinkPaste => '粘贴';

  @override
  String get mapLinkClear => '清除';

  @override
  String get locationModeCoordinates => '坐标';

  @override
  String get locationModeMapLink => 'Google 地图链接';

  @override
  String get linkPreviewOpensInMaps => '在 Google 地图中打开';

  @override
  String get linkPreviewLoading => '正在加载预览…';

  @override
  String get linkPreviewTitleCopied => '标题已复制';

  @override
  String get linkPreviewMapMobileOnly => '地图预览在移动应用中可用';

  @override
  String get coordinatesHelp => '此停靠点的地图位置。点按“在地图上选择”以设置或调整。';

  @override
  String get pickOnMap => '在地图上选择';

  @override
  String get placeTypeLabel => '地点类型';

  @override
  String get placeTypeHelp => '这是哪种类型的地点（例如餐饮、住宿、景点）。用于筛选和地图图标。';

  @override
  String get selectPlaceType => '选择地点类型';

  @override
  String get placeTypeEatDrink => '餐饮';

  @override
  String get placeTypeSleep => '住宿';

  @override
  String get placeTypePray => '祈祷';

  @override
  String get placeTypeLearnSee => '学习与参观';

  @override
  String get placeTypeBuy => '购物';

  @override
  String get placeTypePlayWatch => '运动与观赛';

  @override
  String get placeTypeNature => '自然';

  @override
  String get placeTypeTransport => '交通';

  @override
  String get placeTypeHealBathe => '疗养与沐浴';

  @override
  String get placeTypeEntertainment => '娱乐';

  @override
  String get placeTypeSight => '景点';

  @override
  String get placeTypeHintEatDrink => '咖啡馆、餐厅、酒吧、面包店、餐车';

  @override
  String get placeTypeHintSleep => '酒店、青年旅舍、露营地、旅馆、山间小屋';

  @override
  String get placeTypeHintPray => '教堂、清真寺、寺庙、犹太会堂、神社';

  @override
  String get placeTypeHintLearnSee => '博物馆、美术馆、图书馆、水族馆、天文台';

  @override
  String get placeTypeHintBuy => '商店、市场、商场、精品店、摊位';

  @override
  String get placeTypeHintPlayWatch => '体育场、健身房、竞技场、球场、保龄球馆';

  @override
  String get placeTypeHintNature => '海滩、公园、森林、山峰、瀑布';

  @override
  String get placeTypeHintTransport => '机场、火车站、公交车站、渡轮码头';

  @override
  String get placeTypeHintHealBathe => '水疗中心、温泉、泳池、桑拿、澡堂';

  @override
  String get placeTypeHintEntertainment => '剧院、电影院、音乐厅、夜店';

  @override
  String get placeTypeHintSight => '纪念碑、观景点、城堡、广场、遗址';

  @override
  String get recommendedTimeLabel => '建议停留时间';

  @override
  String get timeToSpendHelp => '你预计在此停留的大致时长。点按可设置天、小时和分钟。';

  @override
  String get stopIsFree => '此停靠点免费';

  @override
  String get freeHelp => '如果参观此地点无需花费，请开启。';

  @override
  String get costLabel => '费用';

  @override
  String get costHelp => '每人的大致费用，以行程货币计。';

  @override
  String get enterValidNumber => '请输入有效的数字';

  @override
  String get thoughtsLabel => '感想';

  @override
  String get thoughtsHelp =>
      '你对此停靠点的个人看法——有什么值得期待、你喜欢什么、有什么可以跳过、开放时间小贴士。使用工具栏可添加加粗、倾斜、标题或项目符号列表。';

  @override
  String get annotationsLabel => '注释';

  @override
  String get annotationsHelp => '附加到此停靠点的简短带标签备注（建议、注意、避免、信息）。适用于警告或提示。';

  @override
  String get saveChangesButton => '保存更改';

  @override
  String get addStopButton => '添加停靠点';

  @override
  String get deleteStopButton => '删除停靠点';

  @override
  String get timeToSpendModalTitle => '停留时间';

  @override
  String get editTransitTitle => '编辑交通';

  @override
  String get addTransitTitle => '添加交通';

  @override
  String get updateTransitButton => '更新交通';

  @override
  String get transportModeLabel => '方式';

  @override
  String get transportModeHelp =>
      '你在此行程段的出行方式（步行、公交、火车、渡轮等）。某些方式会显示线路和方向的额外字段。';

  @override
  String get transitLineLabel => '线路（可选）';

  @override
  String get transitLineHelp => '可选。线路编号或名称（例如“42 路公交”“M1”）。';

  @override
  String get transitDirectionLabel => '方向（可选）';

  @override
  String get transitDirectionHelp => '可选。线路的行进方向（例如“北向”“Châtelet”）。';

  @override
  String get durationLabel => '时长';

  @override
  String get durationHelp => '此行程段耗时，以小时和分钟计。';

  @override
  String get legCostHelp => '以行程货币计的大致费用。开启“免费”时禁用。';

  @override
  String get hoursLabel => '小时';

  @override
  String get minutesLabel => '分钟';

  @override
  String get freeLegLabel => '免费';

  @override
  String get freeLegHelp => '如果此行程段无需花费（步行、含在内的换乘等），请开启。';

  @override
  String get legThoughtsLabel => '感想（可选）';

  @override
  String get legThoughtsHelp => '可选。任何关于此行程段值得知道的信息——预订小贴士、换乘说明、座位选择、票价上的意外。';

  @override
  String get annotationTypeLabel => '类型';

  @override
  String get annotationTypeHelp => '建议：有用的提示。注意：需要小心。避免：不要去。信息：中立的说明。';

  @override
  String get annotationAdvice => '建议';

  @override
  String get annotationCaution => '注意';

  @override
  String get annotationAvoid => '避免';

  @override
  String get annotationInfo => '信息';

  @override
  String get annotationContentLabel => '内容 *';

  @override
  String get annotationContentHelp => '用一两句话描述你的建议、注意事项、警告或说明。';

  @override
  String get annotationContentRequired => '内容为必填项';

  @override
  String get editAnnotationTitle => '编辑注释';

  @override
  String get addAnnotationDialogTitle => '添加注释';

  @override
  String get saveButton => '保存';

  @override
  String get moveStopTitle => '移动停靠点';

  @override
  String moveStopDescription(int max) {
    return '选择现有列、用于新建列的空位，或将其提取到单独的列中。已达到 $max 个停靠点上限的列已停用。';
  }

  @override
  String get extractIntoOwnTrack => '提取到单独的新列';

  @override
  String get moveButton => '移动';

  @override
  String moveStopMoved(String destination) {
    return '已移动到 $destination';
  }

  @override
  String get itineraryChangedElsewhere => '行程已在别处更改——请关闭后重新打开以查看最新顺序。';

  @override
  String get moveStopOrphan1 => '这是该列中的最后一个停靠点——该列将从行程中移除。';

  @override
  String moveStopOrphanSegments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个交通路段将被删除，因为其停靠点将不再位于相邻的列中。',
    );
    return '$_temp0';
  }

  @override
  String get moveStopNewTrack => '新建列';

  @override
  String moveStopNewTrackBefore(int n) {
    return '在第 $n 列之前新建列';
  }

  @override
  String moveStopNewTrackAfter(int n) {
    return '在第 $n 列之后新建列';
  }

  @override
  String moveStopNewTrackBetween(int a, int b) {
    return '在第 $a 列和第 $b 列之间新建列';
  }

  @override
  String get moveStopCurrentSuffix => '  •  当前';

  @override
  String moveStopFull(int max) {
    return '已满 $max/$max';
  }

  @override
  String extractSubtitle(String trackName) {
    return '将此停靠点从“$trackName”中分离——新列紧随其后。';
  }

  @override
  String get removeRatingTitle => '移除你的评分？';

  @override
  String get removeRatingMessage => '你的评分将被删除，平均分会为所有查看此行程的人更新。';

  @override
  String get rateItineraryTitle => '评价此行程';

  @override
  String get overallRatingLabel => '总体 *';

  @override
  String get overallRatingHelp => '必填。你对此行程的总体评分，1 到 5 星。';

  @override
  String get ratingThanksMessage => '谢谢！你的评分能帮助他人。';

  @override
  String get yourImpressionLabel => '你的印象（可选）';

  @override
  String get yourImpressionHelp =>
      '可选。分享让你印象深刻的地方——亮点、遗憾、会推荐给谁。使用工具栏可添加加粗、倾斜、标题或项目符号列表。';

  @override
  String get removeMyRatingTooltip => '移除我的评分';

  @override
  String get wantToShareMore => '想分享更多吗？（可选）';

  @override
  String get safetyLabel => '安全';

  @override
  String get safetyHelp => '可选。此行程期间你的安全感如何。';

  @override
  String get experienceLabel => '体验';

  @override
  String get experienceHelp => '可选。此行程的愉悦度和难忘程度如何。';

  @override
  String get accessibilityLabel => '无障碍';

  @override
  String get accessibilityHelp => '可选。此行程的无障碍程度如何（出行、语言、标识）。';

  @override
  String get familyFriendlyLabel => '适合家庭';

  @override
  String get familyFriendlyHelp => '可选。此行程对有孩子的家庭的适宜程度如何。';

  @override
  String get crowdednessLabel => '不拥挤';

  @override
  String get crowdednessHelp => '可选。感觉有多不拥挤、多宽敞——5 = 舒适不拥挤，1 = 过度拥挤。';

  @override
  String get showOptionalFields => '显示可选字段';

  @override
  String get hideOptionalFields => '隐藏可选字段';

  @override
  String get transportModeWalk => '步行';

  @override
  String get transportModeBus => '公交车';

  @override
  String get transportModeTram => '有轨电车';

  @override
  String get transportModeMetro => '地铁';

  @override
  String get transportModeTrain => '火车';

  @override
  String get transportModeTaxi => '出租车';

  @override
  String get transportModeUber => 'Uber';

  @override
  String get transportModeBike => '自行车';

  @override
  String get transportModeFerry => '渡轮';

  @override
  String get transportModeCar => '汽车';

  @override
  String get transportModeAirplane => '飞机';

  @override
  String get dimensionOverall => '总体';

  @override
  String get dimensionOverallDesc => '总体印象';

  @override
  String get dimensionSafetyDesc => '全程的安全感如何';

  @override
  String get dimensionExperienceDesc => '整体体验的质量';

  @override
  String get dimensionAccessibilityDesc => '对所有人的无障碍程度';

  @override
  String get dimensionFamilyFriendlyDesc => '对儿童和家庭的适宜程度';

  @override
  String get dimensionCrowdednessDesc => '感觉有多不拥挤、多宽敞';

  @override
  String dimensionRatingTitle(String label) {
    return '$label评分';
  }

  @override
  String noRatingsYetFor(String label) {
    return '尚无关于$label的评分';
  }

  @override
  String basedOnRatings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '基于 $count 条评分',
    );
    return '$_temp0';
  }

  @override
  String get ratersLabel => '评分者';

  @override
  String get annotationAdviceDesc => '有用的信息或专业小贴士。';

  @override
  String get annotationCautionDesc => '请留意——可能有意外。';

  @override
  String get annotationAvoidDesc => '别这么做，节省你的时间。';

  @override
  String get annotationInfoDesc => '值得知道的中立信息。';

  @override
  String get unknownUser => '未知';

  @override
  String timeAgoMonths(int count) {
    return '$count 个月前';
  }

  @override
  String timeAgoDays(int count) {
    return '$count 天前';
  }

  @override
  String timeAgoHours(int count) {
    return '$count 小时前';
  }

  @override
  String timeAgoMinutes(int count) {
    return '$count 分钟前';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String get yearsAbbrev => '年';

  @override
  String get timeLabel => '时间';

  @override
  String get transitLabel => '交通';

  @override
  String get noLegsYetTapAdd => '还没有行程段。点按 ＋ 添加。';

  @override
  String get segmentNeedsOneLeg => '一个路段至少需要一段行程。请改为删除该路段。';

  @override
  String fromStopName(String name) {
    return '从 $name';
  }

  @override
  String toStopName(String name) {
    return '到 $name';
  }

  @override
  String get visibilityPublicDesc => '任何拥有链接的人都可查看。';

  @override
  String get visibilityFollowersDesc => '仅关注你的人。';

  @override
  String get visibilityRestrictedDesc => '仅你允许的人。';

  @override
  String get visibilityOnlyMeDesc => '仅你自己。';

  @override
  String get saveItineraryFirstAllowlist => '请先保存行程，然后从编辑界面管理你的白名单。';

  @override
  String get allowlistLabel => '白名单';

  @override
  String personCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 人',
    );
    return '$_temp0';
  }

  @override
  String removedFromAllowlist(String name) {
    return '已将 $name 从白名单中移除';
  }

  @override
  String get addPeople => '添加用户';

  @override
  String get otherOption => '其他';

  @override
  String get thisItineraryFallback => '此行程';

  @override
  String get discardReorderMessage => '你的重新排序将不会被保存。';

  @override
  String get emptyTrackName => '（空）';

  @override
  String get unnamedStop => '（未命名）';

  @override
  String get unknownStop => '（未知）';

  @override
  String get dragToChangeTrackOrder => '拖动以更改列的顺序';

  @override
  String transitSegmentsWillBeDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个交通路段将被删除',
    );
    return '$_temp0';
  }

  @override
  String andMoreCount(int count) {
    return '… 还有 $count 个';
  }

  @override
  String altsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个备选',
    );
    return '$_temp0';
  }

  @override
  String segmentToWillBeDeleted(String name) {
    return '→ $name  —  该路段将被删除';
  }

  @override
  String get reorderAlternativesTitle => '重新排列备选项';

  @override
  String get reorderAlternativesHint => '拖动以更改哪个选项排在最前。点按保存以应用。';

  @override
  String get emptyTrackLabel => '（空列）';

  @override
  String get moveStopToLabel => '将停靠点移动到';

  @override
  String get messageLabel => '留言';

  @override
  String get annotationKeepShortHint => '尽量简短——不超过 200 个字符在小屏幕上阅读效果最佳。';

  @override
  String get transportModeSection => '交通方式';

  @override
  String get lineDirectionSection => '线路与方向';

  @override
  String get durationCostSection => '时长与费用';

  @override
  String get allRatersLabel => '所有评分者';

  @override
  String travelersRatedThis(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 位旅行者评价了此行程',
    );
    return '$_temp0';
  }

  @override
  String get byDimensionLabel => '按维度';

  @override
  String get notEnoughRatings => '评分不足';

  @override
  String get youRatedThis => '你已评价此行程';

  @override
  String get changeButton => '更改';

  @override
  String get hideReview => '隐藏评价';

  @override
  String get readReview => '阅读评价';

  @override
  String get notesLabel => '备注';

  @override
  String get viewLess => '收起';

  @override
  String get viewMore => '... 查看更多';

  @override
  String get imageTooLarge => '图片过大（最大 10 MB）。';

  @override
  String get couldNotLoadImage => '无法加载图片。请尝试另一张。';

  @override
  String get pinchToZoomHint => '双指缩放 · 拖动以重新定位';

  @override
  String get addCoverImage => '添加封面图片';

  @override
  String get coverOptionalMapFallback => '可选——否则将使用地图。';

  @override
  String get noCoverImage => '无封面图片';

  @override
  String get mapTapToPlacePin => '点按地图以放置标记';

  @override
  String get mapTapToMovePin => '点按别处以移动标记，然后点按确认';

  @override
  String get mapMyLocation => '我的位置';

  @override
  String get mapUseMyLocation => '使用我的位置';

  @override
  String get mapSearchNoResults => '未找到地点。';

  @override
  String get mapSearchThisArea => '搜索此区域';

  @override
  String get mapUnnamedPlace => '未命名的位置';

  @override
  String get locationPermissionDenied => '位置权限被拒绝';

  @override
  String get locationServiceDisabled => '定位服务已禁用';

  @override
  String get locationUnavailable => '无法获取你的位置';

  @override
  String get locationOpenSettings => '打开设置';

  @override
  String get nothingToPreview => '暂时没有可预览的内容。';

  @override
  String get rateOverallFirstHint => '先为你的总体印象评分。评分后即可分享更多。';

  @override
  String get splashTagline => '发现并分享由真实旅行者\n精心打造的旅行行程';

  @override
  String get splashMotto => '探索世界，一次一条路线';

  @override
  String get tripsPillLabel => '行程';

  @override
  String get stopsPillLabel => '停靠点';

  @override
  String get travelledPillLabel => '已走过';

  @override
  String get stopFallbackName => '停靠点';

  @override
  String stopWithNumber(int n) {
    return '第 $n 个停靠点';
  }

  @override
  String get undoLabel => '撤销';

  @override
  String get updateYourRating => '更新你的评分';

  @override
  String get moveActionLabel => '移动';

  @override
  String get reorderActionLabel => '重新排序';

  @override
  String get addParallelStopLabel => '// 停靠点';

  @override
  String get aStopFallback => '一个停靠点';

  @override
  String get locationLabel => '位置';

  @override
  String get noLocationSet => '未设置位置';

  @override
  String get latitudeLabel => '纬度';

  @override
  String get longitudeLabel => '经度';

  @override
  String get invalidLatitudeError => '纬度必须是介于 -90 和 90 之间的数字';

  @override
  String get invalidLongitudeError => '经度必须是介于 -180 和 180 之间的数字';

  @override
  String get coordinatesPairRequiredError => '请同时输入纬度和经度';

  @override
  String get detailsSection => '详情';

  @override
  String get selectLanguagesTitle => '选择语言';

  @override
  String get done => '完成';

  @override
  String alreadyInItinerary(String name) {
    return '$name 已在此行程中。';
  }

  @override
  String stopNumberOfTotal(int n, int total) {
    return '第 $n 个停靠点，共 $total 个';
  }

  @override
  String shareCaption(String title, String stops, String duration) {
    return '在 Ntripi 上查看“$title” — $stops，$duration';
  }

  @override
  String shareProfileCaption(String name) {
    return '$name 在 Ntripi — 看看 TA 去过哪些地方';
  }

  @override
  String get apiErrorNotAuthenticated => '你尚未登录。';

  @override
  String get apiErrorAccountDeactivated => '你的账号已被停用。';

  @override
  String get apiErrorEmailUnverified => '请通过 Google 验证你的邮箱以执行此操作。';

  @override
  String get apiErrorItineraryNotFound => '未找到行程。';

  @override
  String get apiErrorItineraryNotOwner => '你无权修改此行程。';

  @override
  String get apiErrorIfMatchRequired => '无法保存此更改——请重新加载后重试。';

  @override
  String get apiErrorItineraryStale => '行程已被修改——请重新加载。';

  @override
  String get apiErrorWaitlistContactRequired => '请至少提供一个邮箱或 WhatsApp 号码。';

  @override
  String get apiErrorGoogleTokenInvalid => 'Google 令牌无效。';

  @override
  String get apiErrorInvalidGrant => '你的会话已过期。请重新登录。';

  @override
  String get apiErrorStopNotFound => '未找到停靠点。';

  @override
  String get apiErrorTrackNotFound => '未找到该列，或它不属于此行程。';

  @override
  String get apiErrorSegmentNotFound => '未找到交通路段。';

  @override
  String get apiErrorLegNotFound => '未找到交通段。';

  @override
  String get apiErrorItineraryAccessDenied => '你无权访问此行程。';

  @override
  String get apiErrorAllowlistRestrictedOnly => '白名单仅适用于受限行程。';

  @override
  String get apiErrorUserNotFound => '未找到用户。';

  @override
  String get apiErrorAllowlistUserExists => '该用户已拥有访问权限。';

  @override
  String get apiErrorAllowlistUserNotFound => '在白名单中未找到该用户。';

  @override
  String get apiErrorRankCollision => '排序冲突——请重试。';

  @override
  String get apiErrorAnnotationNotFound => '未找到注释。';

  @override
  String get apiErrorRatingNotFound => '你尚未评价此行程。';

  @override
  String get apiErrorSegmentAlreadyExists => '已有一个路段连接这两个停靠点。';

  @override
  String get apiErrorIncorrectPassword => '密码错误。';

  @override
  String get apiErrorLoginInvalid => '邮箱/用户名或密码错误。';

  @override
  String get apiErrorCannotFollowSelf => '你不能关注自己。';

  @override
  String get apiErrorNotFollowing => '你没有关注该用户。';

  @override
  String get apiErrorFollowRequestNotFound => '未找到关注请求。';

  @override
  String get apiErrorFollowRequestAlreadyAccepted => '该关注请求已被接受。';

  @override
  String get apiErrorCannotRejectRequest => '你无法拒绝此关注请求。';

  @override
  String get apiErrorAccountPrivate => '该账号为私密账号。';

  @override
  String get apiErrorTosRequired => '注册前必须接受服务条款。';

  @override
  String get apiErrorUsernameTaken => '该用户名已被占用。';

  @override
  String get apiErrorEmailTaken => '使用此邮箱的账号已存在。';

  @override
  String get reportItineraryTitle => '举报此行程';

  @override
  String get reportItineraryTooltip => '举报';

  @override
  String get reportReasonSpam => '垃圾内容';

  @override
  String get reportReasonNsfw => '裸露或性相关内容';

  @override
  String get reportReasonViolence => '暴力';

  @override
  String get reportReasonHateSpeech => '仇恨言论';

  @override
  String get reportReasonHarassment => '骚扰';

  @override
  String get reportReasonCopyright => '侵犯版权';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportNotesHint => '补充说明（可选）';

  @override
  String get reportSubmit => '提交举报';

  @override
  String get reportThanks => '谢谢。我们会审核此举报。';

  @override
  String get apiErrorReportOwnContent => '你无法举报自己的内容。';

  @override
  String get apiErrorReportRateLimited => '举报次数过多。请稍后再试。';

  @override
  String get imageBlockedNsfw => '此图片似乎包含不允许的内容。';

  @override
  String get apiErrorImageModerationRejected => '无法上传此图片，因为它可能包含违禁内容。';

  @override
  String get suspendedTitle => '你的账号已被封停';

  @override
  String get suspendedMessage => '管理员因违反社区准则封停了此账号。封停期间你无法登录。';

  @override
  String get suspendedAppealButton => '申诉此决定';

  @override
  String get suspendedBackToLogin => '返回登录';

  @override
  String get hiddenBannerTitle => '已被管理员隐藏';

  @override
  String get hiddenBannerMessage =>
      '只有你能看到此行程。它不会出现在动态、搜索或分享页面中。你可以在设置的“账号状态”中申诉。';

  @override
  String get hiddenReviewMessage => '只有你能看到此评价。它不会显示在行程中，也不计入行程评分。';

  @override
  String get hiddenProfileMessage => '只有你能看到你的昵称和简介。其他人只会看到你的 @用户名。';

  @override
  String get accountStatusTitle => '账号状态';

  @override
  String get violationsEmpty => '你的账号没有任何管理操作记录。';

  @override
  String get violationHidden => '已隐藏';

  @override
  String get violationRemoved => '已移除';

  @override
  String get violationWarned => '警告';

  @override
  String get violationBanned => '封停';

  @override
  String get violationOther => '管理操作';

  @override
  String get violationLifted => '已解除';

  @override
  String get appealPending => '申诉审核中';

  @override
  String get appealRejected => '申诉被驳回';

  @override
  String get appealRestored => '已恢复';

  @override
  String get appealReduced => '处罚已减轻';

  @override
  String get appealAvailable => '可申诉';

  @override
  String get appealSubmit => '申诉';

  @override
  String get appealSubmitted => '申诉已提交，结果将通过邮件通知你。';

  @override
  String get appealFormTitle => '申诉此决定';

  @override
  String get appealFormMessage => '请说明你认为此决定有误的原因，管理员会进行复核。';

  @override
  String get appealReasonLabel => '你的说明';

  @override
  String get appealReasonRequired => '请说明申诉理由。';

  @override
  String appealCooldownUntil(String date) {
    return '你可以在 $date 之后再次申诉。';
  }

  @override
  String get apiErrorAppealPending => '该项目已有一条待处理的申诉。';

  @override
  String get apiErrorAppealCooldown => '申诉被驳回后，需满 30 天才能再次申诉该项目。';

  @override
  String get apiErrorAppealTargetNotFound => '此处没有可申诉的管理操作。';

  @override
  String get apiErrorTextModerationRejected => '这段文字可能违反社区准则，未能保存。请修改后重试。';

  @override
  String get apiErrorCannotBlockSelf => '你不能屏蔽自己。';

  @override
  String moderationRejectedBecause(String reason) {
    return '这段文字未能保存，因为其中可能包含$reason。请修改后重试。';
  }

  @override
  String get moderationCategoryMinors => '涉及未成年人的内容';

  @override
  String get moderationCategorySexual => '色情内容';

  @override
  String get moderationCategoryHate => '仇恨言论';

  @override
  String get moderationCategoryHarassment => '骚扰内容';

  @override
  String get moderationCategoryViolence => '暴力内容';

  @override
  String get moderationCategorySelfHarm => '有关自我伤害的内容';

  @override
  String get moderationCategoryIllicit => '非法活动';

  @override
  String get reportReasonCsam => '儿童性虐待内容';

  @override
  String get reportReasonSexualContent => '裸露或色情内容';

  @override
  String get reportReasonViolenceThreat => '暴力或威胁';

  @override
  String get reportContent => '举报';

  @override
  String get reportUser => '举报该账号';

  @override
  String get reportStop => '举报该地点';

  @override
  String get reportReview => '举报该评价';

  @override
  String get reportAnnotation => '举报该注释';

  @override
  String get blockUser => '屏蔽';

  @override
  String get unblockUser => '解除屏蔽';

  @override
  String blockUserTitle(String username) {
    return '屏蔽 @$username？';
  }

  @override
  String get blockUserMessage => '你们将无法看到彼此的行程和主页，也无法互相关注。对方不会收到通知。';

  @override
  String get blockedUsers => '已屏蔽的账号';

  @override
  String get blockedUsersEmpty => '你还没有屏蔽任何人。';

  @override
  String get profileUnavailableTitle => '账号不可用';

  @override
  String get profileUnavailableMessage => '该账号不存在或已不再可用。';

  @override
  String blockedUserRemoved(String username) {
    return '已解除屏蔽 @$username。';
  }

  @override
  String blockedUserAdded(String username) {
    return '已屏蔽 @$username。';
  }

  @override
  String get abuseContact => '举报滥用行为';

  @override
  String get abuseContactSubtitle => '就有害内容与我们联系';

  @override
  String get communityGuidelines => '社区准则';

  @override
  String get moderationHintTitle => '这段文字可能会被视为冒犯';

  @override
  String get moderationHintBody => '你仍然可以发布——这只是提醒，不会阻止你。';

  @override
  String get hiddenAppealAction => '申请复核';

  @override
  String hiddenBannerReason(String reason) {
    return '原因：$reason';
  }

  @override
  String get bugReportTitle => '报告问题';

  @override
  String get bugReportHint => '出了什么问题？';

  @override
  String get bugReportSubmit => '发送报告';

  @override
  String get bugReportThanks => '谢谢。我们会跟进处理。';

  @override
  String get bugReportAttachmentNotice => '将附上你的屏幕截图和设备信息。';

  @override
  String get bugReportCategoryCrash => '应用卡住或闪退';

  @override
  String get bugReportCategoryVisual => '显示异常';

  @override
  String get bugReportCategoryData => '信息有误或缺失';

  @override
  String get bugReportCategorySlow => '太慢了';

  @override
  String get bugReportCategoryOther => '其他问题';

  @override
  String get bugReportNavigate => '浏览';

  @override
  String get bugReportDraw => '标注';

  @override
  String get settingsReportBug => '报告错误';

  @override
  String get settingsShakeToReport => '摇一摇报告';

  @override
  String get settingsShakeToReportDetail => '摇动手机即可报告问题';

  @override
  String get notificationsTitle => '通知';

  @override
  String get notificationsEmpty => '暂时没有内容。\n关注、评分和收藏都会显示在这里。';

  @override
  String notificationsCountLabel(int count) {
    return '最近 · $count';
  }

  @override
  String get notificationSomeone => '某人';

  @override
  String get notificationGeneric => '你有一条新通知。';

  @override
  String get notificationTapForDetails => '点击查看详情并申诉';

  @override
  String notificationFollowRequest(String name) {
    return '$name 请求关注你';
  }

  @override
  String notificationNewFollower(String name) {
    return '$name 关注了你';
  }

  @override
  String notificationFollowAccepted(String name) {
    return '$name 接受了你的关注请求';
  }

  @override
  String notificationRated(String name) {
    return '$name 评价了你的一条行程';
  }

  @override
  String notificationSaved(String name) {
    return '$name 收藏了你的一条行程';
  }

  @override
  String notificationEditorAdded(String name, String title) {
    return '$name 把你添加为“$title”的编辑者';
  }

  @override
  String notificationEditorAddedUntitled(String name) {
    return '$name 把你添加为一条行程的编辑者';
  }

  @override
  String get notificationEditorAddedDetail => '你现在可以修改它的停靠点、简介和备注';

  @override
  String notificationViewerAdded(String name, String title) {
    return '$name 与你分享了“$title”';
  }

  @override
  String notificationViewerAddedUntitled(String name) {
    return '$name 与你分享了一条行程';
  }

  @override
  String get notificationViewerAddedDetail => '你现在可以打开这条行程';

  @override
  String notificationHidden(String title) {
    return '“$title”已被隐藏';
  }

  @override
  String get notificationHiddenUntitled => '你的一条行程已被隐藏';

  @override
  String notificationRemoved(String title) {
    return '“$title”已被移除';
  }

  @override
  String get notificationRemovedUntitled => '你的一条行程已被移除';

  @override
  String get notificationSettingsOptionalLabel => '可选';

  @override
  String get notificationSettingsRatings => '评分';

  @override
  String get notificationSettingsRatingsDetail => '当有人评价你的行程时';

  @override
  String get notificationSettingsSaves => '收藏';

  @override
  String get notificationSettingsSavesDetail => '当有人收藏你的行程时';

  @override
  String get notificationSettingsFollowAccepted => '请求已接受';

  @override
  String get notificationSettingsFollowAcceptedDetail => '当有人接受你的关注请求时';

  @override
  String get notificationSettingsAlwaysOnNote =>
      '关注请求和审核通知始终开启。你看不到的请求无法处理，而且你需要知道内容何时被隐藏，才能及时申诉。';

  @override
  String settingsNotificationsOnCount(int count) {
    return '已开启 $count / 3';
  }

  @override
  String get notificationWarned => '你收到了一条审核警告';

  @override
  String get notificationWarnedDetail => '点击查看原因并申诉';

  @override
  String get helpCenterFaqLabel => '常见问题';

  @override
  String get helpCenterGetHelpLabel => '获取帮助';

  @override
  String get helpCenterLegalLabel => '法律条款';

  @override
  String get helpCenterContactSupport => '联系客服';

  @override
  String get helpCenterContactSupportSubtitle => '其他问题请发邮件给我们';

  @override
  String get helpCenterAccountStatusSubtitle => '查看审核决定并提出申诉';

  @override
  String get faqItineraryQ => '什么是行程？';

  @override
  String get faqItineraryA =>
      '行程是你一站一站搭建起来的旅行——吃饭、住宿、参观或途经的地点，按你实际前往的顺序排列。你可以只留给自己，分享给关注你的人，或者公开给所有人。';

  @override
  String get faqTracksQ => '什么是并行站点？';

  @override
  String get faqTracksA =>
      '旅行中的某些环节不止一个好答案。并行站点在行程的同一位置并排排列——同一个下午的两种过法。当你想提供选择而不是固定路线时，就添加一个。';

  @override
  String get faqVisibilityQ => '谁能看到我的行程？';

  @override
  String get faqVisibilityA =>
      '每条行程都由你决定。仅自己可见会保持私密，也是默认设置。关注者会展示给关注你的人。受限仅展示给你挑选的人。公开则会放入发现页，所有人都能看到。';

  @override
  String get faqRatingsQ => '评分是怎么运作的？';

  @override
  String get faqRatingsA =>
      '只有 1 到 5 分的总体评分是必填的。你还可以为安全性、体验、无障碍程度、是否适合家庭以及拥挤程度打分。这些平均分只有在至少三个人评过之后才会显示，这样单独一条意见就不会被当成定论。';

  @override
  String get faqSaveQ => '收藏有什么用？';

  @override
  String get faqSaveA =>
      '收藏会把别人的行程放进你的「已收藏」标签页，方便再次找到。行程作者会知道你收藏了它，但其他人看不到你的收藏列表。';

  @override
  String get faqPrivateAccountQ => '什么是私密账号？';

  @override
  String get faqPrivateAccountA =>
      '使用私密账号时，别人必须先申请才能关注你，每条申请由你同意或拒绝。通过之后，他们就能看到你分享给关注者的行程。';

  @override
  String get faqBlockReportQ => '怎么拉黑或举报某人？';

  @override
  String get faqBlockReportA =>
      '打开对方主页，使用右上角的菜单。拉黑会让你们在两个方向上都彼此不可见，随时可以在设置里取消。举报会把内容送交我们的审核团队，且绝不会告诉对方是谁举报的。';

  @override
  String get faqStaleEditQ => '为什么提示行程已被修改？';

  @override
  String get faqStaleEditA =>
      '在你的编辑器打开期间，有访问权限的人——或者你在另一台设备上——修改了这条行程。重新加载以取得对方的版本，然后再做一次你的改动。正是这一点避免了两次编辑悄悄互相覆盖。';

  @override
  String get reportBugShakeHeadline => '摇一摇手机';

  @override
  String get reportBugShakeBody =>
      '不要在这里报告问题。回到问题发生的地方，摇一摇手机——我们会截下那一屏，让你圈出到底哪里出了错。';

  @override
  String get reportBugStepsLabel => '使用方法';

  @override
  String get reportBugShakeStep1 => '回到出现问题的那个界面';

  @override
  String get reportBugShakeStep2 => '摇一摇手机';

  @override
  String get reportBugShakeStep3 => '圈出问题，并告诉我们发生了什么';

  @override
  String get reportBugGestureOff => '摇一摇报告目前已关闭。开启后即可使用该手势。';

  @override
  String get reportBugWebBody => '浏览器中无法使用摇一摇。请用下方按钮就本页面向我们提交反馈。';

  @override
  String get aboutTagline => '旅行行程，共同分享。';

  @override
  String get aboutBody =>
      '在 Ntripi，旅行者一站一站搭建自己的行程，并分享真正好用的那些安排。每条行程都属于你，直到你另有决定——保持私密、只分享给你挑选的人，或者公开让所有人跟着走。';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutWebsite => '官方网站';

  @override
  String get aboutLicenses => '开源许可';

  @override
  String aboutCopyright(int year) {
    return '© $year Ntripi';
  }

  @override
  String get notificationDelete => '删除通知';

  @override
  String get notificationDeleted => '通知已删除';

  @override
  String get notificationsClearAll => '清除全部';

  @override
  String get notificationsClearAllTitle => '清除全部通知？';

  @override
  String get notificationsClearAllMessage =>
      '你的列表中的所有通知都将被移除。审核通知仍会保留在“账号状态”页面。';

  @override
  String get apiErrorItineraryLocked =>
      'Someone else is editing this itinerary right now.';

  @override
  String get apiErrorEditLockRequired => 'Start editing before saving changes.';

  @override
  String get apiErrorEditLockLost =>
      'Your editing session was taken over. Your changes were not saved.';

  @override
  String get apiErrorEditorCannotView =>
      'This person can\'t see this itinerary, so they can\'t edit it.';

  @override
  String get apiErrorEditorExists =>
      'This person can already edit this itinerary.';

  @override
  String get apiErrorEditorNotFound =>
      'This person is not an editor of this itinerary.';

  @override
  String get apiErrorEditorIsOwner => 'You already have full edit rights.';

  @override
  String get editorsTitle => 'Who can edit';

  @override
  String get editorsSubtitle =>
      'Editors can change the description, stops and notes. Only you can delete the trip, change who can see it, or manage this list.';

  @override
  String get editorsEmpty => 'Nobody else can edit this trip yet.';

  @override
  String get editorsAdd => 'Add an editor';

  @override
  String get editorsSearchHint => 'Search by username';

  @override
  String get editorsRemoveTitle => 'Remove editor?';

  @override
  String editorsRemoveMessage(Object name) {
    return '$name will no longer be able to change this trip. Anything they already added stays.';
  }

  @override
  String editorsRemoved(Object name) {
    return '$name can no longer edit';
  }

  @override
  String get editorsGrantViewTitle => 'Give them access too?';

  @override
  String editorsGrantViewMessage(Object name) {
    return '$name can\'t see this trip yet. Add them to the people who can view it, so they can edit it.';
  }

  @override
  String get editorsGrantViewConfirm => 'Add and give access';

  @override
  String editorsChangeVisibilityMessage(Object name) {
    return '$name can\'t see this trip. Change who can see it first, then add them as an editor.';
  }

  @override
  String get editorsOpenVisibility => 'Change visibility';

  @override
  String get editorsLeaveRowTitle => '你是此行程的编辑者';

  @override
  String get editorsLeaveRowLabel => '将我移出编辑者';

  @override
  String get editorsLeaveTitle => '将我移出编辑者？';

  @override
  String get editorsLeaveMessage =>
      '之后你将无法再修改此行程。你已添加的内容会保留，你仍然可以查看它。只有所有者才能再次将你设为编辑者。';

  @override
  String get editorsLeaveConfirm => '移出';

  @override
  String get editorsLeft => '你已不再是此行程的编辑者';

  @override
  String editLockSomeoneEditing(Object name) {
    return '$name is editing';
  }

  @override
  String editLockSomeoneEditingIdle(Object name) {
    return '$name is editing · away';
  }

  @override
  String editLockAvailableIn(Object time) {
    return 'You can take over in $time';
  }

  @override
  String get editLockAvailableNow => 'You can take over now';

  @override
  String get editLockTakeOver => 'Take over';

  @override
  String get editLockYouElsewhere => 'You\'re editing this on another device';

  @override
  String get editLockMoveHere => 'Continue here';

  @override
  String get editLockMoveHereMessage =>
      'Your other device will not be able to save. Anything unsaved there stays on that device.';

  @override
  String get editLockLostTitle => 'Your editing session was taken over';

  @override
  String editLockLostMessage(Object name) {
    return '$name is editing now, so this change wasn\'t saved. Your text is still here — copy anything you need, or try to take the session back.';
  }

  @override
  String get editLockLostMessageUnknown =>
      'Somebody else is editing now, so this change wasn\'t saved. Your text is still here — copy anything you need, or try to take the session back.';

  @override
  String get editLockReclaim => 'Try to take it back';

  @override
  String get editLockReclaimed => 'You\'re editing again';

  @override
  String get editLockCopyText => 'Copy my text';

  @override
  String get editLockCopied => 'Copied';

  @override
  String get editLockOwnerCanReclaim =>
      'You own this trip — you can take over at any time.';
}
