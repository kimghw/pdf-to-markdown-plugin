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

## 실행 로직 (자동 상태 판단)

`$ARGUMENTS`가 `init`, `start`, `status`, `recover`, `migrate` 중 하나이면 해당 명령을 직접 실행한다.

**`$ARGUMENTS`가 비어있거나 위 명령이 아닌 경우**, 아래 자동 판단 로직을 실행한다:

### 0단계: 상태 확인

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
```

다음 3가지 조건을 순서대로 확인한다:

**조건 A: 큐가 초기화되지 않은 경우** (`$QUEUE_DIR/pending` 디렉토리가 없음)
→ `init` 실행 후 `start` 로직으로 진행

**조건 B: 대기 작업이 있고 이 인스턴스의 작업중이 0개인 경우**
→ `start` 로직 실행 (사용자에게 개수/범위 물어봄)

**조건 C: 이 인스턴스에 작업중인 것이 있는 경우**
→ 현재 상태를 보여주고, 추가 작업을 할당할지 물어봄 (next-batch 로직)

**조건 D: 대기 작업이 0개인 경우**
→ "모든 작업이 완료되었습니다" 메시지 출력, status 표시

---

## 명시적 명령어

### init 명령

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" init
```

- 큐 디렉토리 생성 (pending/, processing/, done/, failed/)
- 미변환 PDF를 pending/에 .task 파일로 등록
- 이미 변환된 PDF는 done/으로 기록

### start 명령

**1단계: 사용자에게 처리 방식 확인**

먼저 현재 큐 상태를 보여주고, AskUserQuestion으로 다음 두 가지를 **하나의 AskUserQuestion에 2개 질문**으로 물어본다:

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
bash "$QUEUE_SCRIPT" status
```

질문 1 — **동시 실행할 에이전트 수**
- header: "병렬 수"
- options: 10개(권장), 5개, 3개

질문 2 — **이번 세션에서 처리할 총 개수**
- header: "처리 범위"
- options: 전체(대기 중인 모든 PDF)(권장), 50개, 10개
- 사용자가 Other로 특정 범위(예: "0101~0200만") 또는 숫자를 지정할 수 있음

**2단계: 작업 할당**

사용자 응답에 따라:

- 개수 지정 시:
  ```bash
  RESULT=$(bash "$QUEUE_SCRIPT" claim ${동시에이전트수})
  ```

- 범위 지정 시:
  pending/ 목록에서 해당 범위의 파일만 필터링하여 개수를 계산한 뒤 claim한다.
  ```bash
  # pending 목록에서 범위 내 파일 확인
  bash "$QUEUE_SCRIPT" list pending
  # 범위 내 파일 수를 COUNT로 설정 후 claim
  RESULT=$(bash "$QUEUE_SCRIPT" claim ${동시에이전트수})
  ```

RESULT의 첫 줄이 `CLAIMED:N`이면 이후 줄들이 작업 이름입니다.
`NO_TASKS_AVAILABLE`이면 큐가 비었습니다.

**3단계: 에이전트 실행 (총량 제한)**

claim된 작업에 대해 Task 도구로 백그라운드 에이전트를 실행합니다.
동시 병렬은 사용자가 선택한 수, 총 처리량이 `TOTAL_LIMIT`에 도달하면 **더 이상 claim하지 않고 멈춘다.**

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
2. 마크다운 변환 (# 제목, ### 조항, **용어**, 표) — 원문 그대로 변환, 요약하거나 생략 금지
3. Write로 저장
4. 이미지 추출:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "$PDF_DIR/[파일명].pdf" -o "$IMG_DIR" -v
5. 검증:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/verify_markdown.py" "$PDF_DIR/[파일명].pdf" "$MD_DIR/[파일명].md" -v
6. 검증 결과 확인: 원문 텍스트 누락이 있으면 수정 후 재검증. 유니코드 차이는 무시.
7. 완료 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" complete "[파일명]"
8. 실패 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" fail "[파일명]" "에러 설명"
```

**중요**: 에이전트가 직접 `complete` 또는 `fail`을 호출해야 작업 상태가 즉시 업데이트됩니다.

---

## 자동 연속 실행 (총량 제한 적용)

에이전트 완료 알림을 받으면:
1. 지금까지 완료(complete + fail)된 작업 수를 카운트
2. 완료 수 + 현재 processing 수 < `TOTAL_LIMIT`이면:
   - `bash "$QUEUE_SCRIPT" claim 1`로 다음 작업 할당
   - 에이전트 실행
3. `TOTAL_LIMIT`에 도달하면:
   - **더 이상 claim하지 않고 멈춤**
   - "지정한 N개 처리 완료" 메시지 출력
4. 동시 병렬은 사용자가 선택한 수 유지

---

## 멀티 인스턴스 동시 사용

여러 터미널에서 동시에 작업할 수 있습니다. 각 인스턴스는 PID 기반 고유 ID로 구분되며, `mv` 명령의 원자성으로 동일 작업이 중복 할당되지 않습니다.

- **큐 초기화**: 한 터미널에서 이미 실행했다면, 다른 터미널에서는 `/pdf-to-markdown`만 실행 (자동으로 start 진행)
- **세션 종료**: 각 인스턴스의 Stop 후크가 미완료 작업을 pending/으로 자동 반환
- **stale 복구**: `claim` 시 30분 초과 작업을 자동 복구하므로 별도 조치 불필요

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
