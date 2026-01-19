#!/bin/bash

# ================= 配置区域 =================
# 测试次数
ITERATIONS=20

# 目标程序启动命令
APP_CMD="sudo -u ywenzhe python3 -u /home/ywenzhe/benchmark/faas_runner.py float_operation"

# CRIU 路径 (根据你的描述配置)
CRIU_BIN="/home/ywenzhe/CRIU/rcriu/criu/criu"
IMG_DIR="/home/ywenzhe/CRIU/check"

# 输出结果文件
RESULT_CSV="criu_perf_results.csv"

# Dump 阶段需要采集的指标 (完全对应你的输出)
DUMP_KEYS=(
    "Freezing time"
    "Frozen time"
    "Memory dump time"
    "Memory write time"
    "CXL write time"
    "Disk write time"
    "CPU dump time"
    "VMA dump time"
    "Pagemap dump time"
)

# Restore 阶段需要采集的指标 (完全对应你的输出)
RESTORE_KEYS=(
    "Restore time"
    "Forking time"
    "Init time"
    "Create main task time"
    "VMA read time"
    "FD read time"
    "Restorer init time"
    "VMA load time"
    "VMA FD restore time"
    "Core read time"
    "Fill restorer time"
    "Remap restorer time"
    "Thread setup time"
    "MM restore time"
    "Sync processes time"
)

# ===========================================

# 检查是否以 root 运行 (CRIU 通常需要 root)
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

# 初始化 CSV 头部
HEADER="Iteration"
for key in "${DUMP_KEYS[@]}"; do HEADER="$HEADER,Dump:$key(us)"; done
for key in "${RESTORE_KEYS[@]}"; do HEADER="$HEADER,Restore:$key(us)"; done
echo "$HEADER" > "$RESULT_CSV"

echo "开始测试，共 $ITERATIONS 轮..."
echo "结果将写入: $RESULT_CSV"
echo "------------------------------------------------"

# 清理函数：确保退出时杀死遗留进程
cleanup() {
    if [ -n "$TARGET_PID" ]; then
        kill -9 "$TARGET_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

# 辅助函数：从日志中提取数值
# 用法: extract_value "Key Name" "logfile"
extract_value() {
    local key="$1"
    local file="$2"
    # 匹配 "Key: 123 us" 格式，提取数字
    grep "$key:" "$file" | awk -F': ' '{print $2}' | awk '{print $1}' | head -n 1
}

# ================= 主循环 =================
for ((i=1; i<=ITERATIONS; i++)); do
    echo -n "Round $i/$ITERATIONS: "
    
    # 1. 启动目标进程 (后台运行)
    # 将输出重定向到文件以便解析 PID
    $APP_CMD > app_output.tmp 2>&1 &
    
    # 2. 等待 PID 出现
    echo -n "Starting App... "
    TARGET_PID=""
    while [ -z "$TARGET_PID" ]; do
        if grep -q "当前进程的PID是:" app_output.tmp; then
            # 提取 PID (假设格式: 当前进程的PID是: 1775543)
            TARGET_PID=$(grep "当前进程的PID是:" app_output.tmp | awk -F': ' '{print $2}' | tr -d '[:space:]')
        fi
        sleep 0.1
    done
    
    # 等待 Flask 完全启动 (可选，防止在此之前 Dump)
    while ! grep -q "Running on http" app_output.tmp; do
        sleep 0.1
    done
    
    echo -n "PID=$TARGET_PID. "

    # 3. 执行 Dump
    echo -n "Dumping... "
    $CRIU_BIN dump -D "$IMG_DIR" --shell-job -v0 --display-stats -t "$TARGET_PID" > dump_stats.tmp 2>&1
    if [ $? -ne 0 ]; then
        echo "Dump failed! 查看 dump_stats.tmp"
        cat dump_stats.tmp
        exit 1
    fi

    # 4. 执行 Restore
    echo -n "Restoring... "
    $CRIU_BIN restore -D "$IMG_DIR" --shell-job -v0 --display-stats > restore_stats.tmp 2>&1
    if [ $? -ne 0 ]; then
        echo "Restore failed! 查看 restore_stats.tmp"
        cat restore_stats.tmp
        exit 1
    fi

    # 5. 杀死恢复后的进程 (为下一轮做准备)
    # Restore 后进程会继续运行，我们需要获取恢复后的 PID 这里的 PID 通常与 Dump 前一致
    # 但为了保险，我们尝试通过端口或原 PID 杀掉
    kill -9 "$TARGET_PID" 2>/dev/null
    wait "$TARGET_PID" 2>/dev/null

    # 6. 数据采集与写入 CSV
    ROW="$i"
    
    # 采集 Dump 数据
    for key in "${DUMP_KEYS[@]}"; do
        val=$(extract_value "$key" dump_stats.tmp)
        if [ -z "$val" ]; then val="0"; fi
        ROW="$ROW,$val"
    done
    
    # 采集 Restore 数据
    for key in "${RESTORE_KEYS[@]}"; do
        val=$(extract_value "$key" restore_stats.tmp)
        if [ -z "$val" ]; then val="0"; fi
        ROW="$ROW,$val"
    done
    
    echo "$ROW" >> "$RESULT_CSV"
    echo "Done."
    
    # 清理临时文件
    rm -f app_output.tmp dump_stats.tmp restore_stats.tmp
    
    # 稍微休眠，确保端口释放
    sleep 1
done

# ================= 结果分析 =================
echo "------------------------------------------------"
echo "测试完成. 计算平均值..."

# 使用 awk 计算平均值
awk -F',' '
    NR==1 { 
        # 保存标题
        for(i=2; i<=NF; i++) headers[i]=$i 
        next 
    }
    { 
        # 累加每一列
        for(i=2; i<=NF; i++) sums[i]+=$i 
        count++ 
    }
    END {
        printf "%-30s %s\n", "METRIC", "AVERAGE (us)"
        printf "%-30s %s\n", "------", "------------"
        for(i=2; i<=NF; i++) {
            printf "%-30s %.2f\n", headers[i], sums[i]/count
        }
    }
' "$RESULT_CSV" | tee criu_average_report.txt

echo "------------------------------------------------"
echo "详细 CSV 数据已保存至: $RESULT_CSV"
echo "平均值报告已保存至: criu_average_report.txt"