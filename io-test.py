import os
import time
import shutil
import tempfile
import random

class MixedFileBenchmark:
    def __init__(self, target_dir=".", rounds=10):
        self.target_dir = target_dir
        self.rounds = rounds
        self.temp_dir = os.path.join(self.target_dir, "mixed_bench_temp")
        
        # 定义文件规格
        # 11个 10KB (10 * 1024 bytes)
        self.small_files_config = [
            {"name": f"small_{i}.bin", "size": 5 * 1024} for i in range(11)
        ]
        # 1个 213357KB (213357 * 1024 bytes)
        self.large_file_config = [
            {"name": "large_main.bin", "size": 213357 * 1024}
        ]
        
        # 合并任务列表 (共12个文件)
        self.all_files = self.small_files_config + self.large_file_config
        
        # 预先在内存生成数据，避免计时时包含数据生成时间
        print("正在预生成测试数据到内存，请稍候...")
        self.data_cache = {}
        # 为了节省内存，小文件共用一份数据，大文件单独一份
        self.small_data_content = os.urandom(10 * 1024)
        self.large_data_content = os.urandom(213357 * 1024)

    def setup(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)
        os.makedirs(self.temp_dir)

    def teardown(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def run_write_test(self):
        """
        测试将所有文件写入磁盘的总耗时
        """
        # 随机打乱写入顺序，模拟真实场景（如果想固定顺序，注释掉下面这行）
        random.shuffle(self.all_files)
        
        start_counter = time.perf_counter()
        
        for file_info in self.all_files:
            file_path = os.path.join(self.temp_dir, file_info["name"])
            
            # 判断使用哪份数据
            if "large" in file_info["name"]:
                content = self.large_data_content
            else:
                content = self.small_data_content
            
            with open(file_path, 'wb') as f:
                f.write(content)
                f.flush()
                os.fsync(f.fileno()) # 强制刷盘，确保计算的是磁盘IO时间
                
        end_counter = time.perf_counter()
        
        # 返回微秒 (秒 * 1,000,000)
        return (end_counter - start_counter) * 1_000_000

    def run_read_test(self):
        """
        测试读取所有文件的总耗时
        """
        # 读取时也打乱顺序
        random.shuffle(self.all_files)
        
        start_counter = time.perf_counter()
        
        for file_info in self.all_files:
            file_path = os.path.join(self.temp_dir, file_info["name"])
            with open(file_path, 'rb') as f:
                while True:
                    # 模拟真实读取，按块读取
                    data = f.read(1024 * 1024) 
                    if not data:
                        break
                        
        end_counter = time.perf_counter()
        return (end_counter - start_counter) * 1_000_000

    def run(self):
        print(f"--- 混合负载磁盘测试 (Target: {os.path.abspath(self.target_dir)}) ---")
        print(f"任务批次: 11个 10KB 文件 + 1个 213,357KB 文件")
        print(f"测试轮数: {self.rounds}")
        print("-" * 60)
        print(f"{'轮次':<6} | {'写耗时 (微秒)':<15} | {'读耗时 (微秒)':<15}")
        print("-" * 60)

        write_times = []
        read_times = []

        try:
            self.setup()
            
            for r in range(1, self.rounds + 1):
                # 1. 写测试
                w_time = self.run_write_test()
                write_times.append(w_time)
                
                # 2. 读测试 (读取刚刚写入的文件)
                r_time = self.run_read_test()
                read_times.append(r_time)
                
                # 打印本轮结果
                print(f"{r:<6} | {w_time:,.0f} us{'':<8} | {r_time:,.0f} us")
                
                # 清理文件以便下一轮重新写入 (保持目录存在，只删文件)
                for filename in os.listdir(self.temp_dir):
                    file_path = os.path.join(self.temp_dir, filename)
                    os.remove(file_path)

        except KeyboardInterrupt:
            print("\n用户中断测试。")
        except Exception as e:
            print(f"\n错误: {e}")
        finally:
            self.teardown()

        # 统计
        if write_times:
            avg_w = sum(write_times) / len(write_times)
            avg_r = sum(read_times) / len(read_times)
            
            print("-" * 60)
            print("最终平均结果:")
            print(f"写平均耗时: {avg_w:,.0f} 微秒")
            print(f"读平均耗时: {avg_r:,.0f} 微秒")
            print("=" * 60)

if __name__ == "__main__":
    # 如需测试其他磁盘，修改 target_dir，例如 "D:\\" 或 "/data"
    bench = MixedFileBenchmark(target_dir="/mnt/tmp/test", rounds=10)
    bench.run()