#!/bin/bash
# Available functions: ['graph', 'float_operation', 'chameleon', 'json_dumps_loads', 'linpack', 'matmul', 'pyaes', 'translator', 'web_service']
# ================= 配置区域 =================
ITERATIONS=10
# 加上 -u 防止 python 输出缓冲
APP_CMD="sudo -u ywenzhe numactl --cpunodebind=4 --membind=4 python3 -u /home/ywenzhe/benchmark/faas_runner.py translator"

CRIU_BIN="/home/ywenzhe/CRIU/rcriu/criu/criu"
IMG_DIR="/mnt/tmp"

RESULT_CSV="dump_fs_translator.csv"

# Dump 阶段关注的指标
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
# ===========================================

if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 运行此脚本"; exit 1; fi
mkdir -p "$IMG_DIR"

# 初始化 CSV
HEADER="Iteration"
for key in "${DUMP_KEYS[@]}"; do HEADER="$HEADER,$key(us)"; done
echo "$HEADER" > "$RESULT_CSV"

extract_value() {
    local key="$1"
    local file="$2"
    grep "$key:" "$file" | awk -F': ' '{print $2}' | awk '{print $1}' | head -n 1
}

cleanup() {
    pkill -f "faas_runner.py" 2>/dev/null
}
trap cleanup EXIT

echo "========== 开始 Dump 性能测试 (共 $ITERATIONS 轮) =========="

for ((i=1; i<=ITERATIONS; i++)); do
    echo -n "Round $i: "
    
    # 1. 启动目标进程
    > app_output.tmp
    $APP_CMD > app_output.tmp 2>&1 &
    
    # 2. 获取 PID (带超时)
    echo -n "Starting App... "
    TARGET_PID=""
    CTR=0
    while [ -z "$TARGET_PID" ]; do
        if grep -q "当前进程的PID是:" app_output.tmp; then
            TARGET_PID=$(grep "当前进程的PID是:" app_output.tmp | awk -F': ' '{print $2}' | tr -d '[:space:]')
        fi
        sleep 0.1
        ((CTR++))
        if [ $CTR -gt 150 ]; then echo "启动超时!"; exit 1; fi
    done
    
    while ! grep -q "Running on http" app_output.tmp; do sleep 0.1; done
    echo -n "PID=$TARGET_PID. "

    # 3. 执行 Dump
    echo -n "Dumping... "
    numactl --cpunodebind=4 --membind=4 $CRIU_BIN dump -D "$IMG_DIR" --shell-job -v0 --display-stats -t "$TARGET_PID" > dump_stats.tmp 2>&1
    
    if [ $? -ne 0 ]; then
        echo "Dump 失败! 查看 dump_stats.tmp"
        cat dump_stats.tmp
        exit 1
    fi

    # 4. 数据采集
    ROW="$i"
    for key in "${DUMP_KEYS[@]}"; do
        val=$(extract_value "$key" dump_stats.tmp)
        ROW="$ROW,${val:-0}"
    done
    echo "$ROW" >> "$RESULT_CSV"
    echo "Done."

    kill -9 "$TARGET_PID" 2>/dev/null
    wait "$TARGET_PID" 2>/dev/null
    
    sudo rm -rf "$IMG_DIR"/*
    rm -f app_output.tmp dump_stats.tmp
    sleep 2
done

# ================= 计算平均值并写入 CSV =================
echo "------------------------------------------------"
echo "正在计算平均值并写入 $RESULT_CSV ..."

# 使用 awk 计算平均值，并追加到 CSV 文件末尾
awk -F',' '
    NR==1 { next } # 跳过标题行
    { 
        # 累加每一列 (从第2列开始)
        for(i=2; i<=NF; i++) sum[i]+=$i 
        count++ 
    }
    END {
        if (count > 0) {
            printf "Average" # 第一列显示 Average
            for(i=2; i<=NF; i++) {
                printf ",%.2f", sum[i]/count # 计算并打印平均值
            }
            printf "\n"
        }
    }
' "$RESULT_CSV" >> "$RESULT_CSV"

echo "完成。最后一行数据如下："
tail -n 1 "$RESULT_CSV"