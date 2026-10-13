from pathlib import Path
import subprocess,psutil,time,json,sys
R=Path(sys.argv[3]) if len(sys.argv)>3 else Path('D:/瓒崇悆娓告垙/鎸佺画鏁村悎/candidate-r006');E='D:/瓒崇悆娓告垙/鎸佺画鏁村悎/runtime/Godot.exe'
def gods():
 return [p.pid for p in psutil.process_iter(['name']) if 'godot' in (p.info['name'] or '').lower()]
for tier,effect in [(int(sys.argv[1]),int(sys.argv[2]))]:
 if gods():raise RuntimeError('Other Godot active: '+str(gods()))
 folder=R/'evidence'/('native_'+str(tier)+'_e'+str(effect)+('_taa_off' if 'taa-off' in sys.argv else ''));folder.mkdir(parents=True,exist_ok=True)
 with (folder/'native.log').open('w',encoding='utf-8') as log:
  p=subprocess.Popen([E,'--path',str(R/'source'),'--rendering-method','forward_plus','--audio-driver','Dummy','--script','res://tests/native_r006_bench.gd','--','--seconds=3000','--seed=391016','--out='+str(folder/'natural.json'),'--settings-file=user://r006_bench_clean.cfg','--tier='+str(tier),'--effects='+str(effect),'--folder='+str(folder)]+(['--taa-off'] if 'taa-off' in sys.argv else []),stdout=log,stderr=subprocess.STDOUT)
  proc=psutil.Process(p.pid);proc.cpu_percent();monitor=[];started=time.time()
  while p.poll() is None:
   others=[i for i in gods() if i!=p.pid]
   if others:p.terminate();raise RuntimeError('Concurrent Godot; aborted own run '+str(others))
   if time.time()-started>140:p.kill();raise RuntimeError('Native test timeout')
   try:
    gpu=subprocess.run(['nvidia-smi','--query-gpu=utilization.gpu,memory.used,power.draw,temperature.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=5).stdout.strip()
    monitor.append({'elapsed':time.time()-started,'process_cpu_percent':proc.cpu_percent(),'rss':proc.memory_info().rss,'gpu_csv':gpu})
   except psutil.NoSuchProcess:break
   time.sleep(1)
  p.wait();(folder/'hardware.json').write_text(json.dumps(monitor,indent=2));print('done',tier,effect,p.returncode,'seconds',round(time.time()-started,1),flush=True)
 text=(folder/'native.log').read_text(encoding='utf-8',errors='replace');print('\n'.join(x for x in text.splitlines() if 'ERROR' in x or 'NATIVE_R006' in x or 'Vulkan' in x)[:4000],flush=True)
