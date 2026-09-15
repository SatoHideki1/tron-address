#!/usr/bin/env bash
#=============================================================================
# TRON 波场地址靓号极速生成器 - Debian/Ubuntu 一键管理与运行脚本
# 特性: 纯本地安全离线 | 椭圆曲线点加法极速运算 | 精确 CPU 占用调控 | 前后台守护
#=============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN_NAME="tron-gen"
PID_FILE=".tron.pid"
LOG_FILE="tron_daemon.log"
RESULT_FILE="found_addresses.txt"

# Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

# Print banner
print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}===============================================================${RESET}"
    echo -e "${WHITE}      ⚡ TRON 波场地址靓号极速生成器 (Debian/Ubuntu 专属) ⚡    ${RESET}"
    echo -e "${YELLOW}      - 纯本地安全离线 | 椭圆曲线点加法 | 精确 CPU 占用调控 -    ${RESET}"
    echo -e "${CYAN}===============================================================${RESET}"
}

# Check and install dependencies on Debian/Ubuntu
check_environment() {
    local need_install=0
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        need_install=1
    fi

    # Check for OpenSSL development headers
    if [[ ! -f /usr/include/openssl/ec.h ]] && [[ ! -f /usr/local/include/openssl/ec.h ]] && [[ ! -d /opt/homebrew/opt/openssl@3/include ]]; then
        need_install=1
    fi

    if [[ $need_install -eq 1 ]]; then
        echo -e "${YELLOW}[!] 检测到系统缺少编译依赖 (gcc / make / libssl-dev)...${RESET}"
        if [[ $(id -u) -eq 0 ]]; then
            echo -e "${CYAN}[*] 正在通过 apt 自动安装依赖环境...${RESET}"
            apt-get update && apt-get install -y build-essential libssl-dev
        elif command -v sudo >/dev/null 2>&1; then
            echo -e "${CYAN}[*] 正在通过 sudo apt 自动安装依赖环境...${RESET}"
            sudo apt-get update && sudo apt-get install -y build-essential libssl-dev
        else
            echo -e "${RED}[ERROR] 缺少编译环境，请以 root 身份运行: apt update && apt install -y build-essential libssl-dev${RESET}"
            exit 1
        fi
    fi
}

# Compile engine if binary doesn't exist
ensure_binary() {
    if [[ ! -f "$BIN_NAME" ]]; then
        echo -e "${CYAN}[*] 正在编译波场靓号生成引擎...${RESET}"
        check_environment
        make -j"$(get_cpu_cores)"
        echo -e "${GREEN}[✓] 引擎编译完成！${RESET}\n"
    fi
}

# Get CPU cores
get_cpu_cores() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 1
    fi
}

# Check if daemon is running
is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Interactive configuration wizard
run_wizard() {
    local is_daemon=$1
    local total_cores
    total_cores=$(get_cpu_cores)

    echo -e "${GREEN}>>> 第一步: 选择靓号匹配规则${RESET}"
    echo -e "  ${WHITE}1)${RESET} 后缀匹配 (如: 888888, 6666, TRX, USDT) [最常用]"
    echo -e "  ${WHITE}2)${RESET} 前缀匹配 (如: TRX, VIP, 999 - 首字母自动带 T)"
    echo -e "  ${WHITE}3)${RESET} 前缀 + 后缀双拼 (如: 前缀 TA + 后缀 888)"
    echo -e "  ${WHITE}4)${RESET} 尾数连续相同靓号 (如: 5连号/6连号/7连号)"
    echo -e "  ${WHITE}5)${RESET} 包含特定字符 (如: 包含 VIP)"
    echo -e "  ${WHITE}6)${RESET} 正则表达式匹配"
    read -r -p "请输入选项 [1-6, 默认 1]: " rule_choice
    rule_choice=${rule_choice:-1}

    local rule_args=""
    case "$rule_choice" in
        1)
            while true; do
                read -r -p "请输入期望的地址后缀 (例 88888): " suffix_val
                if [[ -n "$suffix_val" ]]; then
                    rule_args="-s $suffix_val"
                    break
                fi
                echo -e "${RED}后缀不能为空，请重新输入！${RESET}"
            done
            ;;
        2)
            while true; do
                read -r -p "请输入期望的前缀 (例 TRX 或 VIP，波场链不存在 T8/T7 开头): " prefix_val
                if [[ -n "$prefix_val" ]]; then
                    rule_args="-p $prefix_val"
                    break
                fi
                echo -e "${RED}前缀不能为空，请重新输入！${RESET}"
            done
            ;;
        3)
            read -r -p "请输入期望的前缀 (例 TA): " prefix_val
            read -r -p "请输入期望的后缀 (例 888): " suffix_val
            rule_args="-p $prefix_val -s $suffix_val"
            ;;
        4)
            read -r -p "请输入尾数连续相同位数 [3-10, 默认 5]: " repeat_val
            repeat_val=${repeat_val:-5}
            rule_args="-k $repeat_val"
            ;;
        5)
            read -r -p "请输入要包含的字符串: " contain_val
            rule_args="-m $contain_val"
            ;;
        6)
            read -r -p "请输入正则表达式: " regex_val
            rule_args="-r $regex_val"
            ;;
        *)
            rule_args="-s 8888"
            ;;
    esac

    echo ""
    echo -e "${GREEN}>>> 第二步: 大小写敏感设置${RESET}"
    read -r -p "是否区分大小写？(y=区分，n=忽略大小写) [y/N, 默认 y]: " case_choice
    case_choice=${case_choice:-y}
    if [[ "$case_choice" == "n" || "$case_choice" == "N" ]]; then
        rule_args="$rule_args -i"
    fi

    echo ""
    echo -e "${GREEN}>>> 第三步: CPU 核心数与占用率调控 (核心特性)${RESET}"
    echo -e "  当前服务器检测到共 ${CYAN}${total_cores}${RESET} 个 CPU 核心。"
    read -r -p "请设置使用的 CPU 线程/核心数 [1-${total_cores}, 默认 ${total_cores}]: " threads_val
    threads_val=${threads_val:-$total_cores}

    echo -e "  CPU 占用率上限调控 (通过占空比平滑控温，防止 VPS 满载告警或耗尽积分):"
    read -r -p "请设置 CPU 占用率上限百分比 (10-100) [默认 100]: " cpu_val
    cpu_val=${cpu_val:-100}

    read -r -p "是否以低优先级 (nice -n 19) 运行？(不抢占系统其他网站/数据库服务) [Y/n, 默认 Y]: " nice_choice
    nice_choice=${nice_choice:-y}

    echo ""
    echo -e "${GREEN}>>> 第四步: 寻找目标数量${RESET}"
    read -r -p "找到多少个符合的靓号后停止？(0表示持续寻找) [默认 1]: " count_val
    count_val=${count_val:-1}

    local nice_prefix=""
    if [[ "$nice_choice" == "y" || "$nice_choice" == "Y" ]]; then
        nice_prefix="nice -n 19"
    fi

    local full_cmd="$nice_prefix ./$BIN_NAME $rule_args -t $threads_val -c $cpu_val -n $count_val -o $RESULT_FILE"

    echo ""
    echo -e "${CYAN}---------------------------------------------------------------${RESET}"
    echo -e "${WHITE}即将执行命令:${RESET} $full_cmd"
    echo -e "${CYAN}---------------------------------------------------------------${RESET}"

    if [[ $is_daemon -eq 1 ]]; then
        # Daemon mode
        echo -e "${YELLOW}[*] 正在启动后台守护进程...${RESET}"
        nohup $full_cmd > "$LOG_FILE" 2>&1 &
        local new_pid=$!
        echo "$new_pid" > "$PID_FILE"
        sleep 1
        if kill -0 "$new_pid" 2>/dev/null; then
            echo -e "${GREEN}[✓] 后台算号任务已成功启动！PID: ${new_pid}${RESET}"
            echo -e "  - 即使关闭 SSH 终端窗口，程序仍会在服务器后台持续算号。"
            echo -e "  - 可随时在主菜单输入 ${YELLOW}3${RESET} 查看实时速度，或输入 ${YELLOW}4${RESET} 停止任务。"
            echo -e "  - 命中靓号将自动保存到: ${CYAN}${RESULT_FILE}${RESET}"
        else
            echo -e "${RED}[ERROR] 后台启动失败，请查看日志: cat $LOG_FILE${RESET}"
        fi
    else
        # Foreground mode
        echo -e "${GREEN}[*] 正在前台启动... (按 Ctrl+C 可随时安全退出)${RESET}\n"
        exec $full_cmd
    fi
}

# View daemon status
view_status() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo -e "${GREEN}[●] 后台算号程序正在正常运行 (PID: ${pid})${RESET}\n"

        if command -v ps >/dev/null 2>&1; then
            echo -e "${WHITE}进程资源占用详情:${RESET}"
            ps -p "$pid" -o pid,%cpu,%mem,etime,command 2>/dev/null || true
            echo ""
        fi

        echo -e "${CYAN}=== 最近 15 行实时运行日志 (tail -n 15 $LOG_FILE) ===${RESET}"
        if [[ -f "$LOG_FILE" ]]; then
            tail -n 15 "$LOG_FILE"
        else
            echo -e "${YELLOW}(暂无日志输出)${RESET}"
        fi
        echo -e "${CYAN}======================================================${RESET}\n"
        echo -e "💡 提示: 您也可以使用命令 ${YELLOW}tail -f $LOG_FILE${RESET} 持续跟踪实时速率。"
    else
        echo -e "${YELLOW}[○] 当前没有后台算号任务在运行。${RESET}"
        if [[ -f "$LOG_FILE" ]]; then
            echo -e "\n最后一次运行日志结尾:"
            tail -n 10 "$LOG_FILE"
        fi
    fi
}

# Stop daemon
stop_daemon() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo -e "${YELLOW}[*] 正在停止后台算号任务 (PID: ${pid})...${RESET}"
        kill -SIGINT "$pid" 2>/dev/null || true
        for _ in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.5
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -SIGKILL "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
        echo -e "${GREEN}[✓] 后台算号任务已安全停止！${RESET}"
    else
        echo -e "${YELLOW}[!] 当前没有正在运行的后台任务。${RESET}"
        rm -f "$PID_FILE"
    fi
}

# View found results
view_results() {
    if [[ -f "$RESULT_FILE" ]] && [[ -s "$RESULT_FILE" ]]; then
        local count
        count=$(wc -l < "$RESULT_FILE" | tr -d ' ')
        echo -e "${GREEN}=== 已生成的波场 (TRON) 靓号列表 (共 ${count} 个) ===${RESET}\n"
        cat "$RESULT_FILE"
        echo -e "\n${GREEN}===================================================${RESET}"
        echo -e "📁 结果完整文件路径: ${CYAN}${SCRIPT_DIR}/${RESULT_FILE}${RESET}"
    else
        echo -e "${YELLOW}[!] 暂未找到任何已生成的靓号记录。${RESET}"
    fi
}

# Clean results
clean_results() {
    if [[ -f "$RESULT_FILE" ]]; then
        read -r -p "确定要清空靓号记录文件 ($RESULT_FILE) 吗？[y/N]: " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            rm -f "$RESULT_FILE"
            echo -e "${GREEN}[✓] 已清空靓号记录。${RESET}"
        else
            echo -e "${YELLOW}[*] 已取消。${RESET}"
        fi
    else
        echo -e "${YELLOW}[!] 文件不存在，无需清理。${RESET}"
    fi
}

# Verify key and address
verify_pair() {
    echo -e "${CYAN}=== 离线验证私钥与波场地址匹配关系 ===${RESET}"
    read -r -p "请输入 64 位十六进制私钥: " priv
    read -r -p "请输入波场地址 (以T开头): " addr
    if [[ -n "$priv" && -n "$addr" ]]; then
        ./$BIN_NAME -v "$priv" "$addr"
    else
        echo -e "${RED}私钥和地址均不能为空！${RESET}"
    fi
}

# Interactive Main Menu
menu() {
    ensure_binary
    while true; do
        print_banner
        if is_running; then
            echo -e "  运行状态: ${GREEN}● 正在后台运行 (PID: $(cat "$PID_FILE"))${RESET}"
        else
            echo -e "  运行状态: ${YELLOW}○ 未运行${RESET}"
        fi
        if [[ -f "$RESULT_FILE" ]]; then
            local fc
            fc=$(wc -l < "$RESULT_FILE" | tr -d ' ')
            echo -e "  已获靓号: ${GREEN}${fc} 个${RESET}"
        fi
        echo -e "${CYAN}---------------------------------------------------------------${RESET}"
        echo -e "  ${WHITE}1.${RESET} 🚀 启动前台算号 (实时直观查看算力与结果)"
        echo -e "  ${WHITE}2.${RESET} 🌙 启动后台运行 (退出 SSH 不中断，VPS 挂机必备)"
        echo -e "  ${WHITE}3.${RESET} 📊 查看后台运行状态与实时算力看板"
        echo -e "  ${WHITE}4.${RESET} 🛑 停止后台算号任务"
        echo -e "  ${WHITE}5.${RESET} 📜 查看已生成的靓号列表 (${RESULT_FILE})"
        echo -e "  ${WHITE}6.${RESET} 🔑 手动离线验证私钥与地址"
        echo -e "  ${WHITE}7.${RESET} 🧹 清理/重置靓号历史记录"
        echo -e "  ${WHITE}8.${RESET} ⚙️  重新编译/最高性能优化引擎"
        echo -e "  ${WHITE}0.${RESET} 🚪 退出脚本"
        echo -e "${CYAN}---------------------------------------------------------------${RESET}"
        read -r -p "请输入选择 [0-8]: " choice

        case "$choice" in
            1)
                run_wizard 0
                ;;
            2)
                if is_running; then
                    echo -e "${RED}[!] 后台已有算号任务在运行中 (PID: $(cat "$PID_FILE"))！${RESET}"
                    echo -e "请先在主菜单输入 4 停止当前任务，或输入 3 查看状态。"
                else
                    run_wizard 1
                fi
                ;;
            3)
                view_status
                ;;
            4)
                stop_daemon
                ;;
            5)
                view_results
                ;;
            6)
                verify_pair
                ;;
            7)
                clean_results
                ;;
            8)
                echo -e "${CYAN}[*] 正在重新编译引擎...${RESET}"
                make clean && make -j"$(get_cpu_cores)"
                echo -e "${GREEN}[✓] 重新编译成功！${RESET}"
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入！${RESET}"
                ;;
        esac

        echo ""
        read -r -p "按回车键返回主菜单..." _
    done
}

# Support direct command-line arguments:
# e.g.: ./tron.sh --daemon -s 8888 -t 2 -c 50
if [[ $# -gt 0 ]]; then
    ensure_binary
    if [[ "$1" == "--daemon" || "$1" == "-d" ]]; then
        shift
        if is_running; then
            echo -e "${RED}后台已有任务在运行 (PID: $(cat "$PID_FILE"))！${RESET}"
            exit 1
        fi
        nohup ./$BIN_NAME "$@" > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo -e "${GREEN}已启动后台算号任务，PID: $!${RESET}"
        exit 0
    elif [[ "$1" == "--status" ]]; then
        view_status
        exit 0
    elif [[ "$1" == "--stop" ]]; then
        stop_daemon
        exit 0
    elif [[ "$1" == "--results" ]]; then
        view_results
        exit 0
    else
        exec ./$BIN_NAME "$@"
    fi
fi

# Otherwise show interactive menu
menu
