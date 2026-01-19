import os
import sys
import time
import resource
import yaml
import importlib.util
from flask import Flask, request, jsonify
import traceback

app = Flask(__name__)

# 配置路径
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
APPS_DIR = os.path.join(BASE_DIR, 'apps')
CONFIG_FILE = os.path.join(APPS_DIR, 'functions_info.yaml')

# 全局变量存储当前加载的模块
ACTIVE_MODULE = None
ACTIVE_FUNCTION_NAME = None

# 加载函数配置
def load_functions_config():
    if not os.path.exists(CONFIG_FILE):
        return {"apps": {}}
    with open(CONFIG_FILE, 'r') as f:
        return yaml.safe_load(f)

functions_config = load_functions_config()

def load_module(function_name):
    func_dir = os.path.join(APPS_DIR, function_name)
    app_path = os.path.join(func_dir, 'app.py')
    if not os.path.exists(app_path):
        return None
    
    # 将函数目录加入 sys.path 以支持本地导入
    if func_dir not in sys.path:
        sys.path.insert(0, func_dir)

    try:
        spec = importlib.util.spec_from_file_location(f"apps.{function_name}", app_path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[f"apps.{function_name}"] = module
        spec.loader.exec_module(module)
        return module
    except Exception as e:
        print(f"Error loading module {function_name}: {e}")
        traceback.print_exc()
        return None

@app.route('/functions', methods=['GET'])
def list_functions():
    return jsonify(functions_config)

@app.route('/invoke/instance', methods=['POST'])
def invoke_instance():
    global ACTIVE_MODULE
    
    if not ACTIVE_MODULE:
        return jsonify({"error": "No function loaded"}), 500
    
    if not hasattr(ACTIVE_MODULE, 'handler'):
        return jsonify({"error": f"Function {ACTIVE_FUNCTION_NAME} does not have a handler"}), 500

    # 获取输入参数
    context = request.json if request.is_json else {}
    
    try:
        # 执行函数
        result = ACTIVE_MODULE.handler(context)
        return jsonify({"result": result, "status": "success"})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e), "status": "failed"}), 500

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 faas_runner.py <function_name>")
        sys.exit(1)

    function_name = sys.argv[1]
    
    if function_name not in functions_config.get('apps', {}):
        print(f"Error: Function '{function_name}' not found in configuration.")
        print(f"Available functions: {list(functions_config.get('apps', {}).keys())}")
        sys.exit(1)

    current_pid = os.getpid()
    print(f"当前进程的PID是: {current_pid}")

    print(f"Loading function: {function_name}...")
    ACTIVE_MODULE = load_module(function_name)
    
    if not ACTIVE_MODULE:
        print(f"Error: Failed to load function '{function_name}'")
        sys.exit(1)
        
    ACTIVE_FUNCTION_NAME = function_name
    print(f"Function '{function_name}' loaded successfully.")
    print(f"Starting FaaS Runner on port 12345...")
    app.run(host='0.0.0.0', port=12345, debug=False)