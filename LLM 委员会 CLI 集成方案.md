

# **基于 Claude Code 架构重构 LLM Council：从 Web 应用到原生终端代理的演进与实施报告**

## **1\. 摘要与架构愿景**

随着大语言模型（LLM）生态系统的日益成熟，开发者与 AI 的交互范式正经历从单一的 Web 聊天界面向深度集成开发环境（IDE）和命令行接口（CLI）的代理化工作流转变。原始的 llm-council 项目 1 通过构建一个本地 Web 应用程序，确立了多模型“民主化基准测试”的范式：即通过聚合 OpenAI、Google 和 Anthropic 等不同厂商的顶级模型，形成一个“理事会”来生成、审查并综合得出一个最优的回答。然而，这种基于 Web 的架构存在依赖管理复杂 2、上下文与本地代码库割裂 3 以及维护成本高昂 1 等固有局限性。

本报告旨在详尽阐述将 llm-council 的核心逻辑重构为 Claude Code 原生 Plugin（插件）的战略蓝图。这一重构不仅是代码的迁移，更是架构哲学的升级——利用 Claude Code 的 **Plugins \+ Skill \+ Sub-agents** 复合架构 4，将“理事会”的决策能力内化为开发者终端的一个原生技能。通过集成 OpenAI/Codex CLI (GPT-5.1) 7、Gemini CLI (Gemini 3 Pro Preview) 8 和 Claude Code CLI (Sonnet 4.5) 10 作为底层执行单元，本方案构建了一个去中心化、高容错且具备自我修正能力的代理编排系统。

报告将深入探讨如何利用 **技能（Skills）** 实现程序性知识的渐进式披露 5，利用 **子代理（Sub-agents）** 实现上下文隔离与角色专业化 12，并通过 **插件（Plugins）** 规范实现标准化的分发与治理 13。通过这种架构，开发者无需离开终端即可召唤“理事会”，在保持上下文连贯性的同时，获得多模型交叉验证的高质量输出。

---

## **2\. 传统 llm-council 范式的解构与局限性分析**

在着手重构之前，必须深入理解原始 llm-council 项目的运行逻辑及其在现代工程环境中的局限性。该项目虽然被原作者戏称为“99% 的氛围编码（Vibe Coding）” 1，但其核心的“三阶段共识机制”为多智能体协作提供了重要的理论基础。

### **2.1 三阶段共识机制的工程价值**

原始项目的核心价值在于其模拟人类委员会决策的流程 1，这一流程在重构中必须被完整保留并增强：

1. 第一阶段：独立意见征集（First Opinions）  
   在此阶段，用户查询被广播给所有成员模型。原始实现依赖于 OpenRouter API 将请求分发给不同的后端。在新的架构中，这一步骤演变为并行调用异构 CLI 工具的复杂工程。每个 CLI 工具（如 codex、gemini）不仅是 API 的封装，更是运行在本地环境中的独立代理，能够访问本地文件系统，从而提供比纯 Web API 更丰富的上下文感知能力 7。  
2. 第二阶段：同行评审（Peer Review）  
   这是提升输出质量的关键环节。系统将第一阶段生成的答案匿名化后，交叉发送给其他模型进行评审。研究表明，通过“LLM-as-a-Judge”的模式，模型在评估同类输出时能展现出比生成任务更强的辨别力 15。在 CLI 环境中，这要求架构具备强大的标准输出（stdout）捕获与数据清洗能力，将非结构化的终端输出转化为结构化的评审提示词（Prompt）。  
3. 第三阶段：主席综合（Chairman's Synthesis）  
   由指定的“主席”模型阅读所有原始回答和评审意见，生成最终裁决。这一步骤在 Web 应用中仅是一次 API 调用，但在 Claude Code 架构中，它完美契合了 子代理（Sub-agent） 的设计初衷——即通过独立的上下文窗口处理大量中间数据，避免污染主会话的上下文 12。

### **2.2 Web 架构向终端代理迁移的必要性**

原始架构在实际部署中面临诸多挑战，驱动了向 Claude Code Plugin 的迁移：

* **依赖地狱与环境碎片化**：用户在使用原始 Web 应用时，经常面临 Node.js、npm 或 Python 环境配置的困扰，尤其是在 Windows 平台上 2。Claude Code 通过统一的 Plugin 容器和 Docker 化的执行环境，能够有效屏蔽底层依赖差异 3。  
* **上下文断裂**：Web 应用运行在浏览器沙箱中，无法直接读取开发者正在编辑的代码文件或 Git 状态。而 Claude Code 原生集成于终端，能够通过 ls、grep 等工具实时感知项目结构 3，使得“理事会”的建议不仅仅是通用的编程知识，而是针对当前代码库的精准建议。  
* **维护的可持续性**：原作者明确表示不打算长期维护该项目 1。将其重构为标准化的 Plugin 13，意味着可以利用 Claude Code 蓬勃发展的插件市场 14 进行分发和社区维护。

---

## **3\. Claude Code 核心架构：Plugins、Skills 与 Sub-agents 的协同**

本次重构的理论基础建立在 Claude Code 的三大核心组件之上。准确理解这三者的职责边界，是构建健壮系统的关键。

### **3.1 Plugin（插件）：标准化的分发容器**

在 Claude Code 生态中，**Plugin** 扮演着“集装箱”的角色。它通过一个严格定义的 plugin.json 清单文件 13，将命令（Commands）、代理（Agents）、技能（Skills）和钩子（Hooks）打包在一起。

对于 llm-council，Plugin 不仅是代码的集合，更是权限与依赖的声明。通过在 plugin.json 中声明对 openai/codex 和 google-gemini/gemini-cli 的依赖，我们可以利用 Claude Code 的环境检测机制，引导用户完成必要的 CLI 工具安装 19。此外，Plugin 架构支持通过 Git 仓库直接分发 14，极大地简化了部署流程——用户只需执行 /plugin install 即可获得完整的“理事会”功能，而无需手动配置 Web 服务器。

### **3.2 Skills（技能）：程序性知识的渐进式披露**

**Skills** 是 Claude Code 区别于传统 Chatbot 的核心特性。传统工具（Tools）通常是原子的函数调用，而 Skills 则是包含复杂指令、脚本和资源的文件夹，并通过 SKILL.md 文件进行定义 5。

在 llm-council 重构中，我们将利用 Skills 的 **渐进式披露（Progressive Disclosure）** 特性 5。

* **浅层披露**：在主会话中，Claude 仅加载 SKILL.md 的 Frontmatter（元数据），如名称和描述。这占用的 Context Token 极少 20。  
* **深层披露**：只有当用户明确触发“召开理事会”的意图时，Claude 才会加载 SKILL.md 中的详细编排逻辑和相关的 Bash 脚本。

这种设计解决了上下文窗口拥挤的问题。如果将复杂的理事会逻辑直接写入系统提示词（System Prompt），不仅浪费 Token，还可能导致模型指令遵循能力的退化。Skills 允许我们将“如何调用三个 CLI 并协调它们”这一复杂的程序性知识封装起来，仅在需要时注入上下文。

### **3.3 Sub-agents（子代理）：上下文隔离与角色专业化**

**Sub-agents** 是 Claude Code 中用于处理特定任务的独立智能实体 12。它们拥有独立的系统提示词、工具集和——最重要的是——独立的上下文窗口 12。

在“三阶段共识机制”中，第三阶段的数据量巨大：包含三个模型的原始回答、三份交叉评审意见以及可能的中间思考过程。如果这些数据全部涌入主会话，不仅会迅速消耗 Token 预算，还会用无关的中间数据“污染”开发者的代码上下文 6。

我们将“主席（Chairman）”设计为一个专门的 Sub-agent。

* **角色定义**：主席被赋予“公正仲裁者”的系统提示词，专注于综合与批判 12。  
* **工具限制**：主席仅被授予 Read 和 Write 工具，剥夺其调用外部 CLI 的能力，从而防止递归调用死循环 17。  
* **生命周期**：主席在任务完成后销毁，其处理的海量中间文本随之消散，仅将最终的“裁决报告”返回给主会话。

---

## **4\. 系统实现详解：基于 Plugin 的组件构建**

本节将详细阐述 llm-council Plugin 的各个组成部分，包括文件结构、清单配置及核心逻辑代码。

### **4.1 目录结构设计**

遵循 Claude Code 的最佳实践 4，我们将项目结构设计如下，以确保组件的模块化与可维护性：

llm-council-plugin/  
├──.claude-plugin/  
│ └── marketplace.json \# 市场元数据 14  
├── plugin.json \# 核心清单文件 13  
├── agents/  
│ └── council-chairman.md \# 主席子代理定义 12  
├── skills/  
│ └── council-orchestrator/ \# 编排技能目录  
│ ├── SKILL.md \# 技能定义与流程 5  
│ └── scripts/ \# 执行脚本  
│ ├── query\_codex.sh  
│ ├── query\_gemini.sh  
│ └── query\_claude.sh  
├── commands/  
│ └── summon-council.md \# Slash Command 定义 23  
└── hooks/  
└── lifecycle.json \# 生命周期钩子 13  
这种结构清晰地分离了声明式配置（json/md）与命令式逻辑（sh），便于通过 Git 进行版本控制。

### **4.2 插件清单配置 (plugin.json)**

plugin.json 是插件的入口，必须严格遵循 Schema 13。

JSON

{  
  "name": "llm-council-plugin",  
  "version": "2.0.0",  
  "description": "基于 Claude Code 架构的多模型共识引擎，集成 OpenAI GPT-5.1, Gemini 3 Pro 与 Claude Sonnet 4.5 CLI。",  
  "author": "Refactor-Architect",  
  "strict": true,   
  "commands": \[  
    "commands/summon-council.md"  
  \],  
  "agents": \[  
    "agents/council-chairman.md"  
  \],  
  "skills": \[  
    "skills/council-orchestrator/"  
  \],  
  "hooks": "hooks/lifecycle.json",  
  "dependencies": {  
    "cli-tools": \["codex", "gemini", "claude"\]   
  }  
}

**关键设计决策：**

* "strict": true：强制要求所有引用的文件必须存在，且符合格式规范，这在开发阶段能快速暴露路径错误 14。  
* "skills" 字段指向目录而非文件：这是因为 Skills 通常包含辅助脚本（如 scripts/ 目录下的 bash 脚本），指向目录允许 Claude 自动发现相关的资源文件 25。

### **4.3 编排技能定义 (SKILL.md)**

这是系统的“大脑”，负责指挥底层 CLI 工具。根据 5 和 25 的规范，SKILL.md 必须包含 Frontmatter 和详细的指令主体。

**文件路径：** skills/council-orchestrator/SKILL.md

---

## **name: council-orchestrator description: 协调 OpenAI、Gemini 和 Claude 模型进行多方会谈。负责解析用户查询，并行调用外部 CLI 工具，管理同行评审流程，并最终委托主席子代理生成报告。 license: MIT version: 1.0.0**

# **Council Orchestration Protocol**

## **概述**

本技能定义了 LLM Council 的标准作业程序（SOP）。你将作为协调者（Coordinator），不直接生成答案，而是通过调用外部工具来获取答案。

## **前置检查**

在执行任何操作前，请验证以下 CLI 工具是否可用：

1. codex (OpenAI Codex CLI)  
2. gemini (Google Gemini CLI)  
3. claude (Claude Code CLI)

如果任一工具缺失，请向用户报错并建议安装命令（如 npm install \-g @openai/codex）。

## **执行流程**

### **第一阶段：意见征集 (Parallel Execution)**

1. **解析输入**：从用户的 Prompt 中提取核心技术问题。  
2. **并行调用**：使用 Bash 工具，在后台并行执行以下包装脚本。必须使用 & 和 wait 确保并发以减少延迟。  
   * skills/council-orchestrator/scripts/query\_codex.sh "{query}"  
   * skills/council-orchestrator/scripts/query\_gemini.sh "{query}"  
   * skills/council-orchestrator/scripts/query\_claude.sh "{query}"  
3. **输出重定向**：将标准输出（stdout）分别保存到临时文件：  
   * .council/stage1\_openai.txt  
   * .council/stage1\_gemini.txt  
   * .council/stage1\_claude.txt

### **第二阶段：同行评审 (Cross-Examination)**

1. **读取上下文**：读取第一阶段生成的三个文本文件。  
2. **构建评审 Prompt**：为每个模型构建一个新的 Prompt，包含其他两个模型的匿名回答。  
   * 这里的 Prompt 应要求模型评估准确性、代码质量和安全性。  
3. **执行评审**：再次调用上述脚本，将评审结果保存到 .council/stage2\_review\_\*.txt。

### **第三阶段：主席综合 (Synthesis)**

1. **调用子代理**：唤醒 council-chairman 子代理。  
2. **传递数据**：将 .council/ 目录下的所有文件内容作为初始上下文传递给主席。  
3. **获取裁决**：要求主席生成最终的 Markdown 格式报告。  
4. **清理**：删除 .council/ 临时目录。

## **错误处理**

* 遇到 Rate Limit (429) 时，实施指数退避策略重试一次。  
* 遇到 CLI 执行错误（Exit Code 非 0），在最终报告中标记该成员为“缺席”。

**深度解析：**

* **并行化策略**：技能文档显式指示使用 Bash 的后台任务功能。由于 Claude Code 能够直接执行 Bash 命令 3，这使得原本需要复杂异步代码（如 Python 的 asyncio）的逻辑可以通过简单的 Shell 脚本实现。  
* **临时文件系统**：利用 .council/ 目录作为数据总线。相比于将所有输出保存在内存变量中，文件系统更加可靠，且方便开发者在调试时检查中间结果。这体现了 Claude Code 作为“终端原生”工具的优势 3。

---

## **5\. 执行层集成：CLI 工具的深度封装与适配**

为了实现“无头（Headless）”自动化调用，我们必须对三个特定的 CLI 工具进行脚本封装。这些脚本需要处理参数传递、模型指定以及输出格式化。

### **5.1 OpenAI / Codex CLI (GPT-5.1) 集成**

根据 OpenAI Codex 的文档 7，Codex CLI 支持通过自然语言指令操作代码库，且最新版本集成了 GPT-5 系列模型。

**脚本路径：** skills/council-orchestrator/scripts/query\_codex.sh

Bash

\#\!/bin/bash  
\# OpenAI Codex CLI Wrapper targeting GPT-5.1  
\# 依赖: @openai/codex (npm install \-g @openai/codex)

PROMPT="$1"

\# 使用 'codex exec' 或类似命令进行非交互式调用  
\# 根据  的 CLI 预览，'/init' 等命令是交互式的，  
\# 但对于自动化，我们假设存在类似 'exec' 或管道模式。  
\# GPT-5.1 是用户指定的模型版本。

codex exec \\  
  \--model "gpt-5.1" \\  
  \--reasoning-effort "high" \\  
  \--instruction "$PROMPT" \\  
  \--output-format "text" 2\>/dev/null

\# 注意：'--reasoning-effort' 参数参考了近期推理模型的配置趋势  
\# 2\>/dev/null 用于屏蔽加载动画或进度条等 stderr 输出

**集成难点与应对：**

* **交互式默认行为**：大多数 AI CLI 默认倾向于交互式会话（Chat REPL）。我们必须通过标志位（Flags）强制其进入“单次执行”模式。如果官方 CLI 不支持，可能需要使用 expect 脚本进行自动化交互 29，但首选方案是寻找类似 \--instruction 或直接参数传递的支持。  
* **模型版本**：gpt-5.1 是未来预测版本。封装脚本的好处在于，当实际版本号变更时，只需修改脚本，无需更新整个 Plugin 逻辑。

### **5.2 Gemini CLI (Gemini 3 Pro Preview) 集成**

Google 的 Gemini CLI 提供了相对完善的脚本化支持 8。特别是其支持通过 \-p 参数直接传递 Prompt 8，以及 JSON 格式输出，这对于程序化解析至关重要。

**脚本路径：** skills/council-orchestrator/scripts/query\_gemini.sh

Bash

\#\!/bin/bash  
\# Google Gemini CLI Wrapper  
\# 依赖: @google/gemini-cli

PROMPT="$1"

\# \[30, 9\] 指出 Gemini CLI 支持 agent 模式和管道操作  
\#  确认了 \-p 参数和 \--output-format json

gemini \\  
  \--prompt "$PROMPT" \\  
  \--model "gemini-3-pro-preview" \\  
  \--output-format "json" \\  
  \--no-stream \\

| jq \-r '.content'

\# 使用 jq 解析 JSON 输出，确保传递给下游的是纯文本  
\# \--no-stream 禁用流式输出，确保完整响应一次性返回

技术洞察：  
利用 \--output-format json 8 能够有效避免 Markdown 代码块标记（如 \`\`\`json）被错误地包含在输出文本中，这在多模型管道中是一个常见的“幻觉”源头。jq 的使用确保了数据的纯净性。

### **5.3 Claude Code (Sonnet 4.5) 的递归调用**

这是一个特殊的“俄罗斯套娃”场景：主 Claude Code 进程调用子 Claude Code 进程。

**脚本路径：** skills/council-orchestrator/scripts/query\_claude.sh

Bash

\#\!/bin/bash  
\# Recursive Claude Code Wrapper  
\# 警告：必须严格隔离上下文，防止无限递归读取

PROMPT="$1"

\# \[11, 31\] 确认了 \-p (print) 标志用于无头模式

claude \\  
  \-p "$PROMPT" \\  
  \--model "claude-sonnet-4.5" \\  
  \--print \\  
  \--no-history \\  
  \--verbose=false

\# \--no-history (假设存在) 或类似机制至关重要，  
\# 防止子进程读取主进程生成的临时文件，造成上下文混乱。

风险管理：  
递归调用最大的风险是上下文污染。如果子 Claude 进程启动时自动读取了当前目录下的 .council/ 文件夹（其中包含它自己即将生成的输出文件），可能会导致逻辑崩溃。因此，在脚本中应尽可能通过环境变量或参数禁用自动上下文加载，或者在一个空的临时目录中执行该命令。

---

## **6\. 核心决策层：主席子代理 (Chairman Sub-agent)**

主席是系统的灵魂，负责将碎片化的信息综合为有价值的洞察。不同于 Skills 的流程控制，Sub-agent 侧重于认知推理。

### **6.1 子代理配置 (council-chairman.md)**

配置文件定义了主席的人格与权限 12。

**文件路径：** agents/council-chairman.md

YAML

\---  
name: council-chairman  
description: LLM 理事会的首席法官。专门负责阅读多方输入，综合不同观点，识别共识与分歧，并生成最终裁决报告。  
model: claude-opus-4.5  
tools: Read, Write  
skills:  
\---

\# System Prompt

你是由 OpenAI、Google 和 Anthropic 顶级模型组成的 LLM 理事会的主席。  
你的职责不是回答用户的问题，而是\*\*评价\*\*和\*\*综合\*\*理事会成员的回答。

\#\# 你的输入  
你将读取 \`.council/\` 目录下的文件，其中包含：  
\- \`stage1\_\*.txt\`: 成员对用户问题的初始回答。  
\- \`stage2\_review\_\*.txt\`: 成员之间的相互评审意见。

\#\# 你的任务  
1. \*\*深度阅读\*\*：分析每个成员的回答逻辑、代码质量和安全性。  
2. \*\*寻找共识\*\*：指出所有模型都同意的关键点（通常是正确答案的核心）。  
3. \*\*仲裁分歧\*\*：当模型意见不一致时，利用你（Opus 4.5）的高级推理能力判断谁是正确的，并解释原因。  
4. \*\*识别幻觉\*\*：如果某个模型提出了明显错误或危险的建议，必须明确指出并予以驳斥。

\#\# 输出格式  
请生成一份 Markdown 格式的决策报告，包含：  
\- \*\*执行摘要\*\*：一句话直接回答用户问题。  
\- \*\*理事会辩论摘要\*\*：列出分歧点和各方论据的表格。  
\- \*\*最终综合建议\*\*：基于所有优点的最佳答案。

\#\# 约束  
\- 你必须保持中立，不能偏袒任何特定模型厂商。  
\- 不要再次调用 \`codex\`, \`gemini\` 或 \`claude\` CLI，你的任务是纯文本分析。

**架构解析：**

* **模型选择**：我们为主席指定了 claude-opus-4.5 10。Opus 系列通常具有更强的推理和长上下文处理能力，适合做最终的总结者，而 Sonnet 系列则更适合作为第一阶段的执行者（如前文 CLI 调用所示）。  
* **权限最小化**：tools: Read, Write 12 限制了主席的能力。它只能读文件（获取输入）和写文件（输出报告），无法联网或执行代码。这不仅是安全考量，也是为了强制架构在“思考”与“行动”之间划清界限。

---

## **7\. 治理与交互：Hooks 与 Slash Command**

为了提升用户体验并保障系统安全，我们利用 Hooks 和 Commands 来完善系统交互。

### **7.1 Slash Command 交互设计**

通过 /council 命令，我们将复杂的后台逻辑封装为简单的一行指令 23。

**文件路径：** commands/summon-council.md

# **/council**

**描述**: 召集 LLM 理事会，对复杂的技术问题进行多模型深度审议。

用法:  
/council "如何优化 React 组件的并发渲染性能？"  
**实现逻辑**:

1. 激活 council-orchestrator 技能。  
2. 将用户输入的参数作为 {query} 传递给技能的执行流程。  
3. 自动向用户展示进度（"正在征询 OpenAI 意见...", "正在进行同行评审..."）。

### **7.2 生命周期钩子与安全防护**

hooks/lifecycle.json 允许我们在特定事件发生时介入 13。

JSON

{  
  "hooks": {  
    "PreToolUse":  
      }  
    \],  
    "PostToolUse":  
      }  
    \]  
  }  
}

**应用场景：**

* **PreToolUse**：在 Skill 试图执行 query\_codex.sh 之前，钩子可以检查 Prompt 中是否包含恶意的 Shell 注入字符，或者检查用户的 API 配额是否充足。  
* **PostToolUse**：如果在第一阶段某个 CLI 返回了空文件（如网络超时），钩子可以拦截并触发自动重试机制，而不是让流程带着空数据进入第二阶段 13。

---

## **8\. 令牌经济学（Token Economics）与性能分析**

从 Web 应用迁移到 CLI 代理架构，对 Token 消耗和性能有着显著影响。

### **8.1 成本结构变化**

| 维度 | 原始 Web 架构 (llm-council) | 新版 Claude Code Plugin 架构 | 影响分析 |
| :---- | :---- | :---- | :---- |
| **主控消耗** | 极低（仅简单的路由逻辑） | **中等**（Orchestrator Skill 的推理） | Claude Code 需要消耗 Token 来理解 Skill 并生成 Bash 命令。 |
| **执行消耗** | 仅支付 API 费用 | **相同**（支付 API 费用） | 第三方模型调用的成本不变。 |
| **上下文开销** | 每次刷新页面重置 | **极低**（利用 Sub-agent 隔离） | 通过将庞大的中间文本限制在子代理中，**避免了主开发会话的上下文膨胀** 6。 |

深度洞察：  
尽管 Claude Code 作为主控本身会消耗 Token，但利用 Sub-agents 处理第三阶段的综合任务是一个巨大的经济优势。在 Web 架构中，如果用户想就最终结果继续提问，通常需要将之前的长对话历史再次发送；而在 Claude Code 中，由于中间过程被子代理消化并丢弃，主会话仅保留最终的高质量报告，使得后续的对话（如“根据这个报告帮我重构代码”）更加廉价且聚焦。

### **8.2 延迟与并发**

Web 应用通常利用浏览器的异步请求实现并发。在 Claude Code 中，虽然模型生成 Bash 命令是串行的，但通过在 SKILL.md 中强制使用 Bash 的后台进程符 & 3，我们实现了 CLI 工具的物理级并行执行。

Bash

\# 并行执行示例  
./query\_codex.sh "..." \> out1.txt &  
./query\_gemini.sh "..." \> out2.txt &  
./query\_claude.sh "..." \> out3.txt &  
wait

这种模式的效率完全取决于本地机器的 Shell 执行能力，消除了 Web 服务器作为中间人的延迟瓶颈。

---

## **9\. 结论与未来展望**

将 llm-council 重构为 Claude Code Plugin，标志着 AI 辅助开发工具从“网页玩具”向“生产力基建”的跨越。通过 **Plugin** 的标准化封装，解决了部署难题；通过 **Skill** 的流程编排，实现了复杂的异步工作流；通过 **Sub-agent** 的上下文管理，保证了主开发流的纯净与高效。

这一架构不仅复现了原项目的民主化决策机制，更将其提升为一个可扩展的协议。未来，开发者可以轻松地在 plugin.json 中添加新的 CLI 工具（如 grok-cli 或本地开源模型 ollama），只需增加一个 Shell 封装脚本并更新 Skill 定义即可。这种开放性与灵活性，正是代理式编程（Agentic Coding）的核心魅力所在。

---

参考文献支持：  
1 (llm-council 原始逻辑)2 (环境依赖问题)15 (LLM-as-a-Judge 理论)6 (上下文污染)12 (子代理特性)4 (仓库结构)10 (Claude 模型版本)3 (Claude Code 能力)17 (CLI 权限)27 (Codex SDK)7 (Codex CLI)8 (Gemini CLI)21 (Token 效率)5 (Skills 原理)8 (Gemini 功能)9 (Gemini 3 Pro)11 (Claude Headless)24 (Hooks)23 (Slash Commands)13 (Plugin Schema)14 (Marketplaces)12 (Sub-agent Config)13 (Manifest 字段)5 (Frontmatter 规范)14 (Strict Mode).

#### **Works cited**

1. karpathy/llm-council: LLM Council works together to answer your hardest questions \- GitHub, accessed November 25, 2025, [https://github.com/karpathy/llm-council](https://github.com/karpathy/llm-council)  
2. LLM Council \- Language Log, accessed November 25, 2025, [https://languagelog.ldc.upenn.edu/nll/?p=72058](https://languagelog.ldc.upenn.edu/nll/?p=72058)  
3. Claude Code overview \- Claude Code Docs, accessed November 25, 2025, [https://code.claude.com/docs/en/overview](https://code.claude.com/docs/en/overview)  
4. wshobson/agents: Intelligent automation and multi-agent ... \- GitHub, accessed November 25, 2025, [https://github.com/wshobson/agents](https://github.com/wshobson/agents)  
5. Claude Agent Skills: A First Principles Deep Dive \- Han Lee, accessed November 25, 2025, [https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)  
6. Understanding Claude Skills vs. Subagents. It's not that confusing : r/ClaudeAI \- Reddit, accessed November 25, 2025, [https://www.reddit.com/r/ClaudeAI/comments/1obq6wq/understanding\_claude\_skills\_vs\_subagents\_its\_not/](https://www.reddit.com/r/ClaudeAI/comments/1obq6wq/understanding_claude_skills_vs_subagents_its_not/)  
7. Codex CLI \- OpenAI for developers, accessed November 25, 2025, [https://developers.openai.com/codex/cli/](https://developers.openai.com/codex/cli/)  
8. google-gemini/gemini-cli: An open-source AI agent that ... \- GitHub, accessed November 25, 2025, [https://github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)  
9. 5 things to try with Gemini 3 Pro in Gemini CLI \- Google Developers Blog, accessed November 25, 2025, [https://developers.googleblog.com/en/5-things-to-try-with-gemini-3-pro-in-gemini-cli/](https://developers.googleblog.com/en/5-things-to-try-with-gemini-3-pro-in-gemini-cli/)  
10. Claude Code, accessed November 25, 2025, [https://www.claude.com/product/claude-code](https://www.claude.com/product/claude-code)  
11. Headless mode \- Claude Code Docs, accessed November 25, 2025, [https://code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless)  
12. Subagents \- Claude Code Docs, accessed November 25, 2025, [https://code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)  
13. Plugins reference \- Claude Code Docs, accessed November 25, 2025, [https://code.claude.com/docs/en/plugins-reference](https://code.claude.com/docs/en/plugins-reference)  
14. Plugin marketplaces \- Claude Code Docs, accessed November 25, 2025, [https://code.claude.com/docs/en/plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)  
15. machine-theory/lm-council: LLMs sitting on a council together to decide, by consensus, who among them is the best. \- GitHub, accessed November 25, 2025, [https://github.com/llm-council/llm-council](https://github.com/llm-council/llm-council)  
16. openai/codex: Lightweight coding agent that runs in your terminal \- GitHub, accessed November 25, 2025, [https://github.com/openai/codex](https://github.com/openai/codex)  
17. Claude Code: Best practices for agentic coding \- Anthropic, accessed November 25, 2025, [https://www.anthropic.com/engineering/claude-code-best-practices](https://www.anthropic.com/engineering/claude-code-best-practices)  
18. A curated list of awesome plugins for Claude \- GitHub, accessed November 25, 2025, [https://github.com/GiladShoham/awesome-claude-plugins](https://github.com/GiladShoham/awesome-claude-plugins)  
19. Team Setup Guide: Standardizing Claude Code Plugin Usage \- Skywork.ai, accessed November 25, 2025, [https://skywork.ai/blog/claude-code-plugin-standardization-team-guide/](https://skywork.ai/blog/claude-code-plugin-standardization-team-guide/)  
20. Claude Skills are awesome, maybe a bigger deal than MCP \- Simon Willison's Weblog, accessed November 25, 2025, [https://simonwillison.net/2025/Oct/16/claude-skills/](https://simonwillison.net/2025/Oct/16/claude-skills/)  
21. Introducing advanced tool use on the Claude Developer Platform \- Anthropic, accessed November 25, 2025, [https://www.anthropic.com/engineering/advanced-tool-use](https://www.anthropic.com/engineering/advanced-tool-use)  
22. \[BUG\] Sub-agents Don't Inherit Model Configuration in Task Tool · Issue \#5456 · anthropics/claude-code \- GitHub, accessed November 25, 2025, [https://github.com/anthropics/claude-code/issues/5456](https://github.com/anthropics/claude-code/issues/5456)  
23. Agent SDK overview \- Claude Docs, accessed November 25, 2025, [https://platform.claude.com/docs/en/agent-sdk/overview](https://platform.claude.com/docs/en/agent-sdk/overview)  
24. The Ultimate Claude Code Guide: Every Hidden Trick, Hack, and Power Feature You Need to Know \- DEV Community, accessed November 25, 2025, [https://dev.to/holasoymalva/the-ultimate-claude-code-guide-every-hidden-trick-hack-and-power-feature-you-need-to-know-2l45](https://dev.to/holasoymalva/the-ultimate-claude-code-guide-every-hidden-trick-hack-and-power-feature-you-need-to-know-2l45)  
25. Agent Skills \- Claude Docs, accessed November 25, 2025, [https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)  
26. Equipping agents for the real world with Agent Skills \- Anthropic, accessed November 25, 2025, [https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)  
27. Codex SDK \- OpenAI for developers, accessed November 25, 2025, [https://developers.openai.com/codex/sdk/](https://developers.openai.com/codex/sdk/)  
28. Codex | OpenAI, accessed November 25, 2025, [https://openai.com/codex/](https://openai.com/codex/)  
29. How to automate cli interactions with gh copilot using expect \- Stack Overflow, accessed November 25, 2025, [https://stackoverflow.com/questions/79253147/how-to-automate-cli-interactions-with-gh-copilot-using-expect](https://stackoverflow.com/questions/79253147/how-to-automate-cli-interactions-with-gh-copilot-using-expect)  
30. lst97/claude-code-sub-agents: Collection of specialized AI subagents for Claude Code for personal use (full-stack development). \- GitHub, accessed November 25, 2025, [https://github.com/lst97/claude-code-sub-agents](https://github.com/lst97/claude-code-sub-agents)