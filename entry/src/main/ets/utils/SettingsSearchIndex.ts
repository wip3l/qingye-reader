/**
 * “我的”页设置搜索的索引与匹配。
 *
 * 每条记录对应设置页里的一行：标题须与页面里的标题字面一致（跳转后靠它找到那一行并高亮），
 * 说明用于展示，别名收用户自己的叫法。新增设置行时要在这里登记，
 * scripts/settings-search-index-check.mjs 会扫描登记过的页面，漏登记或标题对不上都会报错。
 * 纯 TS、不依赖 ArkUI，Node 回归脚本可以直接加载。
 */

export interface SettingsSearchPage {
  /** 页面键，回归脚本按它找源码文件。 */
  key: string;
  /** 显示在结果里的位置，如“阅读与收听 › 小说”。 */
  path: string;
  url: string;
  params?: Record<string, string>;
  /** 只有开启在线阅读（网页解析）后才能进入。 */
  requiresWebParse?: boolean;
}

export interface SettingsSearchEntry {
  id: number;
  page: SettingsSearchPage;
  section: string;
  title: string;
  description: string;
  aliases: string[];
  /** 跳转后要高亮的设置行标题；空串表示只打开页面（入口行、面板里的滑杆）。 */
  focus: string;
  requiresWebParse: boolean;
}

const MINE: SettingsSearchPage = { key: 'Mine', path: '我的', url: '' };
const READ: SettingsSearchPage = { key: 'Settings', path: '阅读与收听', url: 'pages/Settings' };
const NOVEL: SettingsSearchPage = { key: 'Settings', path: '阅读与收听 › 小说', url: 'pages/Settings',
  params: { section: 'novel' } };
const NOVEL_TYPO: SettingsSearchPage = { key: 'Settings', path: '阅读与收听 › 小说 › 排版', url: 'pages/Settings',
  params: { section: 'novel', group: '0' } };
const NOVEL_INFO: SettingsSearchPage = { key: 'Settings', path: '阅读与收听 › 小说 › 页眉页脚', url: 'pages/Settings',
  params: { section: 'novel', group: '1' } };
const NOVEL_BG: SettingsSearchPage = { key: 'Settings', path: '阅读与收听 › 小说 › 阅读背景', url: 'pages/Settings',
  params: { section: 'novel', group: '3' } };
const COMIC: SettingsSearchPage = { key: 'ComicSettings', path: '阅读与收听 › 漫画', url: 'pages/ComicSettings' };
const PDF: SettingsSearchPage = { key: 'PdfSettings', path: '阅读与收听 › PDF', url: 'pages/PdfSettings' };
const AUDIO: SettingsSearchPage = { key: 'AudioBookSettings', path: '阅读与收听 › 有声书', url: 'pages/AudioBookSettings' };
const TTS: SettingsSearchPage = { key: 'TtsSettings', path: '阅读与收听 › 朗读', url: 'pages/TtsSettings' };
const SHELF: SettingsSearchPage = { key: 'BookshelfSettings', path: '书架设置', url: 'pages/BookshelfSettings' };
const COVER: SettingsSearchPage = { key: 'CoverSettings', path: '书架设置 › 封面设置', url: 'pages/CoverSettings' };
const LOOK: SettingsSearchPage = { key: 'AppearanceSettings', path: '外观', url: 'pages/AppearanceSettings' };
const OTHER: SettingsSearchPage = { key: 'OtherSettings', path: '其他设置', url: 'pages/OtherSettings' };
const LAB: SettingsSearchPage = { key: 'LabSettings', path: '实验室', url: 'pages/LabSettings' };
const WEB: SettingsSearchPage = { key: 'WebParseSettings', path: '在线阅读', url: 'pages/WebParseSettings' };
const SEARCH: SettingsSearchPage = { key: 'SearchExploreSettings', path: '在线阅读 › 搜索与发现',
  url: 'pages/SearchExploreSettings', requiresWebParse: true };
const SYNC: SettingsSearchPage = { key: 'DataSync', path: '数据同步', url: 'pages/DataSync' };

/** 小说排版面板里滑杆的标题，与 ReaderTypographyField.LABELS 一致；滑杆不是设置行，只打开面板。 */
const TYPOGRAPHY_SLIDERS: string[][] = [
  ['字号', '正文文字大小', '字体大小 文字大小 字太小 字太大'],
  ['字体粗细', '正文笔画粗细', '字重 加粗'],
  ['字距', '字与字之间的距离', '字间距'],
  ['行距', '行与行之间的距离', '行高 行间距'],
  ['段落间距', '段落之间的距离', '段距 段间距'],
  ['左边距', '正文离屏幕左边的距离', '页边距 边距'],
  ['右边距', '正文离屏幕右边的距离', '页边距 边距'],
  ['上边距', '正文离页眉的距离', '页边距 边距'],
  ['下边距', '正文离页脚的距离', '页边距 边距'],
  ['气泡大小', '段落末尾段评气泡的大小', '段评气泡大小']
];

type Row = [SettingsSearchPage, string, string, string, string, boolean?];

/** [页面, 分组, 标题, 说明, 别名（空格分隔）, 需在线阅读]。只打开页面的入口登记在 NAVS。 */
const ROWS: Row[] = [
  [READ, '收听', '与其他应用同时播放', '朗读和有声书不再被游戏、视频的声音打断，开始播放时也不暂停其他应用', '混音 后台播放 游戏'],
  [READ, '阅读通用', '滚动阅读时点击翻屏', '按点击区域动作上下翻一屏；关闭时点击正文只呼出菜单', ''],
  [READ, '阅读通用', '屏幕方向', '阅读时的屏幕方向', '横屏 竖屏 旋转 自动旋转'],
  [READ, '阅读通用', '亮屏时间设置', '无操作达到所选分钟数后恢复系统息屏，0 为常亮', '息屏 熄屏 常亮 屏幕超时 锁屏'],
  [READ, '阅读通用', '双翻页', '横屏、折叠屏展开等宽屏下并排显示两页', '双页 折叠屏 横屏 平板'],
  [READ, '阅读通用', '音量键翻页', '音量上/下键翻到上一页/下一页，条漫为翻一屏', '音量 按键'],
  [READ, '阅读通用', '智控键翻页', '智控键上滑/下滑翻到上一页/下一页，条漫为翻一屏', '指纹键 侧键'],
  [READ, '阅读通用', '手表翻页', '在手表上打开开源轻页，点屏幕或转表冠翻页，条漫为翻一屏', '手表 智能手表 遥控 表冠 WATCH'],
  [READ, '阅读通用', '翻页震感', '点击、滑动或按键翻页时轻震一下，翻到新章节时稍重', '震动 振动 触感 马达'],
  [READ, '阅读通用', '隐藏底部小白条', '阅读正文时收起底部导航条，呼出菜单时恢复', '导航条 手势条 横条'],
  [READ, '阅读通用', '点击区域动作', '点击正文不同区域时做什么', '点击翻页 九宫格 左手 右手'],
  [READ, '提示', 'AI处理标识', '显示 EPUB 插图、漫画和 PDF 的 AI 处理及超分提示', ''],
  [READ, '缓存与提示', '预缓存设置', '提前缓存后续章节，包含漫画图片', '预加载 缓存 下载章节', true],
  [READ, '缓存与提示', '下一章节数', '开启预缓存后出现；小说、漫画共用的预缓存章节数', '预加载 缓存', true],

  [NOVEL, '替换净化', '替换净化', '正文与章节标题的替换规则', '净化 广告 屏蔽词 水印 替换'],
  [NOVEL, '替换净化', 'TXT 目录规则', '本地 TXT 怎样识别章节标题', '章节 分章 目录'],
  [NOVEL, '操作', '长按选中文字', '关闭后长按正文不选中文字，也不弹出操作选项', '复制 选择 划线'],
  [NOVEL, '段评', '段评气泡', '段落末尾的评论数气泡；关闭后不显示', '评论 段评', true],
  [NOVEL, '段评', '热评卡片', '段评热评显示在段落下方', '热评 评论', true],
  [NOVEL, '段评', '本章说', '章末的本章评论入口', '章评 评论', true],
  [NOVEL, '段评', '面板高度', '点评论气泡打开的评论面板有多高，可选铺满', '评论面板 段评面板 弹窗高度 半屏', true],
  [NOVEL, '翻页', '翻页方式', '上下滑动、横向滑动或滚动阅读', '滚动阅读 上下翻页 左右翻页'],
  [NOVEL, '翻页', '翻页动画', '翻页时的切换效果', '仿真 覆盖 平移 卷页 推页'],
  [NOVEL, '翻页', '横竖屏分开设置', '打开后横屏和折叠屏展开时单独选翻页动画，翻页方式仍然共用', '横屏翻页动画 竖屏 双页 仿真 折叠屏 展开'],
  [NOVEL, '翻页', '横屏/展开翻页动画', '打开“横竖屏分开设置”后出现；横屏或折叠屏展开时的切换效果', '横屏 双页 仿真 折叠屏 展开'],
  [NOVEL, '翻页', '快速添加书签', '下拉正文添加或删除当前页书签', '书签 下拉'],
  [NOVEL, '翻页', '眼动翻页（beta）', '向上看即翻页；摄像头图像仅在本机处理', '眼控 抬眼 摄像头 免手'],
  [NOVEL, '翻页', '新版识别模型（beta）', '开启眼动翻页后出现；识别更稳，不怕暗光和眼镜', '眼动'],
  [NOVEL, '排版与主题', '排版跟随主题', '切换主题时一起换成主题的排版', ''],

  [NOVEL_TYPO, '排版', '段首缩进', '正文每段首行的缩进字符数', '缩进 空两格'],
  [NOVEL_TYPO, '排版', '正文对齐方式', '正文段落的水平对齐', '对齐 两端对齐'],
  [NOVEL_TYPO, '排版', '正文扩展至状态栏', '隐藏状态栏，正文延伸到屏幕顶部', '全屏 刘海 隐藏状态栏'],

  [COMIC, '阅读方式', '默认阅读方式', '没单独设置过的漫画使用这里的方式', '条漫 翻页 日漫 从右往左'],
  [COMIC, '阅读方式', '横屏/展开默认阅读方式', '打开“横竖屏分开设置”后出现；横屏或折叠屏展开时用的方式', '横屏 折叠屏 展开 双页 同竖屏'],
  [COMIC, '阅读方式', '横竖屏分开设置', '横屏或折叠屏展开时单独选阅读方式和翻页动画', '横屏 竖屏 折叠屏 展开 双页 仿真 翻页动画'],
  [COMIC, '阅读方式', '点击翻页', '点击屏幕两侧翻页（条漫为翻一屏），中间呼出菜单', ''],
  [COMIC, '画面', '背景', '图片四周和页间距的颜色', '背景色 黑色 白色'],
  [COMIC, '画面', '页间距', '条漫图片之间的间隔', '间隔 缝隙'],
  [COMIC, '画面', '图片缩放', '条漫按宽度铺满，或整张放进一屏', '适应宽度 适应屏幕'],
  [COMIC, '画面', '去白边', '裁掉图片四周的白边或黑边，画面更大', '裁边 黑边 白边'],
  [COMIC, '画面', '双击缩放', '双击放大到 2 倍，再双击还原', '放大'],
  [COMIC, '画面', '信息条', '在右下角显示话名、页码、时间与电量', '页码 电量'],
  [COMIC, 'AI 功能', 'AI超分', '借助AI把低清图片放大变清晰', '高清 清晰 模糊 超分'],
  [COMIC, 'AI 功能', 'AI着色', '为黑白漫画着色', '上色 彩色 黑白 着色'],
  [COMIC, 'AI 功能', 'AI翻译', '借助AI识别并转换漫画对白', '翻译 日文 繁体 生肉'],

  [PDF, '阅读方式', '连续滚动', '上下滑动，连续阅读文档', ''],
  [PDF, '阅读方式', '适配整页', '关闭后按页面宽度显示', '宽度 缩放'],
  [PDF, '画面', '夜间页面', '应用夜间模式时 PDF 页面的显示', '反色 深色 夜间'],
  [PDF, '画面', '页码角标', '阅读时右下角显示目录标题、页码、时间与电量', '页码'],
  [PDF, 'AI超分', 'AI超分', '增强符合条件的低清扫描页，文字页保持原生显示', '高清 扫描 超分'],

  [AUDIO, '播放', '打开时自动播放', '关闭后打开有声书只停在上次听到的位置，点播放才开始', '自动播放'],
  [AUDIO, '离线下载', '边听边下', '提前下载正在听的书后面几章；听完自动删除', '缓存 预下载'],
  [AUDIO, '离线下载', '手动下载仅用 Wi-Fi', '手动下载在移动网络下等待 Wi-Fi', '流量 wifi 移动网络'],
  [AUDIO, '离线下载', '离线音频上限', '超出后先删最早的边听边下章节', '空间 存储'],
  [AUDIO, 'AI 字幕', '识别模型', '听书字幕的本地识别模型，下载或删除', '字幕 语音识别 模型'],
  [AUDIO, 'AI 字幕', '提前识别下一章', '当前章识别完后接着处理已下载的下一章开头', '字幕 预识别'],
  [AUDIO, 'AI 字幕', '导入模型文件', '网络不好时选择下载好的字幕模型文件', '字幕 导入'],

  [TTS, '', '朗读音色', '当前朗读使用的声音', '声音 发音人 语音'],
  [TTS, '', '音色管理', '离线音色 / 系统音色 / 云端音色 / 自定义音色', '离线朗读 声音'],
  [TTS, '', '多角色朗读', '识别人物与旁白，用离线音色和自定义音色分别朗读', '多音色 角色配音 旁白 对白 音色方案 人物'],
  [TTS, '', 'MiMo 朗读', '在线大模型朗读', '小米 在线朗读 大模型'],
  [TTS, '', '手动翻页后，朗读', '立即跟随 / 停留 3 秒后 / 不跟随', '翻页跟随 从本页听 回到朗读处 朗读不跟随'],

  [SHELF, '布局与分类', '书架布局', '列表疏密、封面平铺，或带问候与阅读小记的陪伴首页', '列表 平铺 宫格 陪伴'],
  [SHELF, '布局与分类', '书架背景', '默认跟随主题；可单独上传一张，铺在顶部或全屏', '背景图 壁纸 全屏背景 自定义背景 淡化 模糊'],
  [SHELF, '布局与分类', '上次阅读置顶', '最近阅读的书排在最前的样式', '最近阅读 置顶'],
  [SHELF, '布局与分类', '置顶数量', '按最近阅读排序，最多展示所选数量', ''],
  [SHELF, '布局与分类', '问候语', '书架左上角的两行文案，也可在书架上长按修改', '问候 文案'],
  [SHELF, '布局与分类', '上次阅读扉页设置', '最近阅读书籍封面右侧的展示内容', '扉页'],
  [SHELF, '布局与分类', '显示书籍边框', '封面的描边、投影与底色', '描边'],
  [SHELF, '布局与分类', '错落摆放', '书本高矮不一、偶有斜靠', '整齐'],
  [SHELF, '布局与分类', '封面阴影', '书本落在书架上的投影', '投影'],
  [SHELF, '布局与分类', '阅读小记', '在继续阅读下方显示今日时长、近 7 天和连续阅读天数', '时长 连续阅读'],
  [SHELF, '布局与分类', '书籍分类', '书架顶部按小说、漫画、有声书等类型分页', '分类 类型'],
  [SHELF, '布局与分类', '显示全部分类', '分类栏第一项为“全部”', ''],
  [SHELF, '布局与分类', '书籍打开动画', '点击书籍时播放封面展开动画', '动画 翻开'],
  [SHELF, '进入书架', '沉浸书架', '进入书架时隐藏顶部按钮和底栏，向下滑动时出现', '隐藏底栏 全屏'],
  [SHELF, '进入书架', '顶部按钮', '沉浸书架时顶部按钮下拉显示，或只留菜单按钮', '菜单按钮'],
  [SHELF, '进入书架', '记住打开分组', '重新打开应用时回到上次所在的文件夹和分类', '文件夹 分组'],
  [SHELF, '加入书架', '新书默认分组', '在搜索、发现和书籍详情页加入书架时放进哪个分组', '分组 文件夹 加入书架 默认'],
  [SHELF, '卡片信息', '书籍标签', '在书架卡片上显示标签', ''],
  [SHELF, '卡片信息', '书籍简介', '在书架卡片上显示简介', ''],
  [SHELF, '卡片信息', '显示全部简介', '简介不截断，完整显示', ''],
  [SHELF, '卡片信息', '使用阅读进度条', '在卡片底部显示阅读百分比和阅读信息', '进度'],
  [SHELF, '卡片信息', '显示最后阅读时间', '在进度条旁显示上次阅读时间', ''],
  [SHELF, '卡片信息', '显示最后阅读章节', '在进度条旁显示上次阅读章节', ''],
  [SHELF, '封面', '封面设置', '封面来源与先后顺序、图集、多张封面的显示方式、封面标识', '封面图集 主题封面 换封面'],
  [COVER, '封面来源', '单独设置的封面', '长按书籍设置，始终最优先；可在这里逐本恢复默认', '自定义封面 恢复默认封面 网络封面'],
  [COVER, '封面来源', '统一封面', '用主题封面或图集替换书籍自带的封面', '主题封面 封面图集 忽略原始封面 替换封面'],
  [COVER, '封面来源', '应用到', '统一封面用图集时，作用于全部书籍或指定书籍', '图集应用范围 指定书籍'],
  [COVER, '封面来源', '和自带封面一起轮播', '统一封面用图集时，书籍自带的封面也参与轮播', '轮播 混合'],
  [COVER, '封面来源', '没有封面时', '只给没有封面的书用主题封面或图集兜底', '空封面 无封面 兜底 仅忽略空封面 默认封面'],
  [COVER, '图集', '图集管理', '新建、导入图片、重命名、预览', '封面图集 导入封面'],
  [COVER, '图集', '浅色模式图集', '浅色模式下使用的封面图集', '浅色配色图集'],
  [COVER, '图集', '深色模式图集', '深色模式下使用的封面图集', '深色配色图集'],
  [COVER, '显示', '有多张封面时', '轮流显示、每小时随机换一张，或每本书固定一张', '封面模式 轮流 随机 固定封面'],
  [COVER, '显示', '深色模式调暗封面', '深色模式下降低封面亮度，夜里看书架不刺眼', '夜间 刺眼 暗'],
  [COVER, '显示', '调暗程度', '开启深色模式调暗封面后出现', '亮度'],
  [COVER, '显示', '封面标识', '配置四个角的类型、来源、更新、置顶和未读数', '角标 未读数 置顶'],
  [COVER, '应用范围', '搜索与发现也用这套封面', '搜索、发现和书籍详情沿用书架的封面来源', '搜索封面 使用书架封面'],
  [SHELF, '书籍更新', '自动获取更新', '打开应用时在后台检查连载书籍的新章节', '追更 连载 新章节 检查更新'],
  [SHELF, '隐私书架', '隐私书架', '双击书架顶部空白处进入，在隐私书架里双击返回', '隐藏 私密 加密 密码'],
  [SHELF, '隐私书架', '指纹或人脸解锁', '进入隐私书架时先用系统指纹或人脸验证', '指纹 人脸 密码'],

  [LOOK, '显示', '显示模式', '浅色、深色，或跟随系统自动切换', '夜间 暗黑 深色 黑暗模式 浅色 日间'],
  [LOOK, '显示', '字体设置', '全局字体、自定义字体', '应用字体 全局字体'],
  [LOOK, '显示', '图标设置', '更换桌面图标', '桌面图标 图标'],
  [LOOK, '显示', '显示设置项搜索框', '在“我的”页顶部显示搜索框', '搜索栏 搜索框 隐藏搜索'],
  [LOOK, '材质与背景', '沉浸光感', '菜单、弹窗和面板的半透明材质', '毛玻璃 透明 光感'],
  [LOOK, '材质与背景', '沉浸光感跟随主题色', '半透明底色带上一点主题强调色', '主题色'],
  [LOOK, '材质与背景', '主题背景图', '主题自带背景图时，铺在书架、发现、搜索和我的页顶部', '背景图'],
  [LOOK, '材质与背景', '顶部磨砂', '页面顶栏背后的内容先模糊再透出', '模糊 磨砂'],
  [LOOK, '材质与背景', '播放动图', '书架封面、主题封面和背景图是动图时播放动画', 'gif 动图'],
  [LOOK, '底栏', '底栏样式', '悬浮或平铺', '悬浮 平铺 导航栏'],
  [LOOK, '底栏', '自适应宽度', '悬浮底栏的宽度随项目数变化', ''],
  [LOOK, '底栏', '底栏磨砂', '透出底栏的内容先模糊', '模糊'],
  [LOOK, '底栏', '滑动收起', '列表上滑时底栏自动收起，回到上方再出现', '隐藏底栏'],
  [LOOK, '底栏', '更多底栏项目', '第四个页签：听或足迹', '第四页签 听 足迹'],
  [LOOK, '底栏', '足迹页内容', '选择足迹页显示哪些内容、顺序和数量', '足迹'],

  [OTHER, '数据', '数据导入', '从备份文件导入书架、进度、本地图书和设置', '恢复 备份 迁移 换手机'],
  [OTHER, '数据', '数据导出', '将书架、进度、本地图书和设置导出为备份', '备份 迁移 换手机'],
  [OTHER, '缓存', '小说自动缓存', '阅读时自动缓存的小说章节', '预加载 清理'],
  [OTHER, '缓存', '漫画自动缓存', '阅读时自动缓存的漫画图片', '预加载 清理'],
  [OTHER, '缓存', '离线内容', '查看并清理已缓存的章节和图片', '清理 清除缓存 存储 空间 占用'],
  [OTHER, '缓存', '有声书离线音频', '查看并清理已下载的音频', '清理 存储 空间'],
  [OTHER, '交互', '智感握姿', '根据左右手握持，自动调整导航栏和部分操作按钮的位置', '单手 左手 右手 握持'],

  [LAB, '显示', '墨水屏灰阶', '整个应用（含图片和弹窗）转为灰阶，日间与夜间都生效', '灰阶 黑白 灰度 墨水屏 电纸书 护眼'],
  [LAB, '兼容与诊断', '图片下载并发', '默认 4 张；图片站限流或加载不稳时调回 4 张', '并发 图片加载慢'],
  [LAB, '兼容与诊断', 'HTTP/1.1 兼容模式', '网页连接反复出现传输错误时可尝试开启', '网络错误'],
  [LAB, '浏览器看书', '浏览器看书', '同一局域网内的设备可用浏览器访问本机书架', '电脑 网页 局域网 传书'],

  [WEB, '', '网页解析', '用你自己添加的书源打开网页，并排成适合阅读的版式', '在线阅读 书源 联网'],
  [WEB, '', '导入安卓阅读备份', '导入安卓版阅读导出的 ZIP 备份', '安卓 迁移 legado'],

  [SEARCH, '结果展示', '显示结果封面', '在搜索和发现结果中显示封面', ''],
  [SEARCH, '结果展示', '使用书架封面', '搜索、发现及书籍详情沿用书架的封面来源，在封面设置里开关', ''],
  [SEARCH, '结果展示', '封面模糊背景', '在搜索和发现结果列表中显示封面模糊背景', ''],
  [SEARCH, '结果展示', '显示结果标签', '在搜索和发现结果中显示标签', ''],
  [SEARCH, '书架提示', '返回提示加入书架', '从搜索或发现试读后，返回时询问是否加入书架', ''],
  [SEARCH, '搜索设置', '精准搜索', '只保留书名与关键词完全一致的结果', '完全匹配'],
  [SEARCH, '搜索设置', '匹配作者', '精准搜索时，关键词也可匹配作者', ''],
  [SEARCH, '搜索设置', '简繁同搜', '按书源的简繁用字自动转换关键词', '繁体'],
  [SEARCH, '搜索设置', '显示搜索进度', '搜索时显示已搜书源数和结果数', ''],
  [SEARCH, '搜索设置', '聚合同名结果', '同名书合并为一条，点开查看各书源结果', '合并 去重'],
  [SEARCH, '搜索设置', '搜索并发数', '同时请求的书源数，搜书、换源、找封面和搜索校验共用', '并发 搜索慢'],

  [SYNC, '同步设置', '云同步', '登录后在多台设备间同步', '多设备 云端 备份'],
  [SYNC, '同步设置', '自动同步', '数据变更后自动同步，失败后稍后重试', ''],
  [SYNC, '同步设置', '仅 Wi-Fi 自动同步', '移动网络下仍可手动同步', '流量 wifi'],
  [SYNC, '同步设置', '回到前台时同步', '打开或切回应用时检查云端变更', ''],
  [SYNC, '同步内容', '阅读数据', '书架、分组、进度、书签和阅读统计', '进度同步'],
  [SYNC, '同步内容', '阅读偏好', '字体规则、替换规则、主题', ''],
  [SYNC, '同步内容', '应用偏好', '显示模式、书架布局、搜索显示', '']
];

/** 只打开页面的入口：[位置, 标题, 说明, 别名, 路由, 路由参数, 需在线阅读]。 */
type Nav = [string, string, string, string, string, Record<string, string> | undefined, boolean];

const NAVS: Nav[] = [
  ['我的', '数据同步', '多设备同步书架、进度和设置', '云端 备份 多设备', 'pages/DataSync', undefined, false],
  ['我的', '阅读统计', '按日、周、月查看阅读时长和书籍排行', '时长 统计 排行', 'pages/ReadingStats', undefined, false],
  ['我的', '我的标记', '打分、状态、标签与短评', '评分 短评 想读 弃读', 'pages/BookMarkList', undefined, false],
  ['我的', '票夹', '读过、在读、弃读的书各一张票，可存图分享', '票根 藏书卡 电影票 读完 出票', 'pages/TicketAlbum', undefined, false],
  ['我的', '书籍导入', '本地文件、WebDAV、OPDS、局域网传书', '导入 本地 txt epub 传书', 'pages/BookImport', undefined, false],
  ['我的', '在线阅读', '网页解析开关', '网页解析 书源 联网', 'pages/WebParseSettings', undefined, false],
  ['我的', '书源管理', '导入、分组、校验书源', '书源 源', 'pages/BookSource', undefined, true],
  ['我的', '阅读与收听', '小说、漫画、PDF、有声书、朗读', '', 'pages/Settings', undefined, false],
  ['我的', '书架设置', '布局、卡片信息、封面、隐私书架', '', 'pages/BookshelfSettings', undefined, false],
  ['我的', '主题', '主题库与自定义主题', '皮肤 配色 主题包 主题封面 主题边框 书框', 'pages/ThemeSettings', undefined, false],
  ['我的', '外观', '显示模式、材质、底栏', '', 'pages/AppearanceSettings', undefined, false],
  ['我的', '其他设置', '数据导入导出、缓存、交互', '', 'pages/OtherSettings', undefined, false],
  ['我的', '实验室', '墨水屏灰阶、兼容与诊断、浏览器看书', '', 'pages/LabSettings', undefined, false],
  ['我的', '帮助', '使用说明与常见问题', '说明 教程', 'pages/Help', undefined, false],
  ['我的', '关于', '版本与开源许可', '版本 检查更新', 'pages/About', undefined, false],
  ['阅读与收听', '小说', '排版、背景、翻页', '', 'pages/Settings', { section: 'novel' }, false],
  ['阅读与收听', '漫画', '阅读方式、画面、AI 超分/着色/翻译', '', 'pages/ComicSettings', undefined, false],
  ['阅读与收听', 'PDF', '连续滚动、单双页、页面适配、AI 超分', '', 'pages/PdfSettings', undefined, false],
  ['阅读与收听', '有声书', '自动播放、边听边下、离线下载、AI 字幕', '听书', 'pages/AudioBookSettings', undefined, false],
  ['阅读与收听', '朗读', '音色、倍速、MiMo 朗读、在线朗读字数', '听书 tts 语速 倍速', 'pages/TtsSettings', undefined, false],
  ['阅读与收听 › 小说', '排版', '字号、间距、边距、气泡大小', '版式 间距 边距', 'pages/Settings',
    { section: 'novel', group: '0' }, false],
  ['阅读与收听 › 小说', '页眉页脚', '内容、颜色、位置与进度条', '页码 时间 电量 标题栏', 'pages/Settings',
    { section: 'novel', group: '1' }, false],
  ['阅读与收听 › 小说', '阅读字体', '正文、标题、正则样式', '字体 楷体 宋体 自定义字体', 'pages/Settings',
    { section: 'novel', group: '2' }, false],
  ['阅读与收听 › 小说', '阅读背景', '主题、背景图片、文字颜色', '护眼 背景色 壁纸 文字颜色', 'pages/Settings',
    { section: 'novel', group: '3' }, false],
  ['在线阅读', '搜索与发现', '结果展示、搜索设置', '', 'pages/SearchExploreSettings', undefined, true]
];

function splitAliases(text: string): string[] {
  return text ? text.split(' ').filter((item: string) => item.length > 0) : [];
}

function buildEntries(): SettingsSearchEntry[] {
  const entries: SettingsSearchEntry[] = [];
  const push = (page: SettingsSearchPage, section: string, title: string, description: string, aliases: string,
    focus: string, requiresWebParse: boolean): void => {
    entries.push({ id: entries.length, page: page, section: section, title: title, description: description,
      aliases: splitAliases(aliases), focus: focus, requiresWebParse: requiresWebParse });
  };
  NAVS.forEach((nav: Nav) => {
    const page: SettingsSearchPage = { key: 'Mine', path: nav[0], url: nav[4], params: nav[5],
      requiresWebParse: nav[6] };
    push(page, '', nav[1], nav[2], nav[3], '', nav[6]);
  });
  TYPOGRAPHY_SLIDERS.forEach((item: string[]) => {
    push(NOVEL_TYPO, '排版', item[0], item[1], item[2], '', false);
  });
  ROWS.forEach((row: Row) => {
    push(row[0], row[1], row[2], row[3], row[4], row[2], row[0].requiresWebParse === true || row[5] === true);
  });
  // 页眉页脚、阅读背景面板里的项目不是设置行，搜到后打开对应面板。
  push(NOVEL_INFO, '页眉页脚', '页眉内容', '书名、章节名、时间等', '标题栏', '', false);
  push(NOVEL_INFO, '页眉页脚', '页脚内容', '页码、进度、时间、电量', '页码 时间 电量 进度', '', false);
  push(NOVEL_BG, '阅读背景', '背景图片', '用图片作为纸张背景', '壁纸 底图', '', false);
  push(NOVEL_BG, '阅读背景', '文字颜色', '正文文字颜色', '字体颜色', '', false);
  push(NOVEL_BG, '阅读背景', '图片显示', '背景图裁切铺满、完整显示、拉伸或平铺', '裁切 裁剪 取景 平铺 拉伸 完整显示 填充',
    '', false);
  return entries;
}

export const SETTINGS_SEARCH_ENTRIES: SettingsSearchEntry[] = buildEntries();
export const SETTINGS_SEARCH_MINE_PAGE: SettingsSearchPage = MINE;
/** 搜索层空白时的推荐词。 */
export const SETTINGS_SEARCH_HINTS: string[] = ['字号', '息屏', '音量键', '夜间', '缓存', '隐私书架', '翻页动画', '备份'];

/** 忽略大小写、全角字符和空白。 */
export function normalizeSettingsQuery(text: string): string {
  let out = '';
  for (const ch of text.toLowerCase()) {
    const code = ch.charCodeAt(0);
    if (code === 0x3000 || /\s/.test(ch)) continue;
    out += code >= 0xff01 && code <= 0xff5e ? String.fromCharCode(code - 0xfee0) : ch;
  }
  return out;
}

export function settingsQueryTokens(query: string): string[] {
  return query.trim().split(/\s+/).map((item: string) => normalizeSettingsQuery(item))
    .filter((item: string) => item.length > 0);
}

function tokenScore(entry: SettingsSearchEntry, token: string): number {
  const title = normalizeSettingsQuery(entry.title);
  if (title === token) return 100;
  if (title.startsWith(token)) return 80;
  if (title.includes(token)) return 62;
  for (const alias of entry.aliases) {
    const name = normalizeSettingsQuery(alias);
    if (name === token) return 56;
    if (name.includes(token) || (name.length >= 2 && token.includes(name))) return 46;
  }
  // 词正好是所在位置的一级（“漫画 超分”里的“漫画”）时算强命中，排在只有说明命中的入口之前；
  // 单搜“漫画”时标题完全一致的入口仍排第一。
  const places = entry.page.path.split(' › ').concat(entry.section ? [entry.section] : [])
    .map((item: string) => normalizeSettingsQuery(item));
  if (places.includes(token)) return 70;
  if (normalizeSettingsQuery(entry.description).includes(token)) return 22;
  if (places.some((item: string) => item.includes(token))) return 12;
  return 0;
}

/** 空格分开的词须全部命中；标题命中排在别名、说明之前，同分按登记顺序。 */
export function searchSettings(query: string, entries: SettingsSearchEntry[] = SETTINGS_SEARCH_ENTRIES,
  limit: number = 50): SettingsSearchEntry[] {
  const tokens = settingsQueryTokens(query);
  if (tokens.length === 0) return [];
  const scored: Array<[number, SettingsSearchEntry]> = [];
  for (const entry of entries) {
    let total = 0;
    let matched = true;
    for (const token of tokens) {
      const score = tokenScore(entry, token);
      if (score <= 0) {
        matched = false;
        break;
      }
      total += score;
    }
    if (matched) scored.push([total, entry]);
  }
  scored.sort((a: [number, SettingsSearchEntry], b: [number, SettingsSearchEntry]) => b[0] - a[0] || a[1].id - b[1].id);
  return scored.slice(0, limit).map((item: [number, SettingsSearchEntry]) => item[1]);
}

/** 把文本拆成命中前、命中词、命中后三段，用第一个能在原文里找到的词；找不到时整段放在前面。 */
export function settingsHighlightParts(text: string, query: string): string[] {
  const lower = text.toLowerCase();
  for (const raw of query.trim().split(/\s+/)) {
    const key = raw.trim().toLowerCase();
    if (!key) continue;
    const at = lower.indexOf(key);
    if (at >= 0) return [text.substring(0, at), text.substring(at, at + key.length), text.substring(at + key.length)];
  }
  return [text, '', ''];
}
