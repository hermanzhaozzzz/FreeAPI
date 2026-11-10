"""Use disposable child processes to test guardian cleanup; no SSH connection needed."""
import os
from pathlib import Path
import subprocess
import sys
import time

guardian_script = Path(__file__).resolve().parents[1] / 'Resources/guardian.sh'

def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False

for force_quit in (False, True):
    owner = subprocess.Popen(['sleep', '300'])
    guardian = subprocess.Popen([
        '/bin/sh', str(guardian_script), str(owner.pid), sys.executable, '-u', '-c',
        'import os,time; print(os.getpid(), flush=True); time.sleep(300)'
    ], stdout=subprocess.PIPE, text=True)
    worker_pid = None
    try:
        worker_pid = int(guardian.stdout.readline())
        if force_quit:
            owner.kill()
            owner.wait(timeout=2)
        else:
            guardian.terminate()
        guardian.wait(timeout=8)
        deadline = time.monotonic() + 2
        while alive(worker_pid) and time.monotonic() < deadline:
            time.sleep(0.05)
        assert not alive(worker_pid), 'Guardian left its worker running'
    finally:
        for process in (guardian, owner):
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)
        if worker_pid and alive(worker_pid):
            os.kill(worker_pid, 9)
print('PASS guardian cleanup on normal exit and owner force-quit')
