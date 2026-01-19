#!/bin/bash
# Available functions: ['graph', 'float_operation', 'chameleon', 'json_dumps_loads', 'linpack', 'matmul', 'pyaes', 'translator', 'web_service']
# ================= 配置区域 =================
ITERATIONS=10
APP_CMD="sudo -u ywenzhe numactl --cpunodebind=4 --membind=4 python3 -u /home/ywenzhe/benchmark/faas_runner.py float_operation"

CRIU_BIN="/home/ywenzhe/CRIU/rcriu/criu/criu"
IMG_DIR="/mnt/tmp"
RESULT_CSV="restore_fs_float.csv"

# Restore 阶段关注的指标
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

if [ "$EUID" -ne 0 ]; then echo "请使用 sudo 运行此脚本"; exit 1; fi
mkdir -p "$IMG_DIR"

# 初始化 CSV
HEADER="Iteration"
for key in "${RESTORE_KEYS[@]}"; do HEADER="$HEADER,$key(us)"; done
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

# ================= 自动 Dump 函数 =================
perform_initial_dump() {
    echo ">>> 检测到 check 目录为空或缺少镜像，正在执行初始 Dump..."
    
    # 1. 启动程序
    > app_output_init.tmp
    $APP_CMD > app_output_init.tmp 2>&1 &
    
    # 2. 等待 PID
    local TARGET_PID=""
    local CTR=0
    while [ -z "$TARGET_PID" ]; do
        if grep -q "当前进程的PID是:" app_output_init.tmp; then
            TARGET_PID=$(grep "当前进程的PID是:" app_output_init.tmp | awk -F': ' '{print $2}' | tr -d '[:space:]')
        fi
        sleep 0.1
        ((CTR++))
        if [ $CTR -gt 150 ]; then 
            echo "错误: 初始启动超时，无法获取 PID。"
            cat app_output_init.tmp
            return 1
        fi
    done
    
    # 等待服务完全就绪
    while ! grep -q "Running on http" app_output_init.tmp; do sleep 0.1; done
    echo "    目标进程已启动 (PID=$TARGET_PID)，正在生成镜像..."

    # 3. 执行 Dump (不显示详细统计，只求生成镜像)
    numactl --cpunodebind=4 --membind=4 $CRIU_BIN dump -D "$IMG_DIR" --shell-job -v0 -t "$TARGET_PID"
    
    if [ $? -ne 0 ]; then
        echo "错误: 初始 Dump 失败！"
        return 1
    fi
    
    # rm -f app_output_init.tmp
    echo ">>> 镜像生成成功！准备开始 Restore 测试..."
    sleep 1
}

# ================= 清空旧镜像重新生成 =================
sudo rm -rf "$IMG_DIR"/*
perform_initial_dump

echo "========== 开始 Restore 性能测试 (共 $ITERATIONS 轮) =========="

for ((i=1; i<=ITERATIONS; i++)); do
    echo -n "Round $i: "
    
    # 1. 执行 Restore
    echo -n "Restoring... "
    numactl --cpunodebind=4 --membind=4 $CRIU_BIN restore -D "$IMG_DIR" --shell-job -vvv -o /home/ywenzhe/benchmark/restore.log --display-stats --restore-detached > restore_stats.tmp 2>&1
    
    if [ $? -ne 0 ]; then
        echo "Restore 失败! 查看 restore_stats.tmp"
        cat restore_stats.tmp
        exit 1
    fi

    # 2. 数据采集
    ROW="$i"
    for key in "${RESTORE_KEYS[@]}"; do
        val=$(extract_value "$key" restore_stats.tmp)
        ROW="$ROW,${val:-0}"
    done
    echo "$ROW" >> "$RESULT_CSV"
    
    # 3. 清理刚刚恢复的进程
    RESTORED_PID=$(pgrep -f "faas_runner.py" | head -n 1)
    if [ -n "$RESTORED_PID" ]; then
        kill -9 "$RESTORED_PID"
        echo "Done (PID $RESTORED_PID killed)."
    else
        echo "Done."
    fi

    rm -f restore_stats.tmp
    sync; echo 3 > /proc/sys/vm/drop_caches
    sleep 2
done

# ================= 计算平均值并写入 CSV =================
echo "------------------------------------------------"
echo "正在计算平均值并写入 $RESULT_CSV ..."

awk -F',' '
    NR==1 { next }
    { 
        for(i=2; i<=NF; i++) sum[i]+=$i 
        count++ 
    }
    END {
        if (count > 0) {
            printf "Average"
            for(i=2; i<=NF; i++) {
                printf ",%.2f", sum[i]/count
            }
            printf "\n"
        }
    }
' "$RESULT_CSV" >> "$RESULT_CSV"

echo "完成。最后一行数据如下："
tail -n 1 "$RESULT_CSV"