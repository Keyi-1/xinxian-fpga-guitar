# NEO 双 PCB 全链路音频验证

打开 `neo_full_chain_audio_test.gprj`，Top 为 `neo_full_chain_audio_test_top`。
器件：`GW5AT-LV60PG484AC1/I0`，Version B。

矩阵只选品，MCP3208 CH0～CH3 才触发四个声部；保留已实物验证的自然衰减、
动态左右分离、PT8211 与功放常开。当前采用固定力度 2。

完整接线、参数和上板步骤见 [全链路说明](../../docs/NEO_FULL_CHAIN_AUDIO_TEST.md)。
构建：在本目录用 Gowin `gw_sh.exe build.tcl`，或通过 IDE 综合和布局布线。
仿真：`.\run_sim.ps1`，可传 `-ModelSimBin` 指定已安装的 ModelSim。

已生成位流：`impl/pnr/neo_full_chain_audio_test.fs`。用户已确认双板实物测试结果理想。
此成功工程保留为独立基线；正式 RTL 主入口见 [主工程同步](../../docs/MAIN_ENGINE_SYNC.md)。
