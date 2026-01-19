# Simple FaaS Runner 使用说明

这是一个简易的 FaaS (Function as a Service) 函数运行程序，基于 Flask 开发。它允许你加载并运行定义在 `apps/` 目录下的 Python 函数。

## 环境准备

确保已安装 Python 3 以及必要的依赖库：

```bash
pip install -r requirements.txt
```

`requirements.txt` 应包含：
- flask
- pyyaml
- chameleon (如果运行 chameleon 函数)
- numpy (如果运行 matmul 函数)
- ... (其他函数特定的依赖)

## 目录结构

- `faas_runner.py`: 主程序
- `apps/`: 存放函数代码的目录
- `apps/functions_info.yaml`: 函数配置文件

## 启动服务

运行程序时，必须指定要加载的函数名称作为参数。

**语法：**
```bash
python3 faas_runner.py <function_name>
```

**示例（启动 float_operation 函数）：**
```bash
python3 faas_runner.py float_operation
```

如果启动成功，你将看到类似以下的输出：
```text
Loading function: float_operation...
Function 'float_operation' loaded successfully.
Starting FaaS Runner on port 12345...
 * Serving Flask app 'faas_runner'
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:12345
```

## API 接口

### 1. 查看可用函数列表

- **URL**: `/functions`
- **Method**: `GET`

**示例：**
```bash
curl http://localhost:12345/functions
```

### 2. 调用当前加载的函数实例

- **URL**: `/invoke/instance`
- **Method**: `POST`
- **Content-Type**: `application/json`
- **Body**: 函数所需的参数 JSON

**示例（调用 float_operation）：**

`float_operation` 函数需要一个参数 `n` (循环次数)。

```bash
curl -X POST -H "Content-Type: application/json" \
     -d '{"n": 1000}' \
     http://localhost:12345/invoke/instance
```

**响应示例：**
```json
{
  "result": 0.000123,
  "status": "success"
}
```

## 可用函数参考

根据 `apps/functions_info.yaml`，支持以下函数（部分）：

- `float_operation`: 浮点数运算测试 (参数: `n`)
- `matmul`: 矩阵乘法 (参数: `n`)
- `chameleon`: HTML 模板渲染 (参数: `num_of_rows`, `num_of_cols`)
- `graph`: 图算法 BFS
- `linpack`: 线性方程组求解
- `pyaes`: AES 加密
- `json_dumps_loads`: JSON 序列化测试
- `web_service`: 模拟 Web 服务

请确保在调用时传递正确的参数。
