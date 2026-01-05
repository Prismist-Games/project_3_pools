import sys
import subprocess
import threading
import json

# 替换成你的 Godot 可执行文件路径
# Windows 示例: r"C:\Program Files\Godot\Godot_v4.x.exe"
# Mac 示例: "/Applications/Godot.app/Contents/MacOS/Godot"
GODOT_PATH = "godot" 

# 你的项目路径
PROJECT_PATH = "." 

def enqueue_output(out, queue):
    for line in iter(out.readline, b''):
        queue.write(line)
    out.close()

def run():
    # 启动 Godot，强制无头模式
    # 注意：一定要把 stdout=subprocess.PIPE 以便我们要拦截它
    process = subprocess.Popen(
        [GODOT_PATH, "--headless", "--no-header", "--path", PROJECT_PATH],
        stdin=sys.stdin,       # 把 Antigravity 的输入传给 Godot
        stdout=subprocess.PIPE, # 拦截 Godot 的输出
        stderr=sys.stderr,      # 错误信息直接透传
        text=True,
        bufsize=0              # 无缓冲，保证实时性
    )

    # 循环读取 Godot 的输出
    while True:
        line = process.stdout.readline()
        if not line:
            break
            
        # 核心逻辑：过滤“脏”数据
        # 只有当行首是 '{' 时，我们才认为它是 MCP 的 JSON 消息
        if line.strip().startswith("{"):
            sys.stdout.write(line)
            sys.stdout.flush()
        else:
            # (可选) 将被拦截的日志打印到 stderr，这样你在 Antigravity 的 Output 面板能看到，但不会报错
            sys.stderr.write(f"[Godot Log] {line}")
            sys.stderr.flush()

    process.wait()

if __name__ == "__main__":
    run()