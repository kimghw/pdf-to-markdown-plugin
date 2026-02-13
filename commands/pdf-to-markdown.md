---
allowed-tools: Bash, Read, Write, Edit, Task, Glob, Grep, WebFetch, WebSearch
---

# PDF → 마크다운 변환 시스템 (공유 큐)

PDF 파일들을 마크다운으로 변환하는 통합 커맨드입니다.
디렉토리 기반 공유 큐를 사용하여 여러 Claude Code 인스턴스에서 동시에 작업할 수 있습니다.

## 경로 설정

모든 경로는 `$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh`에서 관리합니다.
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
echo "PDF: $PDF_DIR"
echo "MD: $MD_DIR"
echo "큐: $QUEUE_DIR"
echo "인스턴스: $INSTANCE_ID"
```

## 멀티 인스턴스 동시 사용

여러 터미널에서 동시에 작업할 수 있습니다. 각 인스턴스는 PID 기반 고유 ID로 구분되며, `mv` 명령의 원자성으로 동일 작업이 중복 할당되지 않습니다.

```bash
# 터미널 A
cd /path/to/project && claude --plugin-dir ./pdf-to-markdown-plugin

# 터미널 B (동일 PC, 다른 터미널)
cd /path/to/project && claude --plugin-dir ./pdf-to-markdown-plugin
```

각 터미널에서 `/pdf-to-markdown start`를 실행하면 서로 다른 작업을 자동으로 할당받아 병렬 처리합니다.

## 사용법

### 1. 큐 초기화 (처음 1회만)
```
/pdf-to-markdown init
```
- 큐 디렉토리 생성 (pending/, processing/, done/, failed/)
- 미변환 PDF를 pending/에 .task 파일로 등록
- 이미 변환된 PDF는 done/으로 기록

> **주의**: `init`은 프로젝트당 **최초 1회만** 실행합니다. 두 번째 터미널부터는 `init` 없이 바로 `start`를 실행하세요. 이미 초기화된 큐에서 `init`을 다시 실행하면 신규 PDF만 추가 등록되고 기존 상태는 유지됩니다.

### 2. 배치 실행
```
/pdf-to-markdown start [개수]
```
- 기본 10개, 숫자 지정 시 해당 개수만큼 병렬 실행
- pending/에서 원자적으로 할당 (다른 인스턴스와 충돌 없음)
- 여러 터미널에서 동시에 실행해도 안전

### 3. 상태 확인
```
/pdf-to-markdown status
```
- 대기/작업중/완료/실패 현황 표시
- 어떤 인스턴스가 어떤 작업을 처리중인지 표시

### 4. stale 작업 복구
```
/pdf-to-markdown recover
```
- 30분 이상 processing에 있는 작업을 pending으로 되돌림
- 마크다운이 이미 생성된 작업은 done으로 이동

### 5. 레거시 큐 이전
```
/pdf-to-markdown migrate
```
- 기존 pdf-queue.txt를 디렉토리 기반 큐로 이전
- 이전 완료 후 레거시 파일은 `.migrated` 확장자로 이름 변경

---

## 동시 사용 시 주의사항

- **큐 초기화**: 한 터미널에서 `init`을 이미 실행했다면, 다른 터미널에서는 생략하고 바로 `start` 실행
- **세션 종료**: 각 인스턴스의 Stop 후크가 미완료 작업을 pending/으로 자동 반환
- **stale 복구**: `claim` 시 30분 초과 작업을 자동 복구하므로 별도 조치 불필요
- **인스턴스 식별**: `hostname_pid-$$` 형식으로 자동 생성 (충돌 없음)

---

## 실행 로직

### init 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" init
```

### start 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"

# N개 작업을 원자적으로 할당
RESULT=$(bash "$QUEUE_SCRIPT" claim ${COUNT:-10})
```

RESULT의 첫 줄이 `CLAIMED:N`이면 이후 줄들이 작업 이름입니다.
`NO_TASKS_AVAILABLE`이면 큐가 비었습니다.

각 작업에 대해 Task 도구로 백그라운드 에이전트를 실행합니다.

### status 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" status
```

### recover 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" recover
```

### migrate 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" migrate
```

---

## 에이전트 프롬프트 템플릿

각 작업에 대해 아래 프롬프트로 Task 에이전트를 실행합니다:

```
PDF 파일을 마크다운으로 변환하세요.

PDF: $PDF_DIR/[파일명].pdf
저장: $MD_DIR/[파일명].md

작업:
1. Read로 PDF 읽기
2. 마크다운 변환 (# 제목, ### 조항, **용어**, 표)
3. Write로 저장
4. 이미지 추출:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "$PDF_DIR/[파일명].pdf" -o "$IMG_DIR" -v
5. 검증:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/verify_markdown.py" "$PDF_DIR/[파일명].pdf" "$MD_DIR/[파일명].md" -v
6. 완료 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" complete "[파일명]"
7. 실패 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" fail "[파일명]" "에러 설명"
```

**중요**: 에이전트가 직접 `complete` 또는 `fail`을 호출해야 작업 상태가 즉시 업데이트됩니다.

---

## 자동 연속 실행

에이전트 완료 알림을 받으면:
1. `bash "$QUEUE_SCRIPT" status`로 큐 확인
2. pending > 0이면 `bash "$QUEUE_SCRIPT" claim 1`로 다음 작업 할당
3. 에이전트 실행
4. 항상 10개 에이전트가 병렬 실행되도록 유지

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
