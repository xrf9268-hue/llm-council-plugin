# LLM Council Plugin Cleanup 逻辑修复设计方案

## 1. 背景与问题概述

### 1.1 背景

LLM Council 插件通过 `council-orchestrator` skill 在项目根目录下创建工作目录 `.council/`，用于存放多模型会话的中间文件和最终报告：

- 阶段 1：`stage1_*.txt` 各模型初始回答
- 阶段 2：`stage2_review_*.txt` 交叉评审结果
- 阶段 3：`final_report.md` 主席综合报告

`skills/council-orchestrator/scripts/council_utils.sh` 中的 `council_cleanup` 函数负责清理该目录：

```bash
council_cleanup() {
    if [[ -d "$COUNCIL_DIR" ]]; then
        rm -rf "$COUNCIL_DIR"
        echo -e "${GREEN}Cleaned up council working directory${NC}" >&2
    fi
}
```

当前文档（`SKILL.md` / `REFERENCE.md`）和示例推荐在读取 `final_report.md` 后立即调用 `council_cleanup`，并且面向用户的提示文案中仍然声称“报告已保存到 `.council/final_report.md`”。这会导致：

- 实际上目录已被删除，用户无法再次访问报告；
- 文案与真实状态不一致，体验和信任度受损。

### 1.2 修复目标

- 确保用户在会话结束后可以可靠访问 `final_report.md`。
- 消除“声称报告已保存但已被删除”的误导性行为。
- 保留 `council_cleanup` 作为实用工具函数，但不再在 **会话结束阶段** 隐式调用；而是在需要时显式调用（例如在 `/council` 命令开始前用于重置工作目录，或在独立清理命令中使用）。
- 提供显式、可发现的清理方式，适用于希望保持工作目录整洁的用户。

### 1.3 非目标

- 不改变 `council_cleanup` 的语义：仍然是“删除整个 `.council/` 工作目录”的强力操作。
- 不重构现有 Bash 脚本的整体架构。
- 不在本次修复中强制启用“历史报告持久化”，该功能作为可选增强设计。

---

## 2. 设计原则

1. **真实反映状态**  
   所有面向用户的文案必须与实际文件状态一致，不承诺已删除资源的可用性。

2. **默认安全保留**  
   默认行为应保护用户成果（报告）不被自动删除，清理行为由用户显式触发。

3. **向后兼容**  
   保留 `council_cleanup` 函数和已有脚本接口，降低对现有工作流的破坏性。

4. **易于发现和理解**  
   清理方式和报告位置需要在命令说明和文档中清晰可见，避免“隐形行为”。

5. **与现有插件约定一致**  
   路径解析、模型选择、命令风格与当前仓库（`AGENTS.md`、现有 commands/skills/hooks）保持一致。

---

## 3. 当前行为与问题点

### 3.1 当前推荐执行流程（简化）

在 `SKILL.md` / `REFERENCE.md` 中，Phase 3（主席综合阶段）典型示例为：

```bash
# Phase 3
CHAIRMAN_PROMPT=$(./skills/council-orchestrator/scripts/run_chairman.sh "$query" .council)
# [Invoke chairman agent with $CHAIRMAN_PROMPT]

# Output
cat .council/final_report.md
council_cleanup
```

会话日志中也体现了类似流程：

1. 读取 `.council/final_report.md`（并在界面中展示）。
2. 通过 Bash 工具执行 `council_cleanup` 删除 `.council/`。
3. 向用户提示“完整报告已保存到 `.council/final_report.md`”。

### 3.2 问题总结

- **行为与文案不一致**：  
  清理后仍告知用户“报告已保存到 `.council/final_report.md`”，但实际目录已删除。

- **默认行为不利于复查**：  
  用户想在会话结束后再次查看或分享完整报告时，必须依赖当次会话上下文，而无法通过文件系统访问。

- **缺少显式清理入口**：  
  清理逻辑以示例和 skill 说明的形式“隐性触发”，用户很难意识到这一操作会删除报告。

---

## 4. 目标行为概览

在修复完成后，期望的目标行为如下：

1. **每次运行 `/council` 前重置 `.council/` 工作目录**  
   - 在执行本次会话前，如果存在旧的 `.council/` 目录，先调用 `council_cleanup` 删除，再调用 `council_init` 重新创建。
   - 确保 `.council/` 中的 Stage 1/2 文件和 `final_report.md` **全部只属于本次执行**，避免跨次运行污染。

2. **默认不在会话结束后自动清理 `.council/`**  
   - `/council` 命令完成后，`final_report.md` 和相关中间文件默认保留在 `.council/` 中。
   - 用户可以通过文件系统或后续工具再次访问这些文件；下一次运行 `/council` 会在开始前自动重置目录。

2. **文案与状态一致**  
   - 会话结束时的提示明确说明：报告已展示且保存在 `.council/final_report.md`，但不会声称在清理之后仍然存在。

3. **提供显式清理命令 `/council-cleanup`**  
   - 用户可主动调用该命令来删除 `.council/` 中的所有会话文件。
   - 执行前有明确的删除提示，执行后给出“已清理”反馈。

4. **可选的历史报告持久化（增强项）**  
   - 通过环境变量启用，可在每次会话完成前将 `final_report.md` 复制到持久化目录（例如 `${CLAUDE_PROJECT_DIR}/.council/reports/`）。
   - 默认关闭，以避免意外占用过多磁盘空间。

---

## 5. 详细设计

### 5.1 Phase 1：核心逻辑与文档修复（必做）

#### 5.1.1 移除默认自动 cleanup 调用

**变更点：**

- `skills/council-orchestrator/SKILL.md`
  - 在 “Phase 3: Chairman Synthesis” 示例中，将：
    ```bash
    cat .council/final_report.md
    council_cleanup
    ```
    调整为仅：
    ```bash
    cat .council/final_report.md
    ```
  - 在 “Full Automated Run” 示例末尾同样移除 `council_cleanup` 调用。

- `skills/council-orchestrator/REFERENCE.md`
  - 保留 `Step 3.5: Cleanup` 段落，但明确标注为**可选操作**，示例形如：
    ```bash
    # 可选：如需清理本次会话的所有中间文件和最终报告
    council_cleanup
    # 或手动：
    # rm -rf .council
    ```
  - 在说明文字中强调：默认推荐在确认不再需要本次会话文件后再执行。

- `skills/council-orchestrator/EXAMPLES.md`
  - 所有示例中默认不再包含自动 `council_cleanup` 调用。
  - 如需展示清理流程，单独添加一个示例，明确标注“可选清理步骤”。

**效果：**

- Skill 文档不再鼓励在每次会话完成后立即删除 `.council/`。
- 面向 Claude 的“实现指引”会自然引导其保留报告文件，并将清理职责转移到显式的“会话前重置”或独立清理命令中。

#### 5.1.2 更新安全与行为描述

**变更点：**

- `skills/council-orchestrator/SKILL.md` 中“Security Best Practices”目前包含类似：
  > Temporary Files: All data in `.council/` automatically cleaned up after synthesis

  应改为：
  > Temporary Files: All data in `.council/` is stored in a dedicated working directory. By default, files are preserved after synthesis so users can review or reuse the final report. Use `council_cleanup` or `/council-cleanup` to explicitly remove these files when no longer needed.

**效果：**

- 安全章节与新的默认行为保持一致，不再声明“自动清理”。

#### 5.1.3 `/council` 命令输出约定

**变更点：**

- `commands/council.md` 的 Implementation Instructions 中，增加对最终输出的明确要求，例如：
  - 在完成 skill 调用并拿到综合报告后：
    - 向用户展示完整 Markdown 报告内容；
    - 追加简要说明，指出报告文件位置与清理方式，例如：
      > ✅ Council 综合报告已生成并展示完毕  
      > 📄 完整报告保存在项目根目录下的 `.council/final_report.md`  
      > 💡 如需删除本次会话文件，可在将来使用 `/council-cleanup` 命令，或手动执行 `council_cleanup`。

**效果：**

- `/council` 命令的用户体验更完整，用户能迅速知道报告位置和后续操作选项。

#### 5.1.4 为 `/council` 命令增加“Phase 0：重置工作目录”

为了保证每次运行 `/council` 的幂等性和隔离性，需要在命令开始时显式重置 `.council/` 工作目录：

**变更点：**

- 在 `commands/council.md` 的 Implementation Instructions 中，在启动 `council-orchestrator` skill 之前增加一个步骤：
  - 使用 **Bash tool** 执行：
    ```bash
    # Phase 0: reset council working directory for this run
    source ./skills/council-orchestrator/scripts/council_utils.sh
    council_cleanup || true   # 如果目录不存在，忽略错误
    council_init               # 重新创建 .council/
    ```
  - 然后再继续 Phase 1/2/3 的 orchestrator 调用。

**效果：**

- 确保 `.council/` 在每次 `/council` 执行前都是干净的，防止上一轮会话残留的 Stage 1/2 文件或 `final_report.md` 参与本次 deliberation。
- 保持用户视角的一致性：`.council/` 始终代表“最近一次 `/council` 调用”的工作区；下次再运行会覆盖当前目录内容，但不会在会话结束时立即删除。

---

### 5.2 Phase 2：新增 `/council-cleanup` 命令（推荐）

新增一个专门用于清理 council 工作目录的命令，避免用户直接记忆和执行底层 Bash。

#### 5.2.1 命令定义

**文件：** `commands/council-cleanup.md`

**建议前言：**

```yaml
---
description: Clean up the LLM Council working directory and temporary files created in .council/.
model: claude-haiku-4-5-20251001
---
```

**正文关键点：**

- H1 标题：`# Council Cleanup`
- 用途说明：
  - 删除 `.council/` 目录及其中的全部文件，包括 `final_report.md`。
  - 适用于：会话结束且确认不再需要本次会话文件时，释放空间或保持项目目录整洁。

**Implementation Instructions（要点）：**

1. 使用 **Bash tool**，在项目根目录执行：
   ```bash
   if [[ -d ".council" ]]; then
       echo "⚠️ This will delete the .council/ directory, including final_report.md and all session files."
       source ./skills/council-orchestrator/scripts/council_utils.sh
       council_cleanup
       echo "✅ Council working directory cleaned."
   else
       echo "ℹ️ No .council/ working directory found (already clean)."
   fi
   ```
2. 不需要任何参数；命令为幂等，多次运行在目录缺失时仅返回友好提示。

#### 5.2.2 插件注册与文档更新

- 在 `.claude-plugin/plugin.json` 中注册新命令路径：`"./commands/council-cleanup.md"`。
- 在 `README.md` / `docs/INSTALL.md` 中：
  - 在介绍 `/council` 时补充一小节，说明：
    - 报告默认保存在 `.council/final_report.md`；
    - 使用 `/council-cleanup` 可以清理所有会话文件。
  - 在“故障排查”或“使用技巧”部分，提及如果 `.council/` 中存在旧会话数据，可以通过该命令清理后重新运行 council。

---

### 5.3 Phase 3：历史报告持久化（可选增强）

该部分为可选设计，优先级低于 Phase 1/2，不要求本次修复立即落地，但提前设计有利于后续扩展。

#### 5.3.1 环境变量与目录约定

- 新增可选环境变量：
  - `COUNCIL_SAVE_REPORTS`：`true` 时启用历史报告持久化；默认未设置或 `false` 表示关闭。
  - `COUNCIL_REPORTS_DIR`：持久化目录，默认值建议为：
    ```bash
    COUNCIL_REPORTS_DIR="${COUNCIL_REPORTS_DIR:-${CLAUDE_PROJECT_DIR:-.}/.council/reports}"
    ```

#### 5.3.2 报告保存逻辑（概念设计）

在 Phase 3（主席完成）且 `final_report.md` 已生成后：

1. 检查 `COUNCIL_SAVE_REPORTS` 是否为 `true`；否则直接返回。
2. 确认 `.council/final_report.md` 存在且非空。
3. 创建持久化目录：
   ```bash
   mkdir -p "$COUNCIL_REPORTS_DIR"
   ```
4. 生成基于时间戳的文件名，例如：
   ```bash
   REPORT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
   SAVED_REPORT="${COUNCIL_REPORTS_DIR}/council_report_${REPORT_TIMESTAMP}.md"
   cp ".council/final_report.md" "$SAVED_REPORT"
   ```
5. 在输出中向用户提示持久化路径（例如在 orchestrator 结果描述中追加一行说明）。

**注意事项：**

- 需要在文档中提醒：启用持久化后可能累积大量文件，建议定期清理旧报告（可以未来再引入辅助脚本）。
- 不在本次修复中强制实现自动清理策略，以保持设计简单。

---

## 6. 测试与验证计划

### 6.1 功能测试

1. **默认行为测试**
   - 运行一次完整 `/council` 会话。
   - 验证：
     - 会话结束时 UI 中展示了完整综合报告；
     - 项目根目录存在 `.council/final_report.md` 且内容与展示一致；
     - `.council/` 目录整体仍然存在。

2. **清理命令测试**
   - 在 `.council/` 存在时运行 `/council-cleanup`：
     - 验证命令提示中包含“将删除 `.council/` 及报告”的警告；
     - 清理后 `.council/` 目录不存在。
   - 再次运行 `/council-cleanup`：
     - 验证返回“已是干净状态”的信息，不报错。

3. **兼容性测试**
   - 在 `.council/` 目录不存在时直接运行 `/council`：
     - 确认会话仍能正常创建目录并完成全部阶段。
   - 如存在旧版本工作流依赖 `council_cleanup` 手动调用的情况（用户自定义脚本），验证其行为不变。

### 6.2 自动化测试建议

- 在 `tests/test_runner.sh` 中新增或扩展测试用例：
  - 检查运行 orchestrator 后 `.council/final_report.md` 的存在性；
  - 检查调用清理逻辑（通过脚本模拟 `/council-cleanup`）后 `.council/` 是否被删除。

---

## 7. 迁移与向后兼容性

- **对现有用户的影响：**
  - 原本自动删除 `.council/` 的行为将变为默认保留，属于“宽松变更”，不会破坏已有脚本，但会让磁盘占用略有增加。
  - 强依赖“每次会话后目录必须为空”的用户可以：
    - 手动调用 `council_cleanup`，或
    - 使用新提供的 `/council-cleanup` 命令。

- **向后兼容策略：**
  - 不修改 `council_cleanup` 函数签名和行为。
  - 所有变更集中在文档、命令实现和默认工作流上，避免破坏 hooks 和 skill 调用协议。

---

## 8. 实施清单（摘要）

**Phase 1：核心逻辑与文档（必做）**
- [ ] 修改 `skills/council-orchestrator/SKILL.md`：移除默认 `council_cleanup` 调用，更新安全说明。
- [ ] 修改 `skills/council-orchestrator/REFERENCE.md`：把 cleanup 标记为可选步骤。
- [ ] 修改 `skills/council-orchestrator/EXAMPLES.md`：从默认示例中移除 cleanup，仅在需要时作为可选示例出现。
- [ ] 修改 `commands/council.md`：明确输出中说明报告位置和推荐的清理方式。

**Phase 2：清理命令与插件注册（推荐）**
- [ ] 新增 `commands/council-cleanup.md`，实现无参清理命令，使用 Bash tool 调用 `council_cleanup`。
- [ ] 更新 `.claude-plugin/plugin.json`：注册 `./commands/council-cleanup.md`。
- [ ] 更新 `README.md` / `docs/INSTALL.md`：添加报告位置和 `/council-cleanup` 使用说明。

**Phase 3：历史报告持久化（可选）**
- [ ] 在适当脚本中引入 `COUNCIL_SAVE_REPORTS`、`COUNCIL_REPORTS_DIR` 支持，并实现报告副本保存逻辑。
- [ ] 在文档中说明持久化行为、目录位置和潜在的磁盘占用问题。

实施完 Phase 1 + Phase 2 后，即可彻底解决“cleanup 后仍声称报告已保存”的核心问题，并显著提升用户对报告可用性的信心。Phase 3 则为后续增强提供清晰扩展路径。 
