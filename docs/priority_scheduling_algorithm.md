# 学习时间优化排课算法设计（论文"算法设计"章节素材）

> 状态：算法已用纯 Dart 实现并通过 9 个单元测试（`lib/courses/priority_scheduler.dart` + `test/courses/priority_scheduler_test.dart`），本稿与实现逐条对应、可复现。
> 用途：供作者审查后接入 LinkStudy 真实排课流程。

## 0. 问题定义

**输入**

- 课程集合 $\mathcal{C} = \{c_1, c_2, \dots, c_n\}$，每门课 $c_i$ 含：
  - 时长 $d_i$（分钟）；
  - 难度 $diff_i \in [1,9]$、重要程度 $imp_i \in [1,9]$（由 AI 分析给出）；
  - 截止日期 $deadline_i$（可缺省，缺省视为无截止）。
- 用户选择的学习强度档位 $L \in \{\text{轻松}, \text{中等}, \text{高强度}\}$（或按课程分配档位，见 3.4）。
- 每日可用时间范围 $[T_{start}, T_{end})$（分钟），与不可用时间段集合 $\mathcal{B} = \{b_1, b_2, \dots\}$（午休、已有安排等）。
- 排课窗口天数 $H$。

**输出**

- 排课方案 $\mathcal{S} = \{(c_i, day, start, end)\}$：每门课一个或多个连续学习块，满足：全部落在可用时间内、不与不可用时间冲突、符合强度档位的时长与分布约束；无法完全安排的课程给出可读失败原因。

**优化目标**

在满足硬约束（时间窗、不可用时间、强度上限）的前提下，使高优先系数课程优先获得最佳时段（峰值时段、尽早落位），最大化学习时间利用率与学习效果。

---

## 1. 算法一：基于 AHP 的课程优先系数计算

### 1.1 输入输出定义

- 输入：课程集合（含 $diff_i$、$imp_i$、$deadline_i$），用户偏好 $a$（"重要程度"相对"难度"的支配强度，默认 $a=3$）。
- 输出：每门课的综合优先系数 $P_i \in [0,1]$。

### 1.2 算法思想

不采用简单加权平均，而是先用层次分析法（AHP）建立"难度"与"重要程度"两因子的两两比较矩阵，求得二者相对权重；再引入"紧迫度"因子作为动态修正项，随截止日期临近而放大其权重。三个归一化因子加权合成 $P_i$。

### 1.3 详细步骤

**步骤 1：构建两两比较矩阵**

$$A = \begin{bmatrix} 1 & a \\ 1/a & 1 \end{bmatrix}$$

其中 $a$ 表示"重要程度"相对"难度"的支配强度（$a>0$；$a=3$ 表示重要程度略强于难度）。

**步骤 2：几何平均法求权重（2×2 一致矩阵无需解特征方程）**

$$w_{imp} = \frac{\sqrt{a}}{\sqrt{a}+\sqrt{1/a}} = \frac{a}{a+1}, \qquad w_{diff} = \frac{1}{a+1}$$

当 $a=3$ 时 $w_{imp}=0.75,\ w_{diff}=0.25$，且 $w_{imp}+w_{diff}=1$。

**步骤 3：紧迫度因子**

$$u_i = \begin{cases} 0, & deadline_i \text{ 缺省} \\ \dfrac{1}{deadline_i^{\text{剩余天数}}+1}, & \text{否则} \end{cases}$$

$u_i$ 随剩余天数减少而单调增大（剩余 0 天时为 1，趋近 0 时为 0）。

**步骤 4：集合内 min-max 归一化**

对全部课程的难度、重要程度、紧迫度分别做归一化：

$$n_{diff,i} = \frac{diff_i - \min_j diff_j}{\max_j diff_j - \min_j diff_j},\quad n_{imp,i} = \frac{imp_i - \min_j imp_j}{\max_j imp_j - \min_j imp_j},\quad n_{urg,i} = \frac{u_i - \min_j u_j}{\max_j u_j - \min_j u_j}$$

（上下界相等时取中性值 0.5。）

**步骤 5：动态紧迫度权重**

$$w_{urg,i} = \beta \cdot (1 + 3 n_{urg,i})$$

其中 $\beta$ 为紧迫度基础权重（默认 0.2），随截止临近（$n_{urg,i} \to 1$）放大到 $0.8$。

**步骤 6：综合优先系数（分母归一化，保证 $P_i \in [0,1]$）**

$$P_i = \frac{w_{diff}\cdot n_{diff,i} + w_{imp}\cdot n_{imp,i} + w_{urg,i}\cdot n_{urg,i}}{w_{diff} + w_{imp} + w_{urg,i}}$$

### 1.4 伪代码

```
function AHP_Weights(a):
    w_imp  ← a / (a + 1)
    w_diff ← 1 / (a + 1)
    return (w_diff, w_imp)

function PriorityCoefficient(course, minDiff, maxDiff, minImp, maxImp, minUrg, maxUrg):
    u ← course.deadline == null ? 0 : 1 / (course.deadline + 1)
    nDiff ← MinMax(course.diff,  minDiff, maxDiff)
    nImp  ← MinMax(course.imp,   minImp,  maxImp)
    nUrg  ← MinMax(u,           minUrg,  maxUrg)
    wUrg  ← 0.2 * (1 + 3 * nUrg)
    total ← w_diff + w_imp + wUrg
    return (w_diff*nDiff + w_imp*nImp + wUrg*nUrg) / total
```

### 1.5 复杂度分析

- 时间：$O(n)$（单遍扫描求 min/max 各一次，再单遍计算 $P_i$）；空间：$O(n)$。
- 可进一步简化为单遍在线计算（维护运行 min/max），复杂度不变。

### 1.6 与文献方法的对比

| 维度 | 本文 | Com-DDPG（arXiv:2012.05105） | 相控阵雷达动态调度（arXiv:2409.19201） |
|---|---|---|---|
| 因子 | 难度 + 重要程度 + 紧迫度（动态） | AHP 确定任务优先级 | 重要性 + 紧急性（等权）+ 时间偏移比 |
| 权重获取 | AHP 2×2 几何平均法（闭式解） | AHP 层次结构 | 优先级表 + 动态修正 |
| 归一化 | 集合内 min-max，分母归一化保证 $P \in [0,1]$ | — | — |
| 应用场景 | 学习任务排课 | 移动边缘计算卸载 | 雷达资源调度 |

改进点：相比 Com-DDPG 的通用 AHP，本文将紧迫度设计为**动态权重修正项**（而非固定第三因子），并在分母归一化中保持 $P_i$ 有界，避免权重和大于 1 的常见错误；相比雷达调度固定的"重要性+紧急性等权"，本文允许用户通过 $a$ 调节因子主导关系。

---

## 2. 算法二：可用时间片生成

### 2.1 输入输出定义

- 输入：每日范围 $[T_{start}, T_{end})$（分钟）、粒度 $g$（如 30 分钟）、不可用时间段集合 $\mathcal{B}$。
- 输出：按时间排序的可用时间片数组 $\mathcal{A} = \{(s_1,e_1), (s_2,e_2), \dots\}$，每片长度为 $g$。

### 2.2 算法思想

先把时间范围切分成固定粒度的时间片，再遍历不可用时间段，用布尔"与"运算把被覆盖的时间片标记为不可用，剩余的即为可用时间片。该过程等价于"最大可安排时间数组"与"已占用时间数组"求差。

### 2.3 详细步骤

**步骤 1：初始化**

$$\mathcal{A} \leftarrow \big\{ (T_{start}+kg,\ T_{start}+(k{+}1)g) \mid k=0,1,\dots,\ \text{且 } T_{start}+(k{+}1)g \le T_{end} \big\}$$

**步骤 2：不可用时间排除**

将 $\mathcal{B}$ 按起始时间排序；维护游标 $cursor$ 从 $T_{start}$ 开始：
- 对每个不可用段 $b=(b_s, b_e)$：若 $b_e \le cursor$ 跳过；若 $b_s > cursor$，把 $[cursor, b_s)$ 切块加入 $\mathcal{A}$；然后 $cursor \leftarrow \max(cursor, b_e)$。
- 若 $cursor \ge T_{end}$ 提前终止。

**步骤 3：尾部收尾**

把 $[cursor, T_{end})$ 切块加入 $\mathcal{A}$。

### 2.4 伪代码

```
function AvailableSlices(T_start, T_end, g, B):
    sort B by start
    A ← []; cursor ← T_start
    for b in B:
        if b.end ≤ cursor: continue
        if b.start > cursor:
            for s = cursor; s + g ≤ b.start; s += g:
                A.append((s, s+g))
        cursor ← max(cursor, b.end)
        if cursor ≥ T_end: break
    for s = cursor; s + g ≤ T_end; s += g:
        A.append((s, s+g))
    return A
```

### 2.5 复杂度分析

- 时间：$O(|\mathcal{B}|\log|\mathcal{B}| + T_{end}/g)$（排序 + 切块）；空间：$O(T_{end}/g)$。
- 典型值：$T_{end}/g = 14\text{h}/30\text{min} = 28$ 片/天，$H=14$ 天共 392 片，开销可忽略。

### 2.6 与文献方法的对比

与常见自动排课算法中"时间片与运算"（将可用区间与占用区间逐片取与）等价，但本文将**不可用时间与"已有安排"统一建模为 $\mathcal{B}$**，并采用单次游标扫描（而非逐片布尔数组），在 $|\mathcal{B}|$ 较大时更高效。

---

## 3. 算法三：强度档位与时间片的匹配规则

### 3.1 输入输出定义

- 输入：强度档位 $L$、课程剩余时长、当天可用区间、专注峰值时段 $\mathcal{P}$（可配置或由历史学习数据学习）、强度配置参数（$T_{max}$ 单块上限、$D_{max}$ 每日上限、$chunk$ 拆块粒度、$interval$ 间隔天数）。
- 输出：匹配到的连续时间块，或"无可用块"。

### 3.2 算法思想

三档强度不是"时长长短"的简单划分，而是对应不同的认知负荷承受能力与时间分布规律（认知负荷理论、间隔学习效应、单次有效专注时长实证数据）：

| 档位 | 匹配规则 | 认知依据 |
|---|---|---|
| 高强度 | 优先匹配专注峰值时段；单块时长 ≤ $T_{max}$（默认 50min）；每日该档总量 ≤ $D_{max}$（默认 90min） | 单次有效专注时长 25–50min 实证 |
| 中等 | 按间隔重复规律分布：同一门课拆块，相邻块间隔 ≥ $interval{+}1$ 天（默认隔 1 天），每天一块 | 间隔效应（Cepeda et al. 2006） |
| 轻松 | 对连续性要求最低：碎片填缝、一次放满（不拆块），优先使用零碎可用片 | 低认知负荷任务可穿插于碎片时间 |

### 3.3 匹配规则定义

对强度档位 $L$，其参数为 $(\text{Profile}_L) = (T_{max}^L,\ D_{max}^L,\ chunk^L,\ interval^L)$：

```text
Light:   T_max=45, D_max=180, chunk=0(一次放满), interval=0
Medium:  T_max=60, D_max=150, chunk=30,          interval=1
High:    T_max=50, D_max=90,  chunk=50,          interval=0
```

块长计算：

$$need = \begin{cases} \min(chunk^L,\ remaining), & chunk^L>0 \\ remaining, & \text{否则} \end{cases}, \qquad block = \min(need,\ T_{max}^L,\ D_{max}^L - used_{day,L})$$

高强度档在峰值时段 $\mathcal{P}$ 内寻找块；找不到时降级到普通可用片。

### 3.4 档位来源（两种模式）

1. **全局模式**：用户选择单一档位 $L$，所有课程按该档位的分布规律排课（当前 App 交互）。
2. **逐课模式**：AI 按课程难度把每门课归入档位（简单→轻松、中等→中等、难→高强度），与"算法一由 AI 分析难度/重要程度"的数据流一致。论文推荐模式 2。

### 3.5 复杂度分析

- 每次匹配：$O(S)$（$S$ 为当天时间片数）；每门课至多 $d_i / chunk$ 次匹配，整体 $O(\sum_i d_i \cdot S / chunk)$。

### 3.6 与文献方法的对比

- 与"间隔学习研究综述"（Hans 出版社）的间隔重复策略一致，但本文将间隔参数化为**离散天间隔**并纳入强度档位配置；
- 与"智慧学习环境中的认知负荷问题"（高媛等）的认知负荷管理思想一致，通过 $T_{max}/D_{max}$ 硬上限将认知负荷约束显式建模为调度约束，而非启发式建议。

---

## 4. 算法四：贪心分配调度（主流程）

### 4.1 输入输出定义

- 输入：$\mathcal{C}$（已算好 $P_i$ 与档位 $L_i$）、$\mathcal{A}$（算法二输出，按天组织）、峰值时段 $\mathcal{P}$、强度配置。
- 输出：排课方案 $\mathcal{S}$ 与失败列表 $\mathcal{F}$。

### 4.2 算法思想

按优先系数降序依次为每门课匹配"最符合其强度档位要求"的可用时间块，是 0-1 背包问题在"连续时间资源 + 课程可拆块"约束下的贪心简化版本。高优先课程先选最佳时段；放不下时按优先系数降序保高弃低。

### 4.3 详细步骤

**步骤 1：排序**——按 $P_i$ 降序排列课程。

**步骤 2：初始化**——每天维护一个可用区间集合 $\mathcal{A}_d$（由时间片合并、随分配收缩），以及每天各档位已用时长 $used_{d,L}$。

**步骤 3：逐课分配**——对每门课 $c_i$（剩余时长 $remaining = d_i$，起始日 $startDay$）：

- 高强度：在当天峰值时段内找块；无峰值或不够时降级到普通可用片；单块受 $T_{max}$、每日受 $D_{max}$ 约束；放不下则次日继续。
- 中等：每天至多一块，块长 ≤ $chunk$；放完一块后 $startDay$ 跳到 $interval{+}1$ 天后（间隔重复）。
- 轻松：任意可用片，一次放满（不拆块）。

**步骤 4：占位更新**——取到块 $(s,e)$ 后：从 $\mathcal{A}_d$ 移除 $[s,e)$（可能切分区间）、更新 $used_{d,L}$、更新课程剩余时长与最后放置日。

**步骤 5：失败处理**——遍历完窗口仍 $remaining > 0$ 的课程记入 $\mathcal{F}$（附可读原因，如"时间窗口内无满足强度档位的可用时间"）。

**步骤 6：输出**——按 (day, start) 排序输出 $\mathcal{S}$。

### 4.4 伪代码

```
function ScheduleByPriority(C, H, T_start, T_end, B, P, profiles, g):
    A ← { d: Merge(AvailableSlices(T_start, T_end, g, B[d])) for d in 0..H-1 }
    used ← { d: {L: 0} for d in 0..H-1 }
    lastDay ← {}                       // courseId → 最后放置日
    sort C by priority desc
    S ← []; F ← []
    for course in C:
        L ← course.intensity
        prof ← profiles[L]
        placed ← []
        remaining ← course.duration
        startDay ← lastDay[course.id] == null ? 0 : lastDay[course.id] + prof.interval + 1
        for day = startDay; day < H and remaining > 0; day++:
            if used[day][L] ≥ prof.D_max: continue
            need   ← prof.chunk > 0 ? min(prof.chunk, remaining) : remaining
            capped ← min(need, prof.T_max, prof.D_max - used[day][L])
            block  ← TakeBlock(A[day], P[day], capped)
            if block == null and P[day] not empty:
                block ← TakeBlock(A[day], null, capped)   // 降级匹配
            if block == null: continue
            placed.append((course.id, day, block.start, block.end))
            remaining -= block.end - block.start
            lastDay[course.id] ← day
            used[day][L] += block.end - block.start
            if prof.interval > 0 and remaining > 0:
                day += prof.interval                     // 间隔重复跳天
        if remaining > 0:
            F.append((course.id, reason))
        else:
            S.appendAll(placed)
    sort S by (day, start)
    return (S, F)

function TakeBlock(A_day, peaks, need):        // 返回 (start,end) 或 null
    for seg in (peaks nonempty ? peaks : A_day):
        if seg.end - seg.start ≥ need:
            fit ← (seg.start, seg.start + need)
            RemoveRange(A_day, fit)
            return fit
    if peaks nonempty:
        for seg in A_day:                       // 峰值不足 → 普通片
            if seg.end - seg.start ≥ need:
                fit ← (seg.start, seg.start + need)
                RemoveRange(A_day, fit)
                return fit
    return null
```

### 4.5 复杂度分析

- 排序：$O(n\log n)$。
- 分配：每门课每天至多一次块匹配，每次匹配扫描当天区间 $O(S)$；总 $O(n\cdot H\cdot S)$（$n$ 课程数、$H$ 窗口天数、$S$ 每天时间片数）。
- 空间：$O(H\cdot S + n)$。
- 典型规模（$n\le 50$、$H\le 14$、$S=28$）下计算量约 $2\times10^4$ 次区间比较，移动端毫秒级完成。

### 4.6 与文献方法的对比

| 维度 | 本文 | LLVDF（价值密度调度） | DPTARA（动态优先级队列） |
|---|---|---|---|
| 排序键 | 综合优先系数 $P_i$（AHP+紧迫度） | 价值密度 | 动态优先级 |
| 资源模型 | 每日分片时间 + 强度档约束 | 计算资源 | 边缘节点 |
| 约束 | $T_{max}/D_{max}$/间隔重复/峰值时段 | 截止期 | 队列优先级 |
| 降级策略 | 峰值不足→普通片；窗口不足→保高弃低 | — | — |

改进点：将"价值密度"推广为"课程优先系数 + 强度档适配"二维匹配，并把认知负荷上限作为硬约束纳入贪心过程，避免高价值任务过度占用单日时间。

---

## 5. 实验设计建议

1. **正确性**：约束满足率（无冲突、全部在窗内、强度上限不越界）——已由单元测试覆盖。
2. **效率**：与基准（截止期排序、无强度约束）对比"高优先课程获得峰值时段的比例"、"日均学习时间利用率"。
3. **效果**：模拟 4 周，对比间隔重复（中等档）与集中学习在"间隔效应"下的预期遗忘曲线（引用 Cepeda 2006 的 retention 模型做理论对照）。
4. **消融**：去掉动态紧迫度权重（$w_{urg}$ 固定）对比排序变化；去掉峰值降级对比落位质量。

## 6. 参考文献（已核实真实可查）

1. Gao H, Wang X, Ma X, et al. Com-DDPG: A Multiagent Reinforcement Learning-based Offloading Strategy for Mobile Edge Computing. arXiv:2012.05105, 2020.（其第 III-B 节用 AHP 确定任务优先级）
2. Han M. Dynamic Adaptive Resource Scheduling for Phased Array Radar: Enhancing Efficiency through Synthesis Priorities and Pulse Interleaving. arXiv:2409.19201, 2024.（第 III-A 节：重要性+紧急性双因子动态优先级）
3. Saaty T L. The Analytic Hierarchy Process: Planning, Priority Setting, Resource Allocation. McGraw-Hill, 1980.
4. Saaty T L. A scaling method for priorities in hierarchical structures. Journal of Mathematical Psychology, 1977, 15(3): 234–281.
5. Cepeda N J, Pashler H, Vul E, et al. Distributed practice in verbal recall tasks: A review and quantitative synthesis. Psychological Bulletin, 2006, 132(3): 354–380.
6. 高媛, 黄真真, 李冀红, 黄荣怀. 智慧学习环境中的认知负荷问题.
7. 间隔学习研究综述. Hans 出版社.
