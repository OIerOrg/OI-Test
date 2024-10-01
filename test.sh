#!/bin/bash

# test.sh: 自动编译和运行 C/C++/Java 程序的自动化工具，支持单组或多组样例，自动识别编程语言，并在控制台输出结果

# ANSI 颜色代码（优化后的配色）
RED='\033[1;31m'     # 亮红色
GREEN='\033[1;32m'   # 亮绿色
BLUE='\033[1;34m'    # 亮蓝色
YELLOW='\033[1;33m'  # 亮黄色
MAGENTA='\033[1;35m' # 亮紫色
CYAN='\033[1;36m'    # 亮青色
NC='\033[0m'         # 无颜色

# 全局变量
AC_COUNT=0
WA_COUNT=0
TLE_COUNT=0
MLE_COUNT=0
RE_COUNT=0
UKE_COUNT=0
COMPILE_ERROR=false
LANGUAGE=""
CODE_FILE=""
EXEC_CMD=""
TIME_CMD="/usr/bin/time"
TIME_FORMAT="elapsed=%e\nmaxmem=%M"
TOTAL_TESTS=0
OUTPUT_FILE="out.txt"
TEST_DIR="./test_cases"
SINGLE_CASE=false
BASE_NAME="main" # 默认基名称为 main
ESTIMATED_SCORE=0
LOG_FILE="test_log.txt"
USE_DOCKER=false
DOCKER_IMAGE=""
CONTAINER_NAME="code_executor"

# 配置文件路径
CONFIG_FILE=".test_sh_config"

# 存储测试结果的数组
declare -a TEST_RESULTS

# 显示帮助信息
show_help() {
    echo -e "${BLUE}用法: test.sh [选项]${NC}"
    echo
    echo "自动编译和运行 C/C++/Java 程序的自动化工具。"
    echo
    echo "功能包括："
    echo "  - 多语言支持（C、C++、Java）"
    echo "  - 单组或多组测试用例管理"
    echo "  - 自动识别编程语言"
    echo "  - 编译和运行测试用例"
    echo "  - 结果比较和控制台输出"
    echo "  - 自动清理生成文件"
    echo "  - 美化输出"
    echo "  - 预估分数"
    echo "  - Docker 支持（可选）"
    echo
    echo "选项："
    echo "  -h, --help    显示帮助信息"
    echo
    echo "使用方法："
    echo "  直接运行脚本并按照提示操作： ./test.sh"
    echo
    echo "示例："
    echo "  ./test.sh"
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}Docker 未安装。正在安装 Docker...${NC}"
        install_docker
    else
        echo -e "${GREEN}已检测到 Docker 已安装。${NC}"
    fi
}

# 安装 Docker（适用于 Ubuntu/Debian 系统）
install_docker() {
    # 更新包列表，隐藏输出
    sudo apt-get update -y >/dev/null 2>&1

    # 安装必要的包，隐藏输出
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release >/dev/null 2>&1

    # 添加 Docker 的官方 GPG 密钥，隐藏输出
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg >/dev/null 2>&1

    # 设置稳定版仓库，隐藏输出
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    # 更新包列表，隐藏输出
    sudo apt-get update -y >/dev/null 2>&1

    # 安装 Docker Engine，隐藏输出
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1

    # 启动 Docker，隐藏输出
    sudo systemctl start docker >/dev/null 2>&1
    sudo systemctl enable docker >/dev/null 2>&1

    # 验证 Docker 安装
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}Docker 安装成功。${NC}"
    else
        echo -e "${RED}Docker 安装失败，请手动安装。${NC}"
        exit 1
    fi
}

# 设置 Docker 镜像
setup_docker_image() {
    case "$LANGUAGE" in
    C)
        DOCKER_IMAGE="gcc:latest"
        ;;
    "C++")
        DOCKER_IMAGE="gcc:latest"
        ;;
    Java)
        DOCKER_IMAGE="openjdk:latest"
        ;;
    *)
        echo -e "${RED}错误: 不支持的编程语言 '$LANGUAGE'。${NC}"
        exit 1
        ;;
    esac
}

# 拉取 Docker 镜像
pull_docker_image() {
    echo -e "${BLUE}正在拉取 Docker 镜像 '${DOCKER_IMAGE}'...${NC}"
    sudo docker pull "$DOCKER_IMAGE" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误: 拉取 Docker 镜像 '$DOCKER_IMAGE' 失败。${NC}"
        exit 1
    else
        echo -e "${GREEN}成功拉取 Docker 镜像 '${DOCKER_IMAGE}'。${NC}"
    fi
}

# 启动 Docker 容器
start_docker_container() {
    echo -e "${BLUE}正在启动 Docker 容器 '${CONTAINER_NAME}'...${NC}"
    sudo docker run -d --name "$CONTAINER_NAME" --rm -v "$(pwd)":/workspace -w /workspace "$DOCKER_IMAGE" tail -f /dev/null >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误: 启动 Docker 容器 '$CONTAINER_NAME' 失败。${NC}"
        exit 1
    else
        echo -e "${GREEN}成功启动 Docker 容器 '${CONTAINER_NAME}'。${NC}"
    fi

    # 安装必要的工具（time 和 timeout），隐藏输出
    sudo docker exec "$CONTAINER_NAME" apt-get update -y >/dev/null 2>&1
    sudo docker exec "$CONTAINER_NAME" apt-get install -y time coreutils >/dev/null 2>&1
}

# 停止 Docker 容器
stop_docker_container() {
    echo -e "${BLUE}正在停止 Docker 容器 '${CONTAINER_NAME}'...${NC}"
    sudo docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}成功停止 Docker 容器 '${CONTAINER_NAME}'。${NC}"
    fi
}

# 执行命令在 Docker 容器中
docker_exec() {
    local cmd="$1"
    sudo docker exec "$CONTAINER_NAME" bash -c "$cmd"
}

# 自动识别编程语言
identify_language() {
    local base_name="$1"
    local extensions=("c" "cpp" "java")
    local matches=()

    for ext in "${extensions[@]}"; do
        if [[ -f "${base_name}.${ext}" ]]; then
            matches+=("${base_name}.${ext}")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo -e "${RED}错误: 未找到与基名称 '${base_name}' 匹配的源代码文件（.c, .cpp, .java）。${NC}"
        exit 1
    elif [[ ${#matches[@]} -eq 1 ]]; then
        CODE_FILE="${matches[0]}"
        echo -e "${GREEN}已自动识别源代码文件为 '${CODE_FILE}'。${NC}"
    else
        echo -e "${CYAN}检测到多个匹配的源代码文件:${NC}"
        for i in "${!matches[@]}"; do
            echo "$((i + 1))) ${matches[$i]}"
        done
        while true; do
            read -rp "请输入要使用的文件编号（1-${#matches[@]}) [默认: 1]: " choice
            choice=${choice:-1}
            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && ((choice >= 1 && choice <= ${#matches[@]})); then
                CODE_FILE="${matches[$((choice - 1))]}"
                echo -e "${GREEN}已选择 '${CODE_FILE}'。${NC}"
                break
            else
                echo -e "${RED}无效的选择，请重新输入.${NC}"
            fi
        done
    fi

    # 识别编程语言
    case "${CODE_FILE##*.}" in
    c)
        LANGUAGE="C"
        ;;
    cpp)
        LANGUAGE="C++"
        ;;
    java)
        LANGUAGE="Java"
        ;;
    *)
        echo -e "${RED}错误: 不支持的文件扩展名 '.${CODE_FILE##*.}'。${NC}"
        exit 1
        ;;
    esac
}

# 用户交互输入
get_user_input() {
    # 询问是否使用 Docker
    echo -e "${CYAN}是否启用 Docker 支持？（Y/N）：${NC}"
    read -rp "输入选择 [默认: N]: " docker_choice
    docker_choice=${docker_choice:-N}
    case "$docker_choice" in
    [Yy]*)
        USE_DOCKER=true
        ;;
    [Nn]* | "")
        USE_DOCKER=false
        ;;
    *)
        echo -e "${RED}无效的选择，默认不使用 Docker。${NC}"
        USE_DOCKER=false
        ;;
    esac

    echo -e "${BLUE}请输入源代码的基名称（不含扩展名，如 main）：${NC}"
    read -rp "基名称 [默认: main]: " BASE_NAME
    BASE_NAME=${BASE_NAME:-"main"} # 默认基名称为 main
    if [[ -z "$BASE_NAME" ]]; then
        echo -e "${RED}错误: 基名称不能为空.${NC}"
        exit 1
    fi

    identify_language "$BASE_NAME"

    echo -e "${YELLOW}请选择样例类型:${NC}"
    echo "1) 单组样例"
    echo "2) 多组样例"
    read -rp "输入选项（1/2） [默认: 2]: " SAMPLE_TYPE
    SAMPLE_TYPE=${SAMPLE_TYPE:-2}

    case "$SAMPLE_TYPE" in
    1)
        SINGLE_CASE=true
        ;;
    2)
        SINGLE_CASE=false
        ;;
    *)
        echo -e "${RED}无效的选项.${NC}"
        exit 1
        ;;
    esac

    if [[ "$SINGLE_CASE" == true ]]; then
        echo -e "${MAGENTA}请输入单组测试用例的输入文件路径（如 in.txt） [默认: in.txt]:${NC}"
        read -rp "输入文件: " SINGLE_INPUT
        SINGLE_INPUT=${SINGLE_INPUT:-in.txt}
        if [[ ! -f "$SINGLE_INPUT" ]]; then
            echo -e "${RED}错误: 输入文件 '$SINGLE_INPUT' 不存在.${NC}"
            exit 1
        fi

        echo -e "${MAGENTA}请输入单组测试用例的答案文件路径（如 ans.txt） [默认: ans.txt]:${NC}"
        read -rp "答案文件: " SINGLE_ANSWER
        SINGLE_ANSWER=${SINGLE_ANSWER:-ans.txt}
        if [[ ! -f "$SINGLE_ANSWER" ]]; then
            echo -e "${RED}错误: 答案文件 '$SINGLE_ANSWER' 不存在.${NC}"
            exit 1
        fi
    else
        echo -e "${MAGENTA}请输入测试用例目录路径（默认: ./test_cases）：${NC}"
        read -rp "测试用例目录: " TEST_DIR
        TEST_DIR=${TEST_DIR:-./test_cases}
        if [[ ! -d "$TEST_DIR" ]]; then
            echo -e "${RED}错误: 测试用例目录 '$TEST_DIR' 不存在.${NC}"
            exit 1
        fi
    fi

    # 设置时间限制和内存限制
    echo -e "${CYAN}设置时间限制（秒，默认: 1）：${NC}"
    read -rp "时间限制: " TIME_LIMIT
    TIME_LIMIT=${TIME_LIMIT:-1}

    echo -e "${CYAN}设置内存限制（KB，默认: 65536）：${NC}"
    read -rp "内存限制: " MEMORY_LIMIT
    MEMORY_LIMIT=${MEMORY_LIMIT:-65536}
}

# 加载配置（不包括 USE_DOCKER）
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# 保存配置（不包括 USE_DOCKER）
save_config() {
    cat >"$CONFIG_FILE" <<EOL
BASE_NAME="$BASE_NAME"
SINGLE_CASE="$SINGLE_CASE"
TEST_DIR="$TEST_DIR"
SINGLE_INPUT="$SINGLE_INPUT"
SINGLE_ANSWER="$SINGLE_ANSWER"
TIME_LIMIT="$TIME_LIMIT"
MEMORY_LIMIT="$MEMORY_LIMIT"
LANGUAGE="$LANGUAGE"
CODE_FILE="$CODE_FILE"
EXEC_CMD="$EXEC_CMD"
EOL
}

# 获取状态的文本颜色
get_status_color() {
    case "$1" in
    AC)
        echo -e "${GREEN}"
        ;;
    WA | MLE | RE)
        echo -e "${RED}"
        ;;
    TLE | UKE)
        echo -e "${YELLOW}"
        ;;
    *)
        echo -e "${NC}"
        ;;
    esac
}

# 计算预估分数
calculate_score() {
    if [[ "$TOTAL_TESTS" -eq 0 ]]; then
        ESTIMATED_SCORE=0
    else
        # 预估总分为 100 分
        ESTIMATED_SCORE=$((AC_COUNT * 100 / TOTAL_TESTS))
    fi
}

# 显示进度条（单行更新）
show_progress_bar() {
    local progress=$1
    local total=$2
    local bar_length=50

    # 强制 progress 和 total 为十进制，避免前导零导致的八进制解释
    local progress_decimal=$((10#$progress))
    local total_decimal=$((10#$total))

    local filled_length=$((progress_decimal * bar_length / total_decimal))
    local empty_length=$((bar_length - filled_length))
    local percent=$((progress_decimal * 100 / total_decimal))

    # 使用 ASCII 字符提升兼容性
    local filled_bar=$(printf "%0.s#" $(seq 1 $filled_length))
    local empty_bar=$(printf "%0.s-" $(seq 1 $empty_length))

    # 为不同的进度部分添加颜色
    if [ "$percent" -lt 50 ]; then
        color="$YELLOW"
    elif [ "$percent" -lt 80 ]; then
        color="$MAGENTA"
    else
        color="$GREEN"
    fi

    # 打印进度条，使用 \r 回到行首覆盖旧进度条
    printf "\r${color}[%s%s] %d%% (${progress_decimal}/${total_decimal})${NC}" "$filled_bar" "$empty_bar" "$percent"
}

# 执行单组测试用例并记录结果
run_single_test() {
    echo -e "${BLUE}开始执行单组测试用例...${NC}"

    TEST_NUM=1
    INPUT_FILE="$SINGLE_INPUT"   # 使用相对路径
    ANSWER_FILE="$SINGLE_ANSWER" # 使用相对路径
    CURRENT_OUTPUT_FILE="$OUTPUT_FILE"

    # 定义时间和内存信息文件
    TIME_MEM_FILE="time_output_single.txt"

    # 初始化进度条（单一测试，显示 0%）
    show_progress_bar 0 1

    # 执行程序并限制时间和内存，捕获时间和内存使用
    execute_program "$INPUT_FILE" "$CURRENT_OUTPUT_FILE" "$TIME_MEM_FILE"
    EXEC_STATUS=$?

    # 更新进度条到 100%
    show_progress_bar 1 1
    echo # 换行

    # 读取时间和内存信息
    if [[ -f "$TIME_MEM_FILE" ]]; then
        ELAPSED_TIME=$(grep "elapsed=" "$TIME_MEM_FILE" | cut -d'=' -f2)
        MAX_MEM=$(grep "maxmem=" "$TIME_MEM_FILE" | cut -d'=' -f2)
        rm -f "$TIME_MEM_FILE"
    else
        ELAPSED_TIME="0.00"
        MAX_MEM="0"
    fi

    # 处理执行状态
    if [[ $EXEC_STATUS -eq 124 ]]; then
        RESULT="TLE"
        TLE_COUNT=$((TLE_COUNT + 1))
    elif [[ $EXEC_STATUS -eq 137 ]]; then
        RESULT="MLE"
        MLE_COUNT=$((MLE_COUNT + 1))
    elif [[ $EXEC_STATUS -ne 0 ]]; then
        RESULT="RE"
        RE_COUNT=$((RE_COUNT + 1))
    else
        # 比较输出
        if diff -w "$CURRENT_OUTPUT_FILE" "$ANSWER_FILE" >/dev/null; then
            RESULT="AC"
            AC_COUNT=$((AC_COUNT + 1))
        else
            RESULT="WA"
            WA_COUNT=$((WA_COUNT + 1))
        fi
    fi

    COLOR=$(get_status_color "$RESULT")

    # 记录测试结果，使用实际的制表符分隔
    TEST_RESULTS+=("#$TEST_NUM"$'\t'"$RESULT"$'\t'"${ELAPSED_TIME}s"$'\t'"${MAX_MEM} KiB")
}

# 执行多组测试用例并记录结果
run_tests() {
    echo -e "${BLUE}开始执行多组测试用例...${NC}"

    # 获取所有 .in 文件的列表
    mapfile -t all_tests < <(find "$TEST_DIR" -type f -name "*.in")

    # 检查是否有测试用例
    if [[ ${#all_tests[@]} -eq 0 ]]; then
        echo -e "${RED}错误: 没有找到任何 .in 文件在目录 '$TEST_DIR'。${NC}"
        exit 1
    fi

    # 分离数字命名和字母命名的测试用例
    numeric_tests=()
    alphabetic_tests=()

    for test_input in "${all_tests[@]}"; do
        test_name=$(basename "$test_input" .in)
        if [[ "$test_name" =~ ^[0-9]+$ ]]; then
            numeric_tests+=("$test_input")
        else
            alphabetic_tests+=("$test_input")
        fi
    done

    # 对数字命名的测试用例进行数字排序
    sorted_numeric_tests=()
    if [[ ${#numeric_tests[@]} -gt 0 ]]; then
        sorted_numeric_tests=($(for test in "${numeric_tests[@]}"; do
            test_num=$(basename "$test" .in)
            echo "$test_num $test"
        done | sort -n | awk '{print $2}'))
    fi

    # 对字母命名的测试用例进行字典序排序
    sorted_alphabetic_tests=()
    if [[ ${#alphabetic_tests[@]} -gt 0 ]]; then
        sorted_alphabetic_tests=($(for test in "${alphabetic_tests[@]}"; do
            test_num=$(basename "$test" .in)
            echo "$test_num $test"
        done | sort | awk '{print $2}'))
    fi

    # 组合排序后的测试用例，数字命名的在前，字母命名的在后
    sorted_tests=()
    if [[ ${#sorted_numeric_tests[@]} -gt 0 ]]; then
        sorted_tests+=("${sorted_numeric_tests[@]}")
    fi
    if [[ ${#sorted_alphabetic_tests[@]} -gt 0 ]]; then
        sorted_tests+=("${sorted_alphabetic_tests[@]}")
    fi

    # 初始化进度
    local total=${#sorted_tests[@]}
    local current=0

    # 打印表头

    # 初始化进度 bar
    show_progress_bar 0 "$total"

    # 开始执行测试用例
    for test_input in "${sorted_tests[@]}"; do
        ((TOTAL_TESTS++))
        ((current++))
        TEST_NUM=$(basename "$test_input" .in)
        ANSWER_FILE=$(find "$TEST_DIR" -type f \( -name "$TEST_NUM.ans" -o -name "$TEST_NUM.out" \) | head -n 1)

        if [[ -z "$ANSWER_FILE" ]]; then
            TEST_RESULTS+=("#$TEST_NUM"$'\t'"UKE"$'\t'"-"$'\t'"-")
            UKE_COUNT=$((UKE_COUNT + 1))
            # 更新进度 bar
            show_progress_bar "$current" "$total"
            continue
        fi

        # 设置输出文件为 out.txt_TESTNUM.txt
        CURRENT_OUTPUT_FILE="${OUTPUT_FILE}_${TEST_NUM}.txt"

        # 定义时间和内存信息文件
        TIME_MEM_FILE="time_output_${TEST_NUM}.txt"

        # 执行程序并限制时间和内存，捕获时间和内存使用
        execute_program "$test_input" "$CURRENT_OUTPUT_FILE" "$TIME_MEM_FILE"
        EXEC_STATUS=$?

        # 更新进度 bar
        show_progress_bar "$current" "$total"

        # 读取时间和内存信息
        if [[ -f "$TIME_MEM_FILE" ]]; then
            ELAPSED_TIME=$(grep "elapsed=" "$TIME_MEM_FILE" | cut -d'=' -f2)
            MAX_MEM=$(grep "maxmem=" "$TIME_MEM_FILE" | cut -d'=' -f2)
            rm -f "$TIME_MEM_FILE"
        else
            ELAPSED_TIME="0.00"
            MAX_MEM="0"
        fi

        # 处理执行状态
        if [[ $EXEC_STATUS -eq 124 ]]; then
            RESULT="TLE"
            TLE_COUNT=$((TLE_COUNT + 1))
        elif [[ $EXEC_STATUS -eq 137 ]]; then
            RESULT="MLE"
            MLE_COUNT=$((MLE_COUNT + 1))
        elif [[ $EXEC_STATUS -ne 0 ]]; then
            RESULT="RE"
            RE_COUNT=$((RE_COUNT + 1))
        else
            # 比较输出
            if diff -w "$CURRENT_OUTPUT_FILE" "$ANSWER_FILE" >/dev/null; then
                RESULT="AC"
                AC_COUNT=$((AC_COUNT + 1))
            else
                RESULT="WA"
                WA_COUNT=$((WA_COUNT + 1))
            fi
        fi

        COLOR=$(get_status_color "$RESULT")

        # 记录测试结果，使用实际的制表符分隔
        TEST_RESULTS+=("#$TEST_NUM"$'\t'"$RESULT"$'\t'"${ELAPSED_TIME}s"$'\t'"${MAX_MEM} KiB")
    done

    # 换行，确保光标在进度条下方
    echo

    printf "${MAGENTA}%-5s\t%-5s\t%-8s\t%-10s${NC}\n" "测试" "结果" "时间" "内存"
    # 输出所有测试结果
    for result in "${TEST_RESULTS[@]}"; do
        IFS=$'\t' read -r test_num result_code time mem <<<"$result"
        COLOR=$(get_status_color "$result_code")
        printf "${COLOR}%-5s\t%-5s\t%-8s\t%-10s${NC}\n" "$test_num" "$result_code" "$time" "$mem"
    done

    # 计算预估分数
    calculate_score
}

# 编译代码（Docker 支持）
compile_code() {
    echo -e "${BLUE}编译代码...${NC}"
    case "$LANGUAGE" in
    C)
        COMPILE_CMD="gcc \"$CODE_FILE\" -o \"${CODE_FILE%.*}\" 2>compile_error.log"
        ;;
    "C++")
        COMPILE_CMD="g++ \"$CODE_FILE\" -o \"${CODE_FILE%.*}\" 2>compile_error.log"
        ;;
    Java)
        COMPILE_CMD="javac \"$CODE_FILE\" 2>compile_error.log"
        ;;
    esac

    if [[ "$USE_DOCKER" == true ]]; then
        docker_exec "$COMPILE_CMD" >/dev/null 2>&1
    else
        eval "$COMPILE_CMD" >/dev/null 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        COMPILE_ERROR=true
        echo -e "${RED}编译失败. (CE)${NC}"
        echo -e "${RED}编译错误详情:${NC}"
        if [[ "$USE_DOCKER" == true ]]; then
            docker_exec "cat compile_error.log"
        else
            cat compile_error.log
        fi
        rm -f compile_error.log
        exit 1
    else
        echo -e "${GREEN}编译成功.${NC}"
        rm -f compile_error.log
    fi
}

# 执行程序（Docker 支持）
execute_program() {
    local input_file="$1"
    local output_file="$2"
    local time_mem_file="$3"

    if [[ "$USE_DOCKER" == true ]]; then
        # 使用相对路径，确保在容器内正确访问
        docker_exec "/usr/bin/time -f '$TIME_FORMAT' -o '$time_mem_file' timeout '$TIME_LIMIT's $EXEC_CMD < '$input_file' > '$output_file' 2>/dev/null"
    else
        # 在主机上执行
        /usr/bin/time -f "$TIME_FORMAT" -o "$time_mem_file" timeout "$TIME_LIMIT"s "$EXEC_CMD" <"$input_file" >"$output_file" 2>/dev/null
    fi
}

# 清理生成文件和输出文件
cleanup() {
    # 根据编程语言删除可执行文件
    case "$LANGUAGE" in
    C | C++)
        rm -f "${CODE_FILE%.*}"
        ;;
    Java)
        rm -f "${CODE_FILE%.*}.class"
        ;;
    esac
    # 删除所有 out.txt_*.txt 文件
    if [[ "$SINGLE_CASE" == true ]]; then
        rm -f "$OUTPUT_FILE"
    else
        rm -f ${OUTPUT_FILE}_*.txt
    fi
    # 删除所有 time_output_*.txt 文件（如果存在）
    rm -f time_output_*.txt
    echo -e "${GREEN}清理完成.${NC}"
}

# 主流程
main() {
    # 切换到备用缓冲区并清屏
    tput smcup
    clear

    # 设置 trap 以确保在脚本退出时恢复主缓冲区，并清理 Docker 容器
    trap 'sleep 3; cleanup; if [[ "$USE_DOCKER" == true ]]; then stop_docker_container; fi; tput rmcup; exit' INT TERM EXIT

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    # 检查是否存在配置文件并询问是否使用上一次的选择
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${CYAN}检测到上一次的配置。是否使用上一次的选择？（Y/N）：${NC}"
        read -rp "输入选择 [默认: N]: " keep_choice
        keep_choice=${keep_choice:-N}
        case "$keep_choice" in
        [Yy]*)
            load_config
            ;;
        [Nn]* | "")
            get_user_input
            save_config
            ;;
        *)
            echo -e "${RED}无效的选择，继续使用新输入。${NC}"
            get_user_input
            save_config
            ;;
        esac
    else
        # 如果没有配置文件，则获取用户输入并保存
        get_user_input
        save_config
    fi

    if [[ "$USE_DOCKER" == true ]]; then
        check_docker
        setup_docker_image
        pull_docker_image
        start_docker_container
    fi

    compile_code

    if [[ "$COMPILE_ERROR" == true ]]; then
        cleanup
        if [[ "$USE_DOCKER" == true ]]; then
            stop_docker_container
        fi
        exit 1
    fi

    # 根据编程语言设置执行命令
    case "$LANGUAGE" in
    C | C++)
        EXEC_CMD="./${CODE_FILE%.*}"
        ;;
    Java)
        EXEC_CMD="java ${CODE_FILE%.*}"
        ;;
    esac

    if [[ "$USE_DOCKER" == true ]]; then
        # 确保执行命令在 Docker 容器内
        # 需要授予执行权限
        docker_exec "chmod +x ${EXEC_CMD}" >/dev/null 2>&1
    fi

    if [[ "$SINGLE_CASE" == true ]]; then
        run_single_test
    else
        run_tests
    fi

    cleanup

    if [[ "$USE_DOCKER" == true ]]; then
        stop_docker_container
    fi

    # 输出最终结果，仅显示计数大于0的项
    echo -e "\n${GREEN}测试总结:${NC}"
    [[ $AC_COUNT -gt 0 ]] && echo -e "${GREEN}AC: $AC_COUNT${NC}"
    [[ $WA_COUNT -gt 0 ]] && echo -e "${RED}WA: $WA_COUNT${NC}"
    [[ $TLE_COUNT -gt 0 ]] && echo -e "${YELLOW}TLE: $TLE_COUNT${NC}"
    [[ $MLE_COUNT -gt 0 ]] && echo -e "${RED}MLE: $MLE_COUNT${NC}"
    [[ $RE_COUNT -gt 0 ]] && echo -e "${RED}RE: $RE_COUNT${NC}"
    [[ $UKE_COUNT -gt 0 ]] && echo -e "${YELLOW}UKE: $UKE_COUNT${NC}"

    # 显示预估分数
    echo -e "${GREEN}预估分数: ${ESTIMATED_SCORE}/100${NC}"
}

main "$@"
