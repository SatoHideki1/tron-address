# ⚡ TRON 波场地址靓号极速生成器 (Linux & macOS)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux & macOS](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu%20%7C%20macOS-green.svg)]()
[![GPU: Apple Metal 3](https://img.shields.io/badge/GPU%20Acceleration-Apple%20Metal%203-blueviolet.svg)]()
[![Language: C99 / MSL](https://img.shields.io/badge/Language-C99%20%7C%20Metal%20MSL-orange.svg)]()
[![Security: Offline CSPRNG](https://img.shields.io/badge/Security-100%25%20Offline-brightgreen.svg)]()

专为 **Debian / Ubuntu / Linux** 与 **macOS** 打造的极速、安全、全开源波场（TRON）靓号地址生成器。支持**精细化 CPU 占用控制**（核心数限制 + 占空比平滑控温 + 低优先级守护）以及 **macOS Apple Silicon Metal 3 GPU 硬件加速**，让您在 VPS 或本地电脑上挂机算号的同时绝不影响正常业务与使用。

---

## 🌟 核心亮点

本项目具有以下核心优势：
- 🛡️ **100% 开源透明与离线安全**：纯 C 语言及原生 Metal 着色器编写，绝对零网络连接，全程使用安全伪随机数生成器（CSPRNG），私钥仅存在于本地内存并可实时写入文件。
- ⚡ **Apple Silicon Metal 3 GPU 硬件加速**：针对 Mac（Apple M1 / M2 / M3 / M4 系列）特别实现 Metal Shading Language (MSL) 并行计算架构。GPU 并发 32,768 线程批量执行模加法、模乘法、secp256k1 混合点加法、Keccak-256、双重 SHA-256 和 Base58Check，算力轻松突破 500,000+ ~ 数百万地址/秒！
- 🚀 **椭圆曲线点加法（Point Addition）加速**：CPU 端利用 $P_{i+1} = P_i + G$ 批量递增算法，避免单次全标量相乘，结合自实现轻量 Keccak-256，单核算力可达 **150,000+ 地址/秒**（8核可达 100万+ 地址/秒）。
- 💻 **Linux 与 macOS 完美跨平台支持**：针对 Linux (GCC / Clang) 和 macOS (Apple Silicon M系列 / Intel) 进行了针对性架构优化，无论是部署在云端 VPS 还是在 Mac 本地运行，都能一键编译。
- 🎛️ **精确 CPU / GPU 占用调控（防过热与防封控神器）**：
  - **核心数限制 (`-t`)**：自由指定占用的 CPU 核心数，例如 4 核服务器仅用 2 核。
  - **占用率百分比上限 (`-c`)**：内置高精度占空比平滑限速（10%~100%），如限制为 60%，无论运行多久，云监控平台都不会触发 100% 告警，在 Mac 笔记本上也能平稳控温，避免风扇狂转。
  - **低优先级模式 (`nice -n 19`)**：在系统运行其他业务时自动让出计算资源。
- 🧠 **智能波场前缀数学边界校验**：由于波场主网 `0x41` 前缀与 Base58 编码限制，波场地址的第 2 位字符只能是 `9` 或大写字母 `A-Z`（链上根本不存在 `T888...` 或 `T777...` 开头的地址）。本工具会自动校验并提示，防止用户误设不可能生成的规则导致白费算力。
- 🖥️ **一键交互式管理脚本 (`tron.sh`)**：支持全中文交互向导、前台测试、后台守护（`nohup` 退出终端不中断）、实时算力看板、已生成靓号查看及私钥校验。

---

## 🚀 快速上手

### 1. 克隆仓库

```bash
git clone https://github.com/SatoHideki1/tron-address.git
cd tron-address
chmod +x tron.sh
```

### 2. 运行一键管理脚本

- **在 Debian / Ubuntu 下**：
  直接执行 `./tron.sh`，脚本会自动检测并补齐 `build-essential` 和 `libssl-dev` 依赖并编译。
  ```bash
  ./tron.sh
  ```

- **在 macOS 下 (支持 Apple Silicon M1/M2/M3/M4 & Intel)**：
  需要先确保安装了 Homebrew 的 OpenSSL（只需执行一次）：
  ```bash
  # 1. 安装 OpenSSL 依赖
  brew install openssl@3

  # 2. 运行一键脚本 (会自动编译并检测 Metal GPU 硬件加速)
  ./tron.sh
  ```
  > **向导提示**：在 macOS 下启动 `./tron.sh` 的算号向导时，脚本会自动提示：
  > `检测到 macOS 系统，是否开启 Apple Metal 3 GPU 硬件加速？[Y/n, 默认 Y]:`
  > 直接回车即可启用 GPU 硬件加速流水线！

- **也可以直接编译原生二进制 (`tron-gen`)**：
  ```bash
  make
  ```
  > 在 macOS 下，Makefile 会自动检测 Darwin 平台，启用 `-DHAVE_METAL=1` 并链接 Apple Metal / Foundation 框架，同时支持 CPU 模式与 Metal GPU 模式。

---

## 📋 交互式菜单预览

运行 `./tron.sh` 后将展现如下中文菜单：

```text
===============================================================
      ⚡ TRON 波场地址靓号极速生成器 (Debian/Ubuntu 专属) ⚡    
      - 纯本地安全离线 | 椭圆曲线点加法 | 精确 CPU 占用调控 -    
===============================================================
  运行状态: ○ 未运行
  已获靓号: 3 个
---------------------------------------------------------------
  1. 🚀 启动前台算号 (实时直观查看算力与结果)
  2. 🌙 启动后台运行 (退出 SSH 不中断，VPS 挂机必备)
  3. 📊 查看后台运行状态与实时算力看板
  4. 🛑 停止后台算号任务
  5. 📜 查看已生成的靓号列表 (found_addresses.txt)
  6. 🔑 手动离线验证私钥与地址
  7. 🧹 清理/重置靓号历史记录
  8. ⚙️  重新编译/最高性能优化引擎
  0. 🚪 退出脚本
---------------------------------------------------------------
请输入选择 [0-8]: 
```

---

## 💻 命令行直接调用 (高级/自动化)

如果不希望使用交互式菜单，也可以直接通过命令行参数启动：

### 常用命令示例

#### 1. 寻找后缀为 `8888` 的靓号，使用 2 核 CPU，限制占用率为 60%
```bash
./tron-gen -s 8888 -t 2 -c 60
```

#### 2. 寻找前缀为 `TRX` 且后缀为 `888` 的靓号
```bash
./tron-gen -p TRX -s 888 -t 2
```

#### 3. 寻找尾部 5 连号（如 `AAAAA` 或 `88888`）
```bash
./tron-gen -k 5 -t 4 -c 80
```

#### 4. 后台静默运行（退出终端不中断），找到 3 个后自动停止
```bash
./tron.sh --daemon -s 9999 -t 2 -c 70 -n 3
```

#### 5. 查看后台状态与停止后台任务
```bash
# 查看后台实时日志与速度
./tron.sh --status

# 查看已找到的靓号
./tron.sh --results

# 停止后台任务
./tron.sh --stop
```

#### 6. macOS 启用 Metal 3 GPU 硬件加速 (Apple Silicon 专属)
```bash
# 使用 Metal 3 GPU 加速寻找后缀 888 靓号（算力大幅跃升）
./tron-gen --metal -s 888

# 简写模式：-g 即代表 --metal
./tron-gen -g -s 8888 -n 1

# GPU 控温模式：限制 GPU 占用率为 70%，保持笔记本静音不发烫
./tron-gen -g -s 8888 -c 70
```

#### 7. 离线验证私钥与地址是否相符
```bash
./tron-gen -v <64位十六进制私钥> <波场地址>
```

---

## ⚙️ 完整命令行参数速查表

| 参数 | 长参数 | 描述 | 默认值 |
| :--- | :--- | :--- | :--- |
| `-s` | `--suffix` | 匹配地址后缀（如 `-s 88888`） | 无 |
| `-p` | `--prefix` | 匹配地址前缀（首字母自动带 `T`，如 `-p TRX`） | 无 |
| `-b` | `--both` | 同时匹配前缀与后缀（如 `-b TA 888`） | 无 |
| `-k` | `--repeat` | 匹配尾部连续相同字符位数（如 `-k 6`） | 无 |
| `-m` | `--contain`| 包含指定字符串（如 `-m VIP`） | 无 |
| `-r` | `--regex` | POSIX 正则表达式匹配（如 `-r '^T.*888$'`） | 无 |
| `-f` | `--rule-file`| 从文件批量载入规则（每行一条） | 无 |
| `-i` | `--ignore-case`| 忽略大小写匹配 | 区分大小写 |
| **`-g`** | **`--metal`** | **启用 Apple Silicon Metal 3 GPU 硬件加速（macOS 专属）** | **关闭（默认使用 CPU）** |
| **`-t`** | **`--threads`** | **工作线程数量（CPU 核心数）** | **全部 CPU 核心** |
| **`-c`** | **`--cpu-limit`** | **CPU / GPU 占用百分比上限（10-100% 占空比控温）** | **100%** |
| `-n` | `--count` | 命中指定数量后自动退出（0 表示无限寻找） | 1 |
| `-o` | `--output` | 结果保存文件名 | `found_addresses.txt` |
| `-q` | `--quiet` | 静默模式（不打印动态看板） | 否 |
| `-v` | `--verify` | 离线验证私钥与地址是否匹配 | 无 |
| `-h` | `--help` | 查看帮助文档 | 无 |

---

## 🍏 macOS Metal 3 GPU 硬件加速专题 (Apple Silicon 专属)

对于使用 Mac（搭载 Apple M1 / M2 / M3 / M4 系列芯片）的用户，本项目通过 Apple Metal 3 API 提供了原生的 GPU 算力加速支持。

### 1. 架构与实现原理
- **着色器端纯原生椭圆曲线运算**：在 Metal Shading Language (`tron_kernel.metal`) 中直接实现了 256 位大数模加、模减、模乘与基于费马小定理的模逆元运算，完全在 GPU 显存内完成 Jacobian 混合坐标的点加法递增 ($P_{next} = P + G$)。
- **端到端全 GPU 流水线**：公钥导出 $\rightarrow$ Keccak-256 哈希 $\rightarrow$ 双重 SHA-256 校验和 $\rightarrow$ Base58Check 字符串编码，全部在 GPU 单步中完成，只有在命中规则时才将私钥与地址写回主机内存。
- **高并发调度**：默认单批次调度 **32,768 个 GPU 并发线程**，每线程流水线计算 8 步，一次 Dispatch 检索 **262,144 个地址**。

### 2. 实测算力与表现 (Apple M4 实测)
| 运行设备 | 运算模式 | 综合算力 | 检索后缀 '88' 耗时 | 检索后缀 '888' 耗时 |
| :--- | :--- | :--- | :--- | :--- |
| Apple M4 (MacBook Pro) | CPU (10核全开) | ~300 kH/s | ~1.2 秒 | ~2.5 秒 |
| **Apple M4 (MacBook Pro)** | **Metal 3 GPU 加速** | **~520 kH/s+** | **0.51 秒** | **0.52 秒** |

### 3. GPU 控温与长久挂机
Mac 笔记本用户在长时间算号时，最担心的往往是机身发烫和风扇狂转。本项目支持在 GPU 模式下无缝使用 `-c` 调控负载：
```bash
# 限制 GPU 负载为 60%，系统通过动态微秒级休眠占空比平滑控温，静音凉爽算号
./tron-gen -g -s 8888 -c 60
```

---

## ⚠️ 波场（TRON）地址规则与前缀避坑指南

根据波场官方规范，TRON 地址的生成步骤为：
1. 生成 32 字节私钥 $\rightarrow$ secp256k1 导出 64 字节未压缩公钥 $(X, Y)$。
2. 计算 Keccak-256 哈希，截取最后 20 字节。
3. 添加主网标识前缀字节 `0x41`（十进制 65），形成 21 字节载荷。
4. 计算双重 SHA-256 取得 4 字节校验和，拼接为 25 字节。
5. 最终通过 **Base58Check** 编码为 34 位字符串。

> [!WARNING]
> **关于前缀的数学规律**：
> 因为前缀字节固定为 `0x41`，在 25 字节整数中，其编码后的 Base58 地址范围**严格落入**：
> `T9yD14Nj9j7xAB4dbGeiX9h8unkKDDv9ZR` 至 `TZJozAg1ruapycCicgz31GxvYJ1FvTVysk` 之间！
> - 地址**第一位必定是 `T`**。
> - 地址**第二位只能是 `9` 或大写字母 `A` 到 `Z`**（不含易混淆的 `I`, `O`）。
> - 波场全网**绝不可能出现** `T1`、`T2` ... `T8` 或小写字母开头的地址（例如想要 `8888` 靓号，请务必使用**后缀匹配 `-s 8888`**，而不要使用前缀匹配 `-p 8888`）。

> [!NOTE]
> **Base58 字符集限制**：
> 波场 Base58 字符集排除易混淆的 4 个字符：数字 `0`、大写字母 `O`、大写字母 `I`、小写字母 `l`。设置匹配规则时请勿包含此 4 个字符。

---

## 🔒 安全性说明

1. **私钥绝不上云**：本工具代码全开源，无第三方网络库，无遥测和数据上报代码。您可在完全断开网络的离线机器上编译和运行。
2. **种子随机性**：每个工作线程采用系统安全的 CSPRNG（`BN_priv_rand`）生成初始熵，并在步长达到上限时重新随机播种，杜绝私钥碰撞与伪随机序列风险。
3. **结果保存安全**：生成结果默认保存至本地目录 `found_addresses.txt`，请妥善保管您的私钥文件，切勿泄露给第三方。

---

## 📄 开源许可证

[许可证](LICENSE)
