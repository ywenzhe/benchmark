import sys
import re
import csv
import argparse

def parse_dump_stats(input_lines):
    """
    解析输入行，提取多次运行的统计信息。
    只提取包含 'time' 的字段。
    """
    records = []
    current_record = {}
    
    # 正则匹配模式： 匹配 "Key time: Value us" 或类似的格式
    # 捕获组 1: Key (例如 "Freezing time")
    # 捕获组 2: Value (数字)
    time_pattern = re.compile(r"^\s*(.+?time):\s+(\d+)")

    for line in input_lines:
        line = line.strip()
        
        # 检测新的一轮数据的开始
        if "Displaying dump stats" in line:
            if current_record:
                records.append(current_record)
                current_record = {}
            continue
        
        # 尝试匹配时间行
        match = time_pattern.match(line)
        if match:
            key = match.group(1).strip()
            value = match.group(2) # 保持字符串以便写入，但在计算平均值时转为 int
            current_record[key] = value

    # 循环结束后，保存最后一条记录
    if current_record:
        records.append(current_record)
        
    return records

def calculate_average(records, keys):
    """
    计算平均值行
    """
    if not records:
        return {}
    
    avg_record = {'Round': 'Average'}
    count = len(records)
    
    for key in keys:
        total = 0
        valid_vals = 0
        for rec in records:
            if key in rec:
                try:
                    total += float(rec[key])
                    valid_vals += 1
                except ValueError:
                    continue
        
        # 如果所有轮次都有该字段，计算平均值
        if valid_vals > 0:
            # 使用总轮数作为分母，或者仅使用有效数据的轮数，这里通常使用总轮数(count)或者有效轮数(valid_vals)
            # 对于这种日志，通常每轮结构一致，所以 valid_vals == count
            avg_val = total / valid_vals
            avg_record[key] = "{:.2f}".format(avg_val) # 保留两位小数
        else:
            avg_record[key] = "0"
            
    return avg_record

def save_to_csv(records, output_filename):
    """
    将字典列表保存为 CSV 文件，包含序号和平均值
    """
    if not records:
        print("未找到有效的时间数据。")
        return

    # 1. 获取所有可能的字段名（作为表头）
    # 使用 dict.fromkeys 保持插入顺序 (Python 3.7+)
    keys = []
    for rec in records:
        for key in rec.keys():
            if key not in keys:
                keys.append(key)
    
    # 在表头最前面添加 'Round'
    headers = ['Round'] + keys
    
    try:
        with open(output_filename, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=headers)
            
            writer.writeheader()
            
            # 2. 写入数据行（带序号）
            for i, record in enumerate(records, 1):
                # 创建一个新字典以包含 Round 字段，避免修改原数据
                row_to_write = {'Round': i}
                row_to_write.update(record)
                writer.writerow(row_to_write)
            
            # 3. 计算并写入平均值行
            avg_record = calculate_average(records, keys)
            writer.writerow(avg_record)
        
        print(f"成功! {len(records)} 轮数据及平均值已保存至: {output_filename}")
        
    except IOError as e:
        print(f"写入文件错误: {e}")

def main():
    parser = argparse.ArgumentParser(description="解析 Dump Stats 日志，计算平均值并导出 CSV。")
    parser.add_argument('-i', '--input', type=str, help="输入文件路径 (如果不指定，则从控制台/管道读取)")
    parser.add_argument('-o', '--output', type=str, default="dump_stats_avg.csv", help="输出 CSV 文件名")
    
    args = parser.parse_args()
    
    lines = []
    
    # 输入处理逻辑
    if args.input:
        try:
            with open(args.input, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except FileNotFoundError:
            print(f"错误: 找不到文件 {args.input}")
            return
    else:
        print("请粘贴你的日志数据 (完成后按 Ctrl+D 或 Ctrl+Z 结束):")
        try:
            lines = sys.stdin.readlines()
        except KeyboardInterrupt:
            pass

    records = parse_dump_stats(lines)
    save_to_csv(records, args.output)

if __name__ == "__main__":
    main()