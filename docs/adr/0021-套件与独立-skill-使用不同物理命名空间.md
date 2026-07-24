# 套件与独立 Skill 使用不同物理命名空间

中央库把套件内容存放在 `Library/Suites/<套件名称>/<Skill>`，把独立 Skill 存放在 `Library/Skills/<Skill>`，稳定分发入口使用单独的内部位置。相比把套件和独立 Skill 混放在同一根目录，这避免套件名称与独立 Skill 名称产生路径冲突并简化扫描，同时仍能在 Finder 中看到“套件/多个 Skill”的结构；代价是独立 Skill 和套件 Skill 的路径层级不同。
