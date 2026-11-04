# 已验收发布文件

本目录提供当前配套文件，直接使用无需重新编译：

- `fpga/neo_guitar_touch_game.fs`：2026-11-02双接口位流，保持已验收音色、四声部/32模型状态、LCD/触控180°、姿态控制与1/2/3默认曲库。
- `fpga/verified_release_20261102.zip`：同一位流与原构建/资源/时序报告，保持原ZIP字节。
- `fpga/source_code_140_files.zip`：对应最终综合输入，含RTL、头文件、CST、SDC、MEM与GPRJ；不含README/报告/FS。
- `android/xinxian_jdy23_0.3.0.apk`：Android8.0+，JDY-23蓝牙传谱。
- `windows/FPGA_Guitar_Uploader_1.2.0.zip`：Windows便携版，DEBUG-USB2串口传谱，解压运行。
- `windows/FPGA_Guitar_Uploader_1.2.0_licensed.zip`：推荐的许可补充版，保留上述原包所有成员字节，新增许可及带许可对应源码。
- `license_notices_20261104.zip`：原始验收文件的独立许可补充包。

原始验收文件保持原字节，许可补充版只增加说明与源码许可，没有重新构建程序。校验值见 [SHA256SUMS](SHA256SUMS)，构建输入见 [source_manifest.json](fpga/source_manifest.json)。具体上板和软件使用见[仓库README](../README.md)。

原始包保持不变；2026-11-04新增许可补充包，未重新编译或替换程序。原创程序按组件授权，嵌入曲谱、字库与第三方IP不由此重授权，详见[发布许可范围](LICENSING.md)。
