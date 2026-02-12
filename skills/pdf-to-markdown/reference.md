# PDF → 마크다운 변환 플러그인 레퍼런스

## 플러그인 구조

공식 Claude Code 플러그인 구조를 따릅니다. `claude --plugin-dir ./pdf-to-markdown-plugin`으로 로드합니다.

```
pdf-to-markdown-plugin/
├── .claude-plugin/
│   └── plugin.json              # 플러그인 매니페스트
├── skills/
│   └── pdf-to-markdown/
│       ├── SKILL.md             # 스킬 정의
│       ├── config.sh            # 경로 설정 (★ 새 프로젝트에서 이것만 수정)
│       ├── reference.md         # 이 파일
│       └── scripts/
│           ├── split_pdf.py     # PDF 분할 (11페이지 이상 → 10페이지씩)
│           ├── extract_images.py # 이미지 추출 (조각 합침, 벡터 포함)
│           └── verify_markdown.py # 검증 스크립트
├── hooks/
│   ├── hooks.json               # 후크 선언
│   ├── check-failed-tasks.sh    # Stop 후크
│   └── auto-next-batch.sh       # SubagentStop/UserPromptSubmit 후크
└── commands/
    ├── pdf-to-markdown.md       # 변환 커맨드
    └── next-batch.md            # 배치 실행 커맨드
```

### 새 프로젝트에서 사용하기

1. 플러그인 폴더 복사 또는 `claude plugin install`
2. `skills/pdf-to-markdown/config.sh`에서 경로 수정:
   ```bash
   PDF_DIR="$PROJECT_DIR/path/to/pdf"
   MD_DIR="$PROJECT_DIR/path/to/markdown"
   IMG_DIR="$MD_DIR/images"
   ```
3. `claude --plugin-dir ./pdf-to-markdown-plugin`으로 실행

---

## config.sh

모든 경로의 단일 진실 원천(Single Source of Truth)입니다.
스크립트, 후크, 커맨드 모두 이 파일을 `source`합니다.

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-...}"
PLUGIN_DIR="${CLAUDE_PLUGIN_DIR:-...}"
PDF_DIR="$PROJECT_DIR/KR_강선규칙_2025/분할"
MD_DIR="$PROJECT_DIR/KR_강선규칙_2025/마크다운"
IMG_DIR="$MD_DIR/images"
QUEUE_FILE="$PROJECT_DIR/.claude/pdf-queue.txt"
SKILL_DIR="$PLUGIN_DIR/skills/pdf-to-markdown"
```

---

## 후크 설정

### 등록된 후크

플러그인의 `hooks/hooks.json`에서 자동 등록됩니다.

| 이벤트 | 스크립트 | 동작 |
|--------|----------|------|
| `Stop` | `check-failed-tasks.sh` | 대화 종료 시 변환 현황 보고 |
| `UserPromptSubmit` | `auto-next-batch.sh` | 사용자 메시지 시 큐 상태 안내 |
| `SubagentStop` | `auto-next-batch.sh` | 에이전트 완료 시 다음 배치 안내 |

### 자동 연속 실행 흐름

```
[에이전트 완료]
    ↓
[SubagentStop 후크 → auto-next-batch.sh]
    ↓
[큐 상태 출력: "ACTION: 다음 파일들을 실행하세요"]
    ↓
[Claude가 출력을 보고 다음 에이전트 실행]
    ↓
[큐에서 해당 항목 제거]
```

---

## 작업 큐

### 파일: `$QUEUE_FILE` (config.sh에서 정의)

한 줄에 하나의 파일명 (확장자 제외):
```
강선규칙_0201-0210
강선규칙_0211-0220
```

### 큐 관리
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"

# 큐 초기화
for pdf in "$PDF_DIR"/*.pdf; do
  basename=$(basename "$pdf" .pdf)
  md="$MD_DIR/${basename}.md"
  [ ! -f "$md" ] && echo "$basename"
done | sort > "$QUEUE_FILE"

# 큐에서 N개 제거
tail -n +$((N+1)) "$QUEUE_FILE" > /tmp/q.txt && mv /tmp/q.txt "$QUEUE_FILE"
```

---

## 마크다운 변환 규칙

| 요소 | 마크다운 문법 |
|------|--------------|
| 편 제목 | `#` |
| 장 제목 | `##` |
| 절 제목 | `##` |
| 조항 번호 | `###` (예: `### 101. 용어의 정의`) |
| 용어 정의 | `**용어**` |
| 표 | 마크다운 표 문법 |
| 목록 | `-` 또는 숫자 목록 |
| 이미지 | `![설명](images/파일명.png)` |

---

## 이미지 추출 (extract_images.py)

### 동작 원리
1. PDF 내 이미지 오브젝트의 위치(bbox) 파악
2. 같은 페이지에서 y좌표가 근접한 이미지 조각을 자동 그룹핑
3. 그룹 영역을 300dpi로 클립 렌더링 (벡터 그래픽 포함)
4. 캡션이 있으면 파일명에 반영, 없으면 페이지+순번

### 결과 파일명
- 캡션 있음: `그림_1.2.1_화물창의_대표적인_횡단면.png`
- 캡션 없음: `강선규칙_0021-0030_p07_01.png`

---

## 검증

```bash
python3 "$SKILL_DIR/scripts/verify_markdown.py" "$PDF_DIR/XXX.pdf" "$MD_DIR/XXX.md" -v
```

기준: 커버리지 90% 이상이면 양호
