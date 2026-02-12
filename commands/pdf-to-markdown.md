---
allowed-tools: Bash, Read, Write, Edit, Task, Glob, Grep, WebFetch, WebSearch
---

# PDF → 마크다운 변환 시스템

PDF 파일들을 마크다운으로 변환하는 통합 커맨드입니다.

## 경로 설정

모든 경로는 `$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh`에서 관리합니다.
경로를 확인하려면:
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
echo "PDF: $PDF_DIR"
echo "MD: $MD_DIR"
echo "큐: $QUEUE_FILE"
```

## 사용법

### 1. 큐 초기화 (처음 시작할 때)
```
/pdf-to-markdown init
```
- 미처리 PDF 목록을 큐 파일에 저장
- 마크다운/images 디렉토리 생성

### 2. 배치 실행
```
/pdf-to-markdown start [개수]
```
- 기본 10개, 숫자 지정 시 해당 개수만큼 병렬 실행
- 예: `/pdf-to-markdown start 5` → 5개 실행

### 3. 상태 확인
```
/pdf-to-markdown status
```
- 완료/실행중/대기 현황 표시

---

## 실행 로직

### init 명령

```bash
# 경로 로드
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"

# 디렉토리 생성
mkdir -p "$IMG_DIR"

# 미처리 PDF를 큐에 저장
for pdf in "$PDF_DIR"/*.pdf; do
  basename=$(basename "$pdf" .pdf)
  md="$MD_DIR/${basename}.md"
  if [ ! -f "$md" ]; then
    echo "$basename"
  fi
done | sort > "$QUEUE_FILE"
```

### start 명령

1. 큐에서 N개 가져오기: `head -N "$QUEUE_FILE"`
2. 각각에 대해 Task 도구로 백그라운드 에이전트 실행
3. 큐에서 제거: `tail -n +$((N+1)) "$QUEUE_FILE" > /tmp/q.txt && mv /tmp/q.txt "$QUEUE_FILE"`

### status 명령

```bash
bash "$CLAUDE_PLUGIN_DIR/hooks/check-failed-tasks.sh"
```

---

## 에이전트 프롬프트 템플릿

```
PDF 파일을 마크다운으로 변환하세요.

PDF: $PDF_DIR/[파일명].pdf
저장: $MD_DIR/[파일명].md

작업:
1. Read로 PDF 읽기
2. 마크다운 변환 (# 제목, ### 조항, **용어**, 표)
3. Write로 저장
4. Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "[PDF경로]" -o "$IMG_DIR" -v
5. 완료 보고
```

---

## 자동 연속 실행

에이전트 완료 알림을 받으면:
1. 큐에 남은 항목 확인
2. 있으면 다음 1개 자동 실행
3. 항상 10개 에이전트가 병렬 실행되도록 유지

---

## 필요 권한

settings.local.json에 다음 권한이 필요합니다:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Task(*)",
      "Glob(*)",
      "Grep(*)"
    ]
  }
}
```
