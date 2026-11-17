# Options+ 主应用：供 sofo 使用的界面研究

核对日期：2026-11-17。静态来源是未随仓库发布的本地 `optionsplus-main` 提取产物，版本为 Logi Options+ **2.9.1013853**。设备详情另用本机同版本 Options+ 和正在运行的 sofo 对照。

## 来源与边界

- `original/identity.json` 记录原 ASAR SHA-256 为 `c7f799789b211be19d51742403abf83587fb113cb7e53eece90e1f6e72c86601`。
- `analysis/deep-verification.json` 记录 581 个原始文件、50 个 agent 打包资源的校验无哈希差异；生成代码语法检查通过，但语义等价测试与运行观察均为 false。本次没有独立重跑全量校验。
- 原归档 inventory Evidence：`ev_14e40f9818dcdd8048442d526c1330e89089241b866584964911a5e7b258b932`，保存在 `evidence/rea-evidence.json`。具体界面结论来自下列派生代码直接阅读，不将 inventory Evidence 当作行为验证。
- 组件保留编译变量名，依赖父闭包、Webpack 与 Redux；不是可直接编译的原始 React/TypeScript 工程。
- 安装器规范仅覆盖安装流程。主应用样式以提取的 CSS、组件和实际画面为依据；sofo 当前界面见[设备界面](device-interface.md)。

## 已确认的静态实现

| 项目 | 直接观察 | 来源，相对于 optionsplus-main |
| --- | --- | --- |
| 首页结构 | HOME 分支关联设备列表组件；顶部 header，下面居中设备列表，点击设备设置 activeDevice 并进入设备或引导流程。 | `screens/HOME.md`；`components/app.min.js/44707/_0x3ded3e.js:328` |
| 顶部布局 | header 高 18.5vh，上限 144px；左区宽 33%、左边距 52px；右区宽 60%、右边距 32px。设备区为 flex 居中。 | `readable/app.min.css:9056`；`:34205` |
| 右侧入口 | 添加设备、条件性配置管理入口及功能图标组。图标组按 feature flag / 设备能力决定可用入口；不同图标进入页面或打开浮层，不能统一理解为下拉菜单。 | `components/app.min.js/44707/_0x665abd.js`；`_0x922cad.js` |
| 浮层状态 | header 保存 openedHeaderIconPopup，功能组件保存 tabName；点击遮罩有关闭逻辑。 | `_0x665abd.js:10`；`_0x922cad.js:406` |
| 设备展示 | 首页用 `<img>`、资源 src 和 CSS 投影，不是实时 3D。设备图限制高度，hover / 键盘 focus 上移 12px，过渡约 200ms。 | `_0x552842.js:300`；`readable/app.min.css:6300` |
| 状态与禁用 | 区分设备连接、资源就绪、更新、受阻等状态；有 opacity-40 样式，blocked 设备禁用。不能简化为所有断连状态都完全不能点击。 | `_0x552842.js:28`、`:248`；`_0x3ded3e.js:80` |
| 颜色 | 主色 #814EFA；hover #673EC8；active-hover #6039B2；header hover #F9F6FF，边框 #E6DCFE；hotspot hover #F2EDFE。 | `analysis/css-variables.csv`，原 CSS `:48122` |
| 动作与物理键 | assignment-widget 区分物理键名、动作名称/描述、图标和辅助说明；激活时可显示编辑、恢复默认、禁用。再次选择当前槽位可清除激活态。 | `_0x447b5e.js:123`、`:192` |
| 拖放配置 | assignment 组件有拖动动作、有效目标、等待接收、放置焦点和成功状态的渲染分支。真实设备可用性未运行验证。 | `_0x447b5e.js:35`、`:75` |
| 动作配置数据 | agent 包内包含 macOS 默认槽位、动作标签、推荐、App 相关配置与预定义宏。表结构适合研究动作可用性过滤，不等于适配 Siri Remote。 | `agent-resources/data/defaults/defaults_slot_osx.json`；`data/rap/available_card_tags_slot.json`；`data/macros/` |

## 对 sofo 的建议，属于产品适配

1. 保持 sofo 品牌和实时 3D；借鉴产品居中与顶部功能分组，不按图片的宽高参数机械缩小细长遥控器。
2. 图标 hover 用极浅紫底和明确 focus 环；有真实待处理内容时才显示提示点。
3. 通过模型上的短标签标明实体键，在动作侧栏中显示当前动作，提供搜索、可折叠分组和动作参数。
4. 场景沿用全局映射的动作配置能力，按当前 App 区分映射范围。
5. 保持 sofo 的绿色连接光晕与断连灰显规则。

## 设备详情页：实机对照基线

参考窗口为 Options+ 的 **MX Anywhere 3S → 按钮**；对应窗口为 sofo 的 **A2540 → 按钮**。两种状态均有实机截图；未验证 Options+ 的实际搜索结果或保存动作。

| 对照项 | Options+ | sofo 当前 |
| --- | --- | --- |
| 页面骨架 | 左上返回与设备名，右上全局设置与添加应用，左侧功能入口，左下电量和蓝牙。 | 浏览时保留左侧功能与左下状态，3D 模型轻摆并有呼吸光。选中按键后侧栏和电量一起滑出，相机推近按键区域。 |
| 按键入口 | 默认显示白色热点圆环和浅底标签；选中后是 2 px 紫色圆环、30% 紫色填充、4 px 圆角紫底白字标签，无连线。 | 浏览时直接点模型上的实体键。编辑态沿当前实体键描边并显示紫底标签；点其他实体键即可切换。 |
| 编辑态 | 「动作」侧栏贴右满高，占窗口约三分之一，灰色标题、通栏搜索、圆点动作行和可折叠分组。 | 采用同样的侧栏结构，在标题栏选择单击、双击、长按。再次点同一按键或点返回可收起侧栏。 |

后续每轮调整详情页，都用两款运行中的应用核对相同状态：先看未选中时的页面布局和按键入口，再选中一枚按键检查编辑层级，最后确认退出后能回到浏览态。将参考应用里实际观察到的行为与 sofo 的设计选择分开记录。

鼠标选中样式对应原版 `readable/app.min.css:3025`、`:3200`、`:3410`、`:5001` 及主题色变量 `:48122`、`:48405`。
