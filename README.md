# TOY CLASH — Clash Mini 스타일 Godot 프로토타입

Supercell *Clash Mini* 의 게임 필(장난감 디오라마·데포르메 피규어·쫄깃한 모션·VFX)을 Godot 4 로 재현한 프로토타입.
모든 모델·텍스처·사운드는 **코드로 절차 생성**하며 외부 에셋은 쓰지 않았습니다.

## 문서
- [docs/01_리서치_클래시미니_분석.md](docs/01_리서치_클래시미니_분석.md): 규칙과 시각 분석(컬러·모델링·조명·UI·애니메이션·VFX), 참고 이미지 `docs/refs/`
- [docs/02_기획서_TOY_CLASH.md](docs/02_기획서_TOY_CLASH.md): 전체 기획서(코어 루프, 유닛, 아트/모션/VFX 명세, 기술 설계, 우선순위)

## 실행
Godot 4.7(설치됨: winget `GodotEngine.GodotEngine.Mono`)로 이 폴더를 열고 F5를 누릅니다. 명령줄로 실행하려면:

```bash
"$HOME/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe" --path .
```

## 조작
| 입력 | 동작 |
|---|---|
| 트레이 미니 드래그 → 내 진영(아래 4줄) 타일 | 구매 + 배치 (엘릭서 소모) |
| 같은 미니 위에 드롭 | ★ 업그레이드(합성, 최대 3★) |
| 보드 위 내 유닛 드래그 | 재배치 / 자리 교환 |
| 리롤 버튼 / `R` | 트레이 새로 뽑기 (라운드당 1회 무료, 누적) |
| FIGHT! / `Space` | 배치 종료, 전투 시작 |
| `Esc` | 종료 |

## 개발용 인자 (`--` 뒤에 붙임)
- `--autoplay`: AI 대 AI로 자동 진행
- `--shots=<dir>`: 주요 순간(배치, CLASH, 전투, 결과)을 PNG로 저장
- `--cam=close`: 근접 카메라(모델 확인용)
- `--selftest`: 드래그 배치, 합성, 잘못된 드롭 거부, 재배치를 입력 시뮬레이션으로 검증
- `--quit=<초>`: 지정 시간 뒤 종료

## 구조
```
scripts/
  main.gd        게임 흐름 상태머신, 드래그&드롭, 트레이, 경제
  data.gd        유닛 데이터 (스탯/능력)
  unit.gd        유닛 로직 (타겟팅, 자유 이동, 공격, 에너지/슈퍼, Clash 능력)
  unit_model.gd  절차적 치비 모델 + 모션(숨쉬기, 홉 이동, 공격 3단, 스쿼시, 플래시)
  vfx.gd         VFX 팩토리 (퍼프, 별 스파크, 링, 투사체, 폭발, 슬램, 컨페티)
  hud.gd         HUD (HP바, 데미지 숫자, 배너, 엘릭서 병, 버튼)
  world.gd       숲 디오라마, 보드, 조명, 포스트 FX, 벤치 트레이
  camera_rig.gd  셰이크, 히트스톱, FOV 킥
  sfx.gd         절차적 효과음 합성
  ai.gd          상대 AI (구매/업그레이드/리롤/배치)
  mats.gd        머티리얼과 절차적 텍스처
```

## 실행 파일 (Windows)
- `build/ToyClash.exe`를 더블클릭하면 실행됩니다. 같은 폴더의 `ToyClash.pck`(게임 데이터)와 `GodotSharp/`(.NET 런타임)가 반드시 함께 있어야 합니다.
- 배포용 압축본: `ToyClash_Windows.zip` (약 112 MB). 압축을 푼 뒤 exe를 실행하세요.
- 다시 빌드하는 방법: 게임 데이터만 새로 뽑아 `build/ToyClash.pck`를 덮어씁니다.
  ```bash
  "<Godot 설치 폴더>/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . --export-pack "Windows Desktop" build/ToyClash.pck
  ```
- 참고: 공식 export 템플릿이 설치되어 있지 않아서, 설치된 Godot 4.7.2 런타임 exe에 pck를 붙이는 방식으로 만들었습니다. 템플릿(약 1 GB)을 설치하면 `--export-release`로 더 가벼운 정식 빌드를 만들 수 있습니다.

## 시연 영상
- `video/ToyClash_demo.avi` (약 49초, 540×960, 30fps, 효과음 포함): 시작부터 1라운드 전투와 2라운드 준비 화면까지.
- 다시 녹화하려면 Godot Movie Maker를 사용합니다. `--demo`는 가짜 커서로 실제 입력을 흉내 내고 기능 자막을 띄우는 시연 모드입니다.
  ```bash
  "<Godot 설치 폴더>/Godot_v4.7.2-stable_mono_win64_console.exe" --path . --fixed-fps 30 --write-movie video/ToyClash_demo.avi -- --demo --seed=1
  ```
