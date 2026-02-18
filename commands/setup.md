---
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# PDF → 마크다운 플러그인 초기 설정

새 프로젝트에서 플러그인을 처음 사용할 때 경로와 권한을 대화형으로 설정합니다.

## 실행 순서

### 1단계: 현재 환경 확인

```bash
echo "=== 현재 환경 ==="
echo "프로젝트 디렉토리: $CLAUDE_PROJECT_DIR"
echo "플러그인 디렉토리: $CLAUDE_PLUGIN_DIR"
echo "사용자: $(whoami)"
echo "홈 디렉토리: $HOME"
echo ""

# 기존 설정 파일 확인
if [ -f "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env" ]; then
    echo "=== 기존 설정 발견 ==="
    cat "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env"
    echo ""
fi
```

### 2단계: 사용자에게 경로 설정 질문

AskUserQuestion으로 다음을 물어본다:

**질문 1 — PDF 원본 경로**
- header: "PDF 경로"
- question: "변환할 PDF 파일들이 있는 디렉토리 경로를 알려주세요. (분할된 chunk PDF가 있는 폴더)"
- options:
  - `$CLAUDE_PROJECT_DIR/pdf-source/chunks` — "프로젝트 내 기본 경로"
  - `$HOME/pdf-source/chunks` — "홈 디렉토리 기준"
- (사용자가 Other로 직접 경로를 입력할 수도 있음)

**질문 2 — 마크다운 출력 경로**
- header: "출력 경로"
- question: "변환된 마크다운 파일을 저장할 디렉토리 경로를 알려주세요."
- options:
  - `$CLAUDE_PROJECT_DIR/pdf-source/output` — "프로젝트 내 기본 경로"
  - `$HOME/pdf-source/output` — "홈 디렉토리 기준"
- (사용자가 Other로 직접 경로를 입력할 수도 있음)

**질문 3 — 공유 큐 경로**
- header: "큐 경로"
- question: "공유 큐 디렉토리 경로를 알려주세요. 여러 사용자/터미널이 같은 큐를 공유합니다."
- options:
  - `$CLAUDE_PROJECT_DIR/.queue` — "프로젝트 루트 .queue/ (권장)"
  - `$HOME/.queue` — "홈 디렉토리 기준"
- (사용자가 Other로 직접 경로를 입력할 수도 있음)

### 3단계: 설정 파일 생성

사용자 응답을 바탕으로 `.claude/pdf-queue.env` 파일을 생성한다.
이 파일은 config.sh가 자동으로 로드한다.

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

cat > "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env" << EOF
# PDF → 마크다운 플러그인 경로 설정
# 생성: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 사용자: $(whoami)@$(hostname -s)
#
# config.sh가 이 파일을 자동으로 로드합니다.
# 경로를 변경하려면 이 파일을 직접 수정하세요.

PDF_DIR="${사용자가_선택한_PDF_경로}"
MD_DIR="${사용자가_선택한_MD_경로}"
QUEUE_DIR="${사용자가_선택한_QUEUE_경로}"
EOF

echo "설정 파일 생성 완료: $CLAUDE_PROJECT_DIR/.claude/pdf-queue.env"
cat "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env"
```

### 4단계: 경로 존재 확인 및 생성

```bash
source "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env"

for dir in "$PDF_DIR" "$MD_DIR" "$MD_DIR/images" "$QUEUE_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "디렉토리 생성: $dir"
        mkdir -p "$dir"
    else
        echo "확인 완료: $dir"
    fi
done
```

### 5단계: 권한 설정

`.claude/settings.local.json`이 없으면 자동 생성한다.

```bash
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/settings.local.json" ]; then
    cat > "$CLAUDE_PROJECT_DIR/.claude/settings.local.json" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Task(*)",
      "Glob(*)",
      "Grep(*)"
    ]
  }
}
SETTINGS
    echo "권한 설정 완료: $CLAUDE_PROJECT_DIR/.claude/settings.local.json"
else
    echo "기존 권한 설정 유지: $CLAUDE_PROJECT_DIR/.claude/settings.local.json"
fi
```

### 6단계: 설정 검증

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
echo ""
echo "=== 최종 설정 확인 ==="
echo "PDF 디렉토리:    $PDF_DIR"
echo "마크다운 출력:    $MD_DIR"
echo "이미지 디렉토리:  $IMG_DIR"
echo "공유 큐:         $QUEUE_DIR"
echo "인스턴스 ID:     $INSTANCE_ID"
echo ""

# PDF 파일 수 확인
pdf_count=$(ls "$PDF_DIR"/*.pdf 2>/dev/null | wc -l || echo 0)
echo "PDF 파일 수: ${pdf_count}개"

if [ "$pdf_count" -gt 0 ]; then
    echo ""
    echo "설정 완료! 다음 명령으로 시작하세요:"
    echo "  /pdf-to-markdown init    # 큐 초기화"
    echo "  /pdf-to-markdown start   # 변환 시작"
else
    echo ""
    echo "설정 완료! PDF 파일을 $PDF_DIR 에 넣은 후:"
    echo "  /pdf-to-markdown init    # 큐 초기화"
    echo "  /pdf-to-markdown start   # 변환 시작"
fi
```

## 참고

- 설정 파일 위치: `$CLAUDE_PROJECT_DIR/.claude/pdf-queue.env`
- 설정을 변경하려면 이 파일을 직접 수정하거나 `/pdf-to-markdown:setup`을 다시 실행
- `.claude/pdf-queue.env`는 `.gitignore`에 추가하는 것을 권장 (사용자별 경로가 다를 수 있음)
- 여러 사용자가 같은 프로젝트를 사용할 때는 `/pdf-to-markdown:cowork`를 참고
