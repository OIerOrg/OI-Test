#!/bin/bash

# test.sh: 自动编译和运行 C/C++/Java 程序的自动化工具，支持单组或多组样例，自动识别编程语言，并在控制台输出结果

# ANSI 颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m' # 蓝色
NC='\033[0m'      # 无颜色

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

# 定义 pause 函数
pause() {
    echo -e "${GREEN}按任意键继续...${NC}"
    read -n 1 -s
}

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
    echo
    echo "选项："
    echo "  -h, --help    显示帮助信息"
    echo
    echo "使用方法："
    echo "  直接运行脚本并按照提示操作： ./test.sh"
    echo
    echo "示例："
    echo "  ./test.sh"
    echo
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
        echo -e "${BLUE}检测到多个匹配的源代码文件:${NC}"
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
    echo -e "${BLUE}请输入源代码的基名称（不含扩展名，如 main）：${NC}"
    read -rp "基名称: " BASE_NAME
    if [[ -z "$BASE_NAME" ]]; then
        echo -e "${RED}错误: 基名称不能为空.${NC}"
        exit 1
    fi

    identify_language "$BASE_NAME"

    echo -e "${BLUE}请选择样例类型:${NC}"
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
        echo -e "${BLUE}请输入单组测试用例的输入文件路径（如 in.txt） [默认: in.txt]:${NC}"
        read -rp "输入文件: " SINGLE_INPUT
        SINGLE_INPUT=${SINGLE_INPUT:-in.txt}
        if [[ ! -f "$SINGLE_INPUT" ]]; then
            echo -e "${RED}错误: 输入文件 '$SINGLE_INPUT' 不存在.${NC}"
            exit 1
        fi

        echo -e "${BLUE}请输入单组测试用例的答案文件路径（如 ans.txt） [默认: ans.txt]:${NC}"
        read -rp "答案文件: " SINGLE_ANSWER
        SINGLE_ANSWER=${SINGLE_ANSWER:-ans.txt}
        if [[ ! -f "$SINGLE_ANSWER" ]]; then
            echo -e "${RED}错误: 答案文件 '$SINGLE_ANSWER' 不存在.${NC}"
            exit 1
        fi
    else
        echo -e "${BLUE}请输入测试用例目录路径（默认: ./test_cases）：${NC}"
        read -rp "测试用例目录: " TEST_DIR
        TEST_DIR=${TEST_DIR:-./test_cases}
        if [[ ! -d "$TEST_DIR" ]]; then
            echo -e "${RED}错误: 测试用例目录 '$TEST_DIR' 不存在.${NC}"
            exit 1
        fi
    fi

    # 设置时间限制和内存限制
    echo -e "${BLUE}设置时间限制（秒，默认: 1）：${NC}"
    read -rp "时间限制: " TIME_LIMIT
    TIME_LIMIT=${TIME_LIMIT:-1}

    echo -e "${BLUE}设置内存限制（KB，默认: 65536）：${NC}"
    read -rp "内存限制: " MEMORY_LIMIT
    MEMORY_LIMIT=${MEMORY_LIMIT:-65536}
}

# 编译代码
compile_code() {
    echo -e "${BLUE}编译代码...${NC}"
    case "$LANGUAGE" in
    C)
        gcc "$CODE_FILE" -o "${CODE_FILE%.*}" 2>/dev/null
        ;;
    "C++")
        g++ "$CODE_FILE" -o "${CODE_FILE%.*}" 2>/dev/null
        ;;
    Java)
        javac "$CODE_FILE" 2>/dev/null
        ;;
    esac

    if [[ $? -ne 0 ]]; then
        COMPILE_ERROR=true
        echo -e "${RED}编译失败. (CE)${NC}"
    else
        echo -e "${GREEN}编译成功.${NC}"
    fi
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
        echo -e "${BLUE}"
        ;;
    *)
        echo -e "${NC}"
        ;;
    esac
}

# 执行单组测试用例并输出结果到控制台
run_single_test() {
    echo -e "${BLUE}开始执行单组测试用例...${NC}"

    TEST_NUM=1
    INPUT_FILE="$(realpath "$SINGLE_INPUT")"
    ANSWER_FILE="$(realpath "$SINGLE_ANSWER")"
    CURRENT_OUTPUT_FILE="$(realpath "$OUTPUT_FILE")"

    # 定义时间和内存信息文件
    TIME_MEM_FILE="time_output_single.txt"

    # 执行程序并限制时间和内存，捕获时间和内存使用
    /usr/bin/time -f "$TIME_FORMAT" -o "$TIME_MEM_FILE" timeout "$TIME_LIMIT"s "$EXEC_CMD" <"$SINGLE_INPUT" >"$CURRENT_OUTPUT_FILE" 2>/dev/null
    EXEC_STATUS=$?

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

    # 根据结果输出，包括秒和 KiB
    echo -e "${COLOR}#${TEST_NUM}\t${RESULT}\t${ELAPSED_TIME}s\t${MAX_MEM} KiB${NC}"
}

# 执行多组测试用例并输出结果到控制台
run_tests() {
    echo -e "${BLUE}开始执行多组测试用例...${NC}"

    for test_input in "$TEST_DIR"/*.in; do
        ((TOTAL_TESTS++))
        TEST_NUM=$(basename "$test_input" .in)
        ANSWER_FILE=$(find "$TEST_DIR" -type f \( -name "$TEST_NUM.ans" -o -name "$TEST_NUM.out" \) | head -n 1)

        if [[ -z "$ANSWER_FILE" ]]; then
            echo -e "${BLUE}#${TEST_NUM}\tUKE${NC}"
            UKE_COUNT=$((UKE_COUNT + 1))
            continue
        fi

        # 设置输出文件为 out.txt_TESTNUM.txt
        CURRENT_OUTPUT_FILE="${OUTPUT_FILE}_${TEST_NUM}.txt"

        # 定义时间和内存信息文件
        TIME_MEM_FILE="time_output_${TEST_NUM}.txt"

        # 执行程序并限制时间和内存，捕获时间和内存使用
        /usr/bin/time -f "$TIME_FORMAT" -o "$TIME_MEM_FILE" timeout "$TIME_LIMIT"s "$EXEC_CMD" <"$test_input" >"$CURRENT_OUTPUT_FILE" 2>/dev/null
        EXEC_STATUS=$?

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

        # 根据结果输出，包括秒和 KiB
        echo -e "${COLOR}#${TEST_NUM}\t${RESULT}\t${ELAPSED_TIME}s\t${MAX_MEM} KiB${NC}"
    done
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

    # 设置 trap 以确保在脚本退出时恢复主缓冲区
    trap 'tput rmcup; exit' INT TERM EXIT

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        tput rmcup
        exit 0
    fi

    get_user_input
    compile_code

    if [[ "$COMPILE_ERROR" == true ]]; then
        tput rmcup
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

    if [[ "$SINGLE_CASE" == true ]]; then
        run_single_test
    else
        run_tests
    fi

    cleanup

    # 输出最终结果，仅显示计数大于0的项
    echo -e "${GREEN}测试总结:${NC}"
    [[ $AC_COUNT -gt 0 ]] && echo -e "${GREEN}AC: $AC_COUNT${NC}"
    [[ $WA_COUNT -gt 0 ]] && echo -e "${RED}WA: $WA_COUNT${NC}"
    [[ $TLE_COUNT -gt 0 ]] && echo -e "${BLUE}TLE: $TLE_COUNT${NC}"
    [[ $MLE_COUNT -gt 0 ]] && echo -e "${RED}MLE: $MLE_COUNT${NC}"
    [[ $RE_COUNT -gt 0 ]] && echo -e "${RED}RE: $RE_COUNT${NC}"
    [[ $UKE_COUNT -gt 0 ]] && echo -e "${BLUE}UKE: $UKE_COUNT${NC}"

    # 添加 pause 功能
    pause

    # 解除 trap 并恢复主缓冲区
    trap - INT TERM EXIT
    tput rmcup
}

main "$@"
