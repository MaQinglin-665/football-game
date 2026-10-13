"""Finite offline matches and evidence summaries. Does not tune or edit the AI."""
from pathlib import Path
import argparse
import collections
import datetime
import hashlib
import json
import subprocess

SOURCE = Path(__file__).resolve().parents[1]
BASELINE = SOURCE.parent.parent / 'dribble039_sim_review' / 'source'
ENGINE = Path(r'C:\Users\MQL\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe')


def fingerprint(source):
    digest = hashlib.sha256()
    for file in sorted(source.rglob('*.gd')):
        if '.godot' not in file.parts and 'tests' not in file.parts:
            digest.update(file.relative_to(source).as_posix().encode())
            digest.update(file.read_bytes())
    return digest.hexdigest()


def summarize(files, destination):
    reports = []
    lines = ['AI 自动对战复盘', '',
             '这是短时间自然开局的对照，不是整场胜率或整体智力评级。',
             '传球完成以实际接球接触为准；疑似停顿需人工复核。',
             '每个文件包含0.2秒采样轨迹和真实触球事件，可按时间回查。', '']
    for file in files:
        data = json.loads(file.read_text(encoding='utf-8'))
        event_counts = collections.Counter(e['event'] for e in data['receive_events'])
        cancellations = collections.Counter(e['reason'] for e in data['receive_events'] if e['event'] == 'CANCEL')
        outs = [e for e in data['incidents'] if e.get('state') == 'STOPPAGE' and e.get('restart', {}).get('reason') in ('touchline', 'goal_line')]
        stalls = [e for e in data['incidents'] if e['type'] == 'carrier_stall_candidate']
        report = dict(file=str(file), seed=data['seed'], all_ai=data['all_ai'],
                      simulated_seconds=data['duration_sim_seconds'], live_seconds=data['live_seconds'],
                      stats=data['stats'], receptions=dict(event_counts), cancellations=dict(cancellations),
                      stall_candidates=stalls, out_incidents=outs)
        reports.append(report)
        lines.extend([file.name,
                      f"  有效比赛 {data['live_seconds']:.2f} 秒；场上 AI {data['actors']} / 物理角色 {data['physics_actors']}",
                      f"  传球 {data['stats']['ai_passes']}；射门 {data['stats']['ai_shots']}；出界 {data['stats']['outs']}",
                      f"  接球计划完成 {event_counts['COMPLETE']} / 启动 {event_counts['START']}；取消 {event_counts['CANCEL']}（未结束不能算失败）",
                      f"  取消原因 {dict(cancellations)}；疑似持球停顿 {len(stalls)}"])
        for event in outs + stalls:
            lines.append(f"  回查时间 {event['t']:.2f}s：{event.get('restart', {}).get('reason', event['type'])}")
        lines.append('')
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'summary.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
    (destination / '复盘报告.txt').write_text('\n'.join(lines), encoding='utf-8')
    print(destination / '复盘报告.txt', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, default=45, choices=range(15, 121))
    parser.add_argument('--full-match', action='store_true')
    parser.add_argument('--summarize', nargs='+', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    destination = args.output or SOURCE.parent / 'verification' / datetime.datetime.now().strftime('review_%Y%m%d_%H%M%S_%f')
    if args.summarize:
        summarize(args.summarize, destination)
        return
    destination.mkdir(parents=True)
    manifest = {'full_match': args.full_match, 'watchdog_sim_seconds': 2400 if args.full_match else args.seconds, 'regulation_seconds': 1200 if args.full_match else None, 'baseline': str(BASELINE), 'candidate': str(SOURCE),
                'baseline_hash': fingerprint(BASELINE), 'candidate_hash': fingerprint(SOURCE),
                'seeds': [390109] if args.full_match else [390109, 390110], 'kickoff_teams': [0] if args.full_match else [0, 1],
                'note': 'Headless fixed simulation delta; not FPS evidence. All modifications require developer review.'}
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    files = []
    for label, source in [('before', BASELINE), ('after', SOURCE)]:
        for seed in manifest['seeds']:
            target = destination / f'{label}_{seed}.json'
            log = target.with_suffix('.log')
            print(f'{label} / seed {seed} / ' + ('full regulation match' if args.full_match else f'{args.seconds} simulated seconds'), flush=True)
            command = [str(ENGINE), '--headless', '--fixed-fps', '120', '--path', str(source),
                       '--script', str(SOURCE / 'tests/ai_match_review.gd'), '--',
                       f'--seconds={2400 if args.full_match else args.seconds}', f'--seed={seed}', f'--out={target.as_posix()}']
            if args.full_match:
                command.append('--full-match')
            with log.open('w', encoding='utf-8') as stream:
                result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=7200 if args.full_match else 300)
            errors = log.read_text(encoding='utf-8', errors='replace')
            if result.returncode or not target.exists() or 'SCRIPT ERROR' in errors or 'Parse Error' in errors:
                raise RuntimeError(f'Run failed; inspect {log}')
            files.append(target)
    if args.full_match:
        from summarize_full_match import summary
        reports = [summary(p) for p in files]
        (destination / 'full_summary.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
        print(destination / 'full_summary.json', flush=True)
        if not all(r['full_time'] for r in reports):
            raise RuntimeError('A run did not reach FULL_TIME; inspect the trajectory before calling this a complete match.')
    else:
        summarize(files, destination)


if __name__ == '__main__':
    main()
